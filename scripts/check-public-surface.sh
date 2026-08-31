#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for required_tool in git rg; do
  if ! command -v "$required_tool" >/dev/null 2>&1; then
    echo "public-surface check requires ${required_tool}" >&2
    exit 1
  fi
done

public_files=()
while IFS= read -r -d '' file; do
  public_files+=("$file")
done < <(git ls-files --cached --others --exclude-standard -z)

if [ "${#public_files[@]}" -eq 0 ]; then
  echo "public-surface check found no Git-addable files"
  exit 0
fi

blocked_files=()
for file in "${public_files[@]}"; do
  case "/${file}" in
    */.env.example | */.env.*.example)
      ;;
      */.env | */.env.* | */.aws/* | */.kube/* | */.docker/config.json | \
      */.terraform/* | */.terragrunt-cache/* | *.tfstate | *.tfstate.* | \
      *.tfplan | *.plan | */tfplan | */plan.out | *.pem | *.key | \
      *.p12 | *.pfx | *.jks | *.keystore | */id_rsa | */id_ed25519 | \
      */docs/aws-account-bootstrap-engineering-note.md | \
      */docs/cost-and-safety.md | \
      */docs/evidence-and-assumptions.md | \
      */services/demo-api/bin/* | */result | */result-* | */dist/*)
      blocked_files+=("$file")
      ;;
  esac
done

user_home_pattern='/''Users/[^/[:space:]]+'

set +e
content_matches="$(rg -l -P --no-messages \
  -e '(?<![0-9A-Za-z])[0-9]{12}(?![0-9A-Za-z])' \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'ASIA[0-9A-Z]{16}' \
  -e 'github_pat_[A-Za-z0-9_]{20,}' \
  -e 'gh[pousr]_[A-Za-z0-9]{20,}' \
  -e 'xox[baprs]-[A-Za-z0-9-]{10,}' \
  -e '-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----' \
  -e 'https?://[^[:space:]]+:[^[:space:]@]+@' \
  -e 'aws_(secret_access_key|session_token)[[:space:]]*[:=]' \
  -e '(?<![A-Za-z0-9])o-[a-z0-9]{10,32}(?![A-Za-z0-9])' \
  -e '(?<![A-Za-z0-9])ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}(?![A-Za-z0-9])' \
  -e '[A-Za-z0-9._%+-]+@yahoo\.com' \
  -e "$user_home_pattern" \
  -- "${public_files[@]}")"
rg_status=$?
set -e

if [ "$rg_status" -gt 1 ]; then
  echo "public-surface content scan could not complete" >&2
  exit "$rg_status"
fi

if [ "${#blocked_files[@]}" -gt 0 ] || [ -n "$content_matches" ]; then
  echo "public-surface check failed; review these filenames:" >&2
  if [ "${#blocked_files[@]}" -gt 0 ]; then
    printf '  %s\n' "${blocked_files[@]}" >&2
  fi
  if [ -n "$content_matches" ]; then
    while IFS= read -r file; do
      printf '  %s\n' "$file" >&2
    done <<<"$content_matches"
  fi
  echo "matched content is intentionally omitted from logs" >&2
  exit 1
fi

echo "public-surface check passed for ${#public_files[@]} Git-addable files"
