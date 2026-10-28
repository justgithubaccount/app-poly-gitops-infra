#!/usr/bin/env sh
set -eu

base_url="${1:?usage: verify-loki-log.sh BASE_URL TRACE_ID SERVICE_NAME [ATTEMPTS] [DELAY_SECONDS]}"
trace_id="${2:?trace ID is required}"
service_name="${3:?service name is required}"
attempts="${4:-30}"
delay_seconds="${5:-2}"
response_file="$(mktemp)"

cleanup() {
  rm -f "${response_file}"
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
  if curl --silent --show-error --fail \
    --get \
    --data-urlencode "query={stream=\"otel\"} |= \"${trace_id}\"" \
    --output "${response_file}" \
    "${base_url%/}/loki/api/v1/query_range" && \
    grep -Fq "${trace_id}" "${response_file}" && \
    grep -Fq "${service_name}" "${response_file}"; then
    printf '%s\n' "Loki log verified: service=${service_name} trace_id=${trace_id}"
    exit 0
  fi
  attempt=$((attempt + 1))
  if test "${attempt}" -le "${attempts}"; then
    sleep "${delay_seconds}"
  fi
done

echo "Loki log unavailable: service=${service_name} trace_id=${trace_id}" >&2
cat "${response_file}" >&2 || true
exit 1
