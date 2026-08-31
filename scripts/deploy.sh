#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "usage: deploy <overlay> <cluster-name> <aws-region> <image-uri> <sha256-digest>" >&2
  exit 2
fi

: "${KUSTOMIZE_ROOT:?KUSTOMIZE_ROOT must point to deploy/kustomize}"

overlay="$1"
cluster_name="$2"
aws_region="$3"
image_uri="$4"
digest="$5"

if [[ ! "$overlay" =~ ^(nonprod-eu-west-1|prod-eu-west-1|prod-us-east-1)$ ]]; then
  echo "unknown overlay: $overlay" >&2
  exit 2
fi
if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo "image digest must be a sha256 digest" >&2
  exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cp -R "$KUSTOMIZE_ROOT" "$workdir/kustomize"
kubeconfig="$workdir/kubeconfig"
export KUBECONFIG="$kubeconfig"

aws eks update-kubeconfig \
  --name "$cluster_name" \
  --region "$aws_region" \
  --kubeconfig "$kubeconfig" \
  --alias "$cluster_name" \
  --user-alias "$cluster_name" >/dev/null

cd "$workdir/kustomize/overlays/$overlay"
kustomize edit set image "demo-api=${image_uri}@${digest}"
kustomize build . | kubectl apply --server-side --field-manager=github-actions -f -
kubectl -n demo-api rollout status deployment/demo-api --timeout=5m
