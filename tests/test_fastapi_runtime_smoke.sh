#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smoke_script="${repo_root}/scripts/fastapi-runtime-smoke.sh"
fixture="${repo_root}/tests/fixtures/fake_fastapi_server.py"
server_pid=""
port_file=""

cleanup() {
  if test -n "${server_pid}"; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  if test -n "${port_file}"; then
    rm -f "${port_file}"
  fi
}
trap cleanup EXIT

start_server() {
  cleanup
  server_pid=""
  port_file="$(mktemp)"
  rm -f "${port_file}"
  python3 "${fixture}" --port-file "${port_file}" "$@" &
  server_pid=$!
  for _ in $(seq 1 50); do
    test -s "${port_file}" && return
    sleep 0.1
  done
  echo "fake FastAPI server did not start" >&2
  exit 1
}

# A valid FastAPI implementation must pass the complete user-visible flow.
start_server
bash "${smoke_script}" "http://127.0.0.1:$(cat "${port_file}")"

# A 200 response containing the application's wrapped LLM error must fail smoke.
start_server --chat-error
error_output="$(mktemp)"
if bash "${smoke_script}" "http://127.0.0.1:$(cat "${port_file}")" \
  > "${error_output}" 2>&1; then
  echo "runtime smoke accepted an LLM error as success" >&2
  exit 1
fi
grep -q 'Ошибка API: invalid key' "${error_output}"
rm -f "${error_output}"
