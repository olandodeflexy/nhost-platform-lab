#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 8 ]; then
  echo "usage: verify-promotion <registry-account-id> <source-region> <target-region> <repository> <version> <github-repository> <release-commit> <nonprod-codebuild-project>" >&2
  exit 2
fi

: "${GH_TOKEN:?GH_TOKEN is required to verify the GitHub attestation}"

registry_account_id="$1"
source_region="$2"
target_region="$3"
repository="$4"
version="$5"
github_repository="$6"
release_commit="$7"
nonprod_codebuild_project="$8"

if [[ ! "$registry_account_id" =~ ^[0-9]{12}$ ]]; then
  echo "registry account ID must contain 12 digits" >&2
  exit 2
fi
if [[ ! "$source_region" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] ||
  [[ ! "$target_region" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]]; then
  echo "source and target regions must be AWS region names" >&2
  exit 2
fi
if [[ ! "$repository" =~ ^[a-z0-9]+([._/-][a-z0-9]+)*$ ]]; then
  echo "repository is not a valid ECR repository name" >&2
  exit 2
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version must be X.Y.Z" >&2
  exit 2
fi
if [[ ! "$github_repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GitHub repository must be OWNER/REPOSITORY" >&2
  exit 2
fi
if [[ ! "$release_commit" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
  echo "release commit must be a 40- or 64-character Git object ID" >&2
  exit 2
fi
if [[ ! "$nonprod_codebuild_project" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{1,253}$ ]]; then
  echo "non-production CodeBuild project name is invalid" >&2
  exit 2
fi

source_registry="${registry_account_id}.dkr.ecr.${source_region}.amazonaws.com"
source_image_uri="${source_registry}/${repository}"
predicate_type="https://github.com/${github_repository}/attestations/nonprod-deployment/v1"
release_ref="refs/tags/demo-api@${version}"
signer_workflow="olandodeflexy/nhost-platform-lab/.github/workflows/demo-api-release-delivery.yml"

source_digest="$(aws ecr describe-images \
  --registry-id "$registry_account_id" \
  --region "$source_region" \
  --repository-name "$repository" \
  --image-ids "imageTag=${version}" \
  --query 'imageDetails[0].imageDigest' \
  --output text)"

if [[ ! "$source_digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo "source ECR version tag ${version} did not resolve to a sha256 digest" >&2
  exit 1
fi

# Replication is asynchronous. Wait up to thirty minutes for the regional copy,
# then require it to resolve to the exact source digest before deployment.
target_digest=""
for ((attempt = 1; attempt <= 120; attempt++)); do
  target_digest="$(aws ecr describe-images \
    --registry-id "$registry_account_id" \
    --region "$target_region" \
    --repository-name "$repository" \
    --image-ids "imageTag=${version}" \
    --query 'imageDetails[0].imageDigest' \
    --output text 2>/dev/null || true)"
  if [[ "$target_digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    break
  fi
  if [ "$attempt" -lt 120 ]; then
    sleep 15
  fi
done

if [[ ! "$target_digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo "regional ECR version tag ${version} was not available in ${target_region} after thirty minutes" >&2
  exit 1
fi
if [ "$target_digest" != "$source_digest" ]; then
  echo "regional digest does not match the immutable source version tag" >&2
  exit 1
fi

docker_config="$(mktemp -d)"
trap 'rm -rf "$docker_config"' EXIT
export DOCKER_CONFIG="$docker_config"

aws ecr get-login-password --region "$source_region" \
  | skopeo login \
    --authfile "$DOCKER_CONFIG/config.json" \
    --username AWS \
    --password-stdin \
    "$source_registry" >/dev/null

verification_file="${DOCKER_CONFIG}/verification.json"
gh attestation verify \
  "oci://${source_image_uri}@${source_digest}" \
  --repo "$github_repository" \
  --signer-workflow "$signer_workflow" \
  --predicate-type "$predicate_type" \
  --source-digest "$release_commit" \
  --source-ref "$release_ref" \
  --deny-self-hosted-runners \
  --format json >"$verification_file"

if ! jq -e \
  --arg version "$version" \
  --arg release_tag "demo-api@${version}" \
  --arg commit "$release_commit" \
  --arg image "$source_image_uri" \
  --arg digest "$source_digest" \
  --arg executor_project "$nonprod_codebuild_project" \
  'any(.[].verificationResult.statement.predicate;
    .environment == "nonprod" and
    .status == "succeeded" and
    .version == $version and
    .releaseTag == $release_tag and
    .commit == $commit and
    .image == $image and
    .digest == $digest and
    .executorProject == $executor_project and
    (.executorBuild | type == "string") and
    (.executorBuild | test("^" + $executor_project + ":[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")))' \
  "$verification_file" >/dev/null; then
  echo "no valid non-production deployment attestation matches version ${version}, commit ${release_commit}, and digest ${source_digest}" >&2
  exit 1
fi

echo "verified non-production digest for ${repository} in ${source_region}"
echo "verified regional replica digest for ${repository} in ${target_region}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "digest=${source_digest}" >>"$GITHUB_OUTPUT"
else
  echo "digest=${source_digest}"
fi
