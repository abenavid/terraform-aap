#!/usr/bin/env bash
# Build the execution environment image for ansible-navigator / AAP.
# Requires: ansible-builder, Docker or Podman
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-terraform-aap-ee:latest}"
RUNTIME="${CONTAINER_RUNTIME:-}"

if [[ -z "$RUNTIME" ]]; then
  if command -v podman &>/dev/null; then
    RUNTIME=podman
  elif command -v docker &>/dev/null; then
    RUNTIME=docker
  else
    echo "Install podman or docker" >&2
    exit 1
  fi
fi

cd "$ROOT"
exec ansible-builder build \
  -f execution-environment/execution-environment.yml \
  -t "$IMAGE_NAME" \
  --container-runtime "$RUNTIME"
