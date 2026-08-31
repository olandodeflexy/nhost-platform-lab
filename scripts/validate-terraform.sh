#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
modules=(
  "infra/bootstrap"
  "infra/modules/ecr"
  "infra/modules/eks"
  "infra/modules/github-oidc-role"
  "infra/modules/network"
  "infra/modules/platform-addons"
)

for module in "${modules[@]}"; do
  echo "validating ${module}"
  terraform -chdir="${repo_root}/${module}" init -backend=false -input=false >/dev/null
  terraform -chdir="${repo_root}/${module}" validate
done
