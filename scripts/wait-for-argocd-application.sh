#!/usr/bin/env bash
set -euo pipefail

app_name="${1:?usage: wait-for-argocd-application.sh APP_NAME [TIMEOUT_SECONDS] [healthy|sync-only]}"
timeout_seconds="${2:-900}"
wait_mode="${3:-healthy}"
poll_seconds="${POLL_SECONDS:-5}"
kubectl_bin="${KUBECTL_BIN:-kubectl}"

if [[ "${wait_mode}" != "healthy" && "${wait_mode}" != "sync-only" ]]; then
  echo "unsupported wait mode: ${wait_mode}" >&2
  exit 2
fi

deadline=$((SECONDS + timeout_seconds))

while ((SECONDS < deadline)); do
  if status="$("${kubectl_bin}" -n argocd get application "${app_name}" \
    -o jsonpath='{.status.sync.status} {.status.health.status} {.status.operationState.phase}' 2>/dev/null)"; then
    read -r sync_status health_status operation_phase <<< "${status}"

    if [[ "${health_status}" == "Degraded" ]]; then
      echo "${app_name} is Degraded" >&2
      exit 1
    fi

    if [[ "${operation_phase}" == "Failed" || "${operation_phase}" == "Error" ]]; then
      echo "${app_name} operation ${operation_phase}" >&2
      exit 1
    fi

    if [[ "${sync_status}" == "Synced" && "${wait_mode}" == "sync-only" ]]; then
      echo "${app_name} is Synced"
      exit 0
    fi

    if [[ "${sync_status}" == "Synced" && "${health_status}" == "Healthy" ]]; then
      echo "${app_name} is Synced and Healthy"
      exit 0
    fi
  fi

  sleep "${poll_seconds}"
done

echo "timed out waiting for ${app_name} (${wait_mode})" >&2
exit 1
