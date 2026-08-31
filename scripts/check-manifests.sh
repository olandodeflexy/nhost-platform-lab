#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kustomize_root="${KUSTOMIZE_ROOT:-${repo_root}/deploy/kustomize}"

render() {
  local overlay="$1"
  if command -v kustomize >/dev/null 2>&1; then
    kustomize build "$overlay"
    return
  fi
  if command -v kubectl >/dev/null 2>&1; then
    kubectl kustomize "$overlay"
    return
  fi
  echo "kustomize or kubectl is required" >&2
  return 1
}

for overlay in "${kustomize_root}"/overlays/*; do
  [ -d "$overlay" ] || continue
  rendered="$(mktemp)"
  trap 'rm -f "$rendered"' EXIT
  render "$overlay" >"$rendered"

  if command -v kubeconform >/dev/null 2>&1; then
    kubeconform \
      -strict \
      -summary \
      -skip VMServiceScrape \
      -kubernetes-version 1.34.0 \
      <"$rendered"
  fi

  echo "validated $(basename "$overlay")"
  rm -f "$rendered"
  trap - EXIT
done
