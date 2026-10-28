#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="${repo_root}/tests/fixtures/fake_loki_server.py"
verifier="${repo_root}/scripts/verify-loki-log.sh"
trace_id="00000000000000000000000000000001"
port_file="$(mktemp)"
server_pid=""

cleanup() {
  if test -n "${server_pid}"; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  rm -f "${port_file}"
}
trap cleanup EXIT

rm -f "${port_file}"
python3 "${fixture}" \
  --port-file "${port_file}" \
  --trace-id "${trace_id}" \
  --service-name chat-api &
server_pid=$!
for _ in $(seq 1 50); do
  test -s "${port_file}" && break
  sleep 0.1
done
test -s "${port_file}"

bash "${verifier}" \
  "http://127.0.0.1:$(cat "${port_file}")" \
  "${trace_id}" chat-api 1 0

if bash "${verifier}" \
  "http://127.0.0.1:$(cat "${port_file}")" \
  "${trace_id}" wrong-service 1 0; then
  echo "Loki verifier accepted the wrong service" >&2
  exit 1
fi
