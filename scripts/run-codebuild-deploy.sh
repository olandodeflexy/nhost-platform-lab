#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "usage: run-codebuild-deploy <project> <region> <release-tag> <release-commit> <expected-digest>" >&2
  exit 2
fi

project="$1"
region="$2"
release_tag="$3"
release_commit="$4"
expected_digest="$5"

if [[ ! "$project" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{1,253}$ ]]; then
  echo "invalid CodeBuild project name" >&2
  exit 2
fi
if [[ ! "$region" =~ ^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$ ]]; then
  echo "invalid AWS region" >&2
  exit 2
fi
if [[ ! "$release_tag" =~ ^demo-api@[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "release tag must be demo-api@X.Y.Z" >&2
  exit 2
fi
if [[ ! "$release_commit" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
  echo "release commit must be a full Git object ID" >&2
  exit 2
fi
if [[ ! "$expected_digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo "expected digest must be a sha256 digest" >&2
  exit 2
fi

for command in aws jq sha256sum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "required command is unavailable: $command" >&2
    exit 2
  fi
done

request_file="$(mktemp)"
chmod 600 "$request_file"
build_id=""
build_active=false

cleanup() {
  status="$?"
  if [ "$build_active" = true ] && [ -n "$build_id" ]; then
    echo "stopping the in-progress CodeBuild deployment" >&2
    aws codebuild stop-build \
      --region "$region" \
      --id "$build_id" \
      --output json >/dev/null 2>&1 || true
  fi
  rm -f "$request_file"
  return "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

token_seed="${GITHUB_REPOSITORY:-local}:${GITHUB_WORKFLOW:-workflow}:${GITHUB_RUN_ID:-manual}:${GITHUB_RUN_ATTEMPT:-1}:${project}:${release_tag}:${release_commit}:${expected_digest}"
idempotency_token="$(printf '%s' "$token_seed" | sha256sum | awk '{ print $1 }')"

jq -n \
  --arg project "$project" \
  --arg token "$idempotency_token" \
  --arg release_tag "$release_tag" \
  --arg release_commit "$release_commit" \
  --arg expected_digest "$expected_digest" \
  '{
    projectName: $project,
    idempotencyToken: $token,
    environmentVariablesOverride: [
      {name: "RELEASE_TAG", value: $release_tag, type: "PLAINTEXT"},
      {name: "RELEASE_COMMIT", value: $release_commit, type: "PLAINTEXT"},
      {name: "EXPECTED_DIGEST", value: $expected_digest, type: "PLAINTEXT"}
    ]
  }' >"$request_file"

echo "starting fixed CodeBuild deployment project: $project"
build_id="$(aws codebuild start-build \
  --region "$region" \
  --cli-input-json "file://$request_file" \
  --query 'build.id' \
  --output text)"

if [[ ! "$build_id" =~ ^${project}:[0-9a-f-]+$ ]]; then
  echo "CodeBuild returned an unexpected build identifier" >&2
  exit 1
fi
build_active=true

# The fixed projects allow five minutes in queue and thirty minutes running.
# Keep a small polling buffer so a successful build is not stopped at its
# configured boundary while still bounding a cancelled or stalled deployment.
deadline=$((SECONDS + 2220))
last_status=""
build_response=""

while ((SECONDS < deadline)); do
  build_response="$(aws codebuild batch-get-builds \
    --region "$region" \
    --ids "$build_id" \
    --query 'builds[0].{complete:buildComplete,status:buildStatus,project:projectName,arn:arn,log:logs.deepLink,exports:exportedEnvironmentVariables}' \
    --output json)"

  returned_project="$(jq -r '.project // empty' <<<"$build_response")"
  if [ "$returned_project" != "$project" ]; then
    echo "CodeBuild response did not belong to the requested project" >&2
    exit 1
  fi

  build_status="$(jq -r '.status // "UNKNOWN"' <<<"$build_response")"
  build_complete="$(jq -r '.complete // false' <<<"$build_response")"
  if [ "$build_status" != "$last_status" ]; then
    echo "CodeBuild deployment status: $build_status"
    last_status="$build_status"
  fi

  if [ "$build_complete" = true ]; then
    build_active=false
    break
  fi
  sleep 10
done

if [ "$build_active" = true ]; then
  echo "timed out while waiting for the CodeBuild deployment" >&2
  exit 1
fi

if [ "$(jq -r '.status' <<<"$build_response")" != "SUCCEEDED" ]; then
  log_link="$(jq -r '.log // empty' <<<"$build_response")"
  echo "CodeBuild deployment failed with status $(jq -r '.status // "UNKNOWN"' <<<"$build_response")" >&2
  if [[ "$log_link" == https://* ]]; then
    echo "private deployment log: $log_link" >&2
  fi
  exit 1
fi

if ! jq -e '
  (.exports | type == "array") and
  (.exports | length == 3) and
  ([.exports[].name] | sort == ["DEPLOYED_COMMIT", "DEPLOYED_DIGEST", "DEPLOYED_TAG"]) and
  ([.exports[].name] | unique | length == 3)
' <<<"$build_response" >/dev/null; then
  echo "CodeBuild returned missing, duplicate, or unexpected deployment coordinates" >&2
  exit 1
fi

deployed_tag="$(jq -r '.exports[] | select(.name == "DEPLOYED_TAG") | .value' <<<"$build_response")"
deployed_commit="$(jq -r '.exports[] | select(.name == "DEPLOYED_COMMIT") | .value' <<<"$build_response")"
deployed_digest="$(jq -r '.exports[] | select(.name == "DEPLOYED_DIGEST") | .value' <<<"$build_response")"

if [ "$deployed_tag" != "$release_tag" ] || [ "$deployed_commit" != "$release_commit" ] || [ "$deployed_digest" != "$expected_digest" ]; then
  echo "CodeBuild result did not match the requested release coordinates" >&2
  exit 1
fi

build_arn="$(jq -r '.arn // empty' <<<"$build_response")"
if [[ ! "$build_arn" =~ ^arn:[a-z0-9-]+:codebuild:[a-z0-9-]+:[0-9]{12}:build/${project}:[0-9a-f-]+$ ]]; then
  echo "CodeBuild returned an unexpected build ARN" >&2
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    printf 'build_id=%s\n' "$build_id"
    printf 'tag=%s\n' "$deployed_tag"
    printf 'commit=%s\n' "$deployed_commit"
    printf 'digest=%s\n' "$deployed_digest"
  } >>"$GITHUB_OUTPUT"
fi

echo "CodeBuild deployment succeeded with verified release coordinates"
