#!/usr/bin/env sh
set -eu

trace_id="${1:?usage: verify-vector-trace.sh TRACE_ID SERVICE_NAME [ATTEMPTS] [DELAY_SECONDS] [RAW_TRACE_TOKEN]}"
service_name="${2:?service name is required}"
attempts="${3:-30}"
delay_seconds="${4:-2}"
raw_trace_token="${5:-}"
kubectl_bin="${KUBECTL_BIN:-kubectl}"
namespace="${VECTOR_NAMESPACE:-observability}"
deployment="${VECTOR_DEPLOYMENT:-vector-gateway}"
log_file="$(mktemp)"

cleanup() {
  rm -f "${log_file}"
}
trap cleanup EXIT

case "${trace_id}" in
  *[!0-9a-fA-F]*|'')
    echo "invalid trace ID: ${trace_id}" >&2
    exit 1
    ;;
esac
test "${#trace_id}" -eq 32

attempt=1
while test "${attempt}" -le "${attempts}"; do
  if "${kubectl_bin}" -n "${namespace}" logs "deployment/${deployment}" \
    --since=20m >"${log_file}" 2>/dev/null &&
    awk -v trace_id="${trace_id}" \
      -v service_name="${service_name}" \
      -v raw_trace_token="${raw_trace_token}" '
      BEGIN {
        trace_id = tolower(trace_id)
        service_name = tolower(service_name)
        raw_trace_token = tolower(raw_trace_token)
        found = 0
      }
      {
        line = tolower($0)
        trace_matches = index(line, trace_id) || \
          (length(raw_trace_token) && index(line, raw_trace_token))
        if (trace_matches && index(line, service_name)) {
          found = 1
        }
      }
      END { exit(found ? 0 : 1) }
    ' "${log_file}"; then
    printf '%s\n' "Vector trace verified: service=${service_name} trace_id=${trace_id}"
    exit 0
  fi

  attempt=$((attempt + 1))
  if test "${attempt}" -le "${attempts}"; then
    sleep "${delay_seconds}"
  fi
done

echo "Vector trace unavailable: service=${service_name} trace_id=${trace_id}" >&2
tail -n 200 "${log_file}" >&2 || true
exit 1
