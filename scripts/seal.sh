#!/usr/bin/env bash
# Render a SealedSecret without placing secret values in process arguments.
# Usage: seal.sh NAME NAMESPACE [--repo] KEY[:ENV_VAR] [...]

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/timeweb-config}"
export KUBECONFIG

controller_name="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets}"
controller_namespace="${SEALED_SECRETS_CONTROLLER_NAMESPACE:-kube-system}"

usage() {
  cat >&2 <<'EOF'
Usage: seal.sh NAME NAMESPACE [--repo] KEY[:ENV_VAR] [...]

Secret values are read from environment variables, never from arguments.
KEY reads the same-named variable; KEY:ENV_VAR maps a variable to another key.

Examples:
  seal.sh chat-openrouter chat-api OPENROUTER_API_KEY
  seal.sh chat-postgres chat-api DATABASE_URL
  seal.sh chat-github argocd --repo url:GITHUB_REPO_URL username:GITHUB_USERNAME password:GITHUB_PAT
EOF
  exit 2
}

if (($# < 3)); then
  usage
fi

secret_name="$1"
namespace="$2"
shift 2

repo_args=()
if [[ "${1:-}" == "--repo" ]]; then
  repo_args=(--repo)
  shift
fi

if (($# == 0)); then
  usage
fi

for command_name in kubectl kubeseal python3; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "required command not found: ${command_name}" >&2
    exit 2
  fi
done

echo "Checking SealedSecrets controller in ${controller_namespace}..." >&2
if ! kubectl get pods -n "${controller_namespace}" \
    -l app.kubernetes.io/name=sealed-secrets --no-headers 2>/dev/null | grep -q Running; then
  echo "SealedSecrets controller is not running in ${controller_namespace}" >&2
  exit 1
fi

echo "Rendering SealedSecret ${namespace}/${secret_name} from $# environment variable(s)..." >&2
python3 "${script_dir}/render-secret-json.py" \
  --name "${secret_name}" \
  --namespace "${namespace}" \
  "${repo_args[@]}" \
  "$@" |
  kubeseal \
    --controller-name="${controller_name}" \
    --controller-namespace="${controller_namespace}" \
    --format yaml
