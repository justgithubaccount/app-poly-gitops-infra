#!/usr/bin/env bash
# Compatibility entrypoint; use wait-for-argocd-application.sh for new callers.

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/timeweb-config}"
export KUBECONFIG

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${script_dir}/wait-for-argocd-application.sh" "${1:-dev-cluster}" "${2:-120}"
