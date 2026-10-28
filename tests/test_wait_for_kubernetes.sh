#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wait_script="${repo_root}/scripts/wait-for-kubernetes.sh"

if [[ ! -x "${wait_script}" ]]; then
  echo "missing executable Kubernetes readiness script: ${wait_script}" >&2
  exit 1
fi

kubectl() {
  printf 'kubectl'
  printf ' %s' "$@"
  printf '\n'
}
export -f kubectl

actual="$(bash "${wait_script}")"
expected=$'kubectl wait --for=condition=Ready nodes --all --timeout=10m\nkubectl -n kube-system wait --for=condition=Ready pods --all --timeout=15m'

if [[ "${actual}" != "${expected}" ]]; then
  printf 'unexpected readiness sequence:\n%s\n' "${actual}" >&2
  exit 1
fi
