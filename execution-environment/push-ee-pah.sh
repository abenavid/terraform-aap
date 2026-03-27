#!/usr/bin/env bash
# Tag and push the EE to Private Automation Hub's container registry.
#
# Prerequisites:
#   - Image already built (./build-ee.sh), default local name: terraform-aap-ee:latest
#   - In PAH UI, create a container repository under your organization if required
#   - Hub route must respond (not HTTP 503)
#
# Configuration (environment variables):
#   On AAP, attach a credential that injects AAP_CONTROLLER_URL, AAP_ADMIN_USERNAME,
#   AAP_ADMIN_PASSWORD (same names as in the job environment).
#
#   PAH_REGISTRY       — registry hostname only, e.g. hub-aap.apps.cluster-foo.dynamic.redhatworkshops.io
#                        If unset, derived from AAP_CONTROLLER_URL (aap-aap → hub-aap).
#   PAH_NAMESPACE      — organization / namespace in Hub (default: ansible)
#   PAH_IMAGE_NAME     — image short name (default: terraform-aap-ee)
#   PAH_USERNAME       — default: AAP_ADMIN_USERNAME
#   PAH_TOKEN          — Hub/API token used as registry password (overrides PAH_PASSWORD)
#   PAH_PASSWORD       — registry password if not using PAH_TOKEN (default: AAP_ADMIN_PASSWORD)
#   PAH_TLS_VERIFY     — true or false (default: true); set false for some lab clusters
#   LOCAL_IMAGE        — local image ref (default: terraform-aap-ee:latest)
#   ENV_FILE           — optional path to a dotenv file (fallback when vars are not in the environment)
#   CONTAINER_RUNTIME  — podman or docker (default: podman if available)

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-$ROOT/.env}"
LOCAL_IMAGE="${LOCAL_IMAGE:-terraform-aap-ee:latest}"
PAH_NAMESPACE="${PAH_NAMESPACE:-ansible}"
PAH_IMAGE_NAME="${PAH_IMAGE_NAME:-terraform-aap-ee}"
PAH_TLS_VERIFY="${PAH_TLS_VERIFY:-true}"

read_env_kv() {
  local key="$1"
  local line
  [[ -n "${ENV_FILE:-}" ]] && [[ -f "${ENV_FILE}" ]] || return 1
  line=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | head -1) || true
  [[ -n "${line}" ]] || return 1
  printf '%s' "${line#*=}"
}

if [[ -z "${PAH_REGISTRY:-}" ]]; then
  url="${AAP_CONTROLLER_URL:-}"
  if [[ -z "$url" ]]; then
    url="$(read_env_kv AAP_CONTROLLER_URL)" || url=""
  fi
  if [[ -z "$url" ]]; then
    echo "Set PAH_REGISTRY or AAP_CONTROLLER_URL (e.g. from AAP credential injector) or AAP_CONTROLLER_URL in ${ENV_FILE:-a dotenv file}" >&2
    exit 1
  fi
  PAH_REGISTRY="$(printf '%s' "$url" | sed -E 's|^https?://||' | sed 's|/$||' | sed 's/aap-aap/hub-aap/')"
fi

if [[ -z "${PAH_USERNAME:-}" ]]; then
  PAH_USERNAME="${AAP_ADMIN_USERNAME:-}"
  if [[ -z "$PAH_USERNAME" ]]; then
    PAH_USERNAME="$(read_env_kv AAP_ADMIN_USERNAME)" || PAH_USERNAME=""
  fi
  if [[ -z "$PAH_USERNAME" ]]; then
    echo "Set PAH_USERNAME or AAP_ADMIN_USERNAME (e.g. from AAP credential injector) or in ${ENV_FILE:-a dotenv file}" >&2
    exit 1
  fi
fi

# Registry password: PAH_TOKEN > PAH_PASSWORD > AAP_ADMIN_PASSWORD > optional dotenv
if [[ -n "${PAH_TOKEN:-}" ]]; then
  PAH_PASSWORD="$PAH_TOKEN"
elif [[ -n "${PAH_PASSWORD:-}" ]]; then
  :
elif [[ -n "${AAP_ADMIN_PASSWORD:-}" ]]; then
  PAH_PASSWORD="$AAP_ADMIN_PASSWORD"
else
  if [[ -f "${ENV_FILE:-}" ]] && line=$(grep "^PAH_TOKEN=" "$ENV_FILE" 2>/dev/null | head -1); then
    PAH_PASSWORD="${line#PAH_TOKEN=}"
  fi
  if [[ -z "${PAH_PASSWORD:-}" ]]; then
    PAH_PASSWORD="$(read_env_kv PAH_PASSWORD)" || PAH_PASSWORD=""
  fi
  if [[ -z "${PAH_PASSWORD:-}" ]]; then
    PAH_PASSWORD="$(read_env_kv AAP_ADMIN_PASSWORD)" || PAH_PASSWORD=""
  fi
fi
if [[ -z "${PAH_PASSWORD:-}" ]]; then
  echo "Set PAH_TOKEN, PAH_PASSWORD, or AAP_ADMIN_PASSWORD (e.g. from AAP credential injector) or in ${ENV_FILE:-a dotenv file}" >&2
  exit 1
fi

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

REMOTE_IMAGE="${PAH_REGISTRY}/${PAH_NAMESPACE}/${PAH_IMAGE_NAME}:latest"

PODMAN_TLS=(--tls-verify=true)
if [[ "${PAH_TLS_VERIFY}" == "false" ]]; then
  PODMAN_TLS=(--tls-verify=false)
fi

echo "Logging in to ${PAH_REGISTRY} ..."
if [[ "$RUNTIME" == podman ]]; then
  printf '%s' "${PAH_PASSWORD}" | "$RUNTIME" login "${PODMAN_TLS[@]}" "${PAH_REGISTRY}" -u "${PAH_USERNAME}" --password-stdin
else
  printf '%s' "${PAH_PASSWORD}" | "$RUNTIME" login "${PAH_REGISTRY}" -u "${PAH_USERNAME}" --password-stdin
fi

echo "Tagging ${LOCAL_IMAGE} -> ${REMOTE_IMAGE}"
"$RUNTIME" tag "${LOCAL_IMAGE}" "${REMOTE_IMAGE}"

echo "Pushing ${REMOTE_IMAGE} ..."
if [[ "$RUNTIME" == podman ]]; then
  "$RUNTIME" push "${PODMAN_TLS[@]}" "${REMOTE_IMAGE}"
else
  "$RUNTIME" push "${REMOTE_IMAGE}"
fi

echo "Done. Use this image in Controller: ${REMOTE_IMAGE}"
