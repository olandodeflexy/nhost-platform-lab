#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: publish-image <ecr-registry> <repository> <tag>" >&2
  exit 2
fi

: "${IMAGE_ARCHIVE:?IMAGE_ARCHIVE must point to the Nix-built OCI archive}"
: "${AWS_REGION:?AWS_REGION is required}"

registry="$1"
repository="$2"
tag="$3"
image_uri="${registry}/${repository}"

auth_dir="$(mktemp -d)"
trap 'rm -rf "$auth_dir"' EXIT
auth_file="${auth_dir}/auth.json"

aws ecr get-login-password --region "$AWS_REGION" \
  | skopeo login \
    --authfile "$auth_file" \
    --username AWS \
    --password-stdin \
    "$registry" >/dev/null

skopeo copy \
  --dest-authfile "$auth_file" \
  "docker-archive:${IMAGE_ARCHIVE}" \
  "docker://${image_uri}:${tag}"

digest="$(aws ecr describe-images \
  --region "$AWS_REGION" \
  --repository-name "$repository" \
  --image-ids "imageTag=${tag}" \
  --query 'imageDetails[0].imageDigest' \
  --output text)"

if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo "ECR returned an invalid digest: $digest" >&2
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "digest=${digest}" >>"$GITHUB_OUTPUT"
else
  echo "digest=${digest}"
fi
echo "published ${repository} in ${AWS_REGION}"
