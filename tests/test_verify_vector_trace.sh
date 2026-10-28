#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="${repo_root}/scripts/verify-vector-trace.sh"
fake_kubectl="$(mktemp)"
trace_id="00000000000000000000000000000001"
trap 'rm -f "${fake_kubectl}"' EXIT

cat >"${fake_kubectl}" <<'SCRIPT'
#!/usr/bin/env sh
set -eu
printf '%s\n' '{"trace_id":"00000000000000000000000000000001","resource":{"service.name":"chat-api"}}'
SCRIPT
chmod +x "${fake_kubectl}"

KUBECTL_BIN="${fake_kubectl}" bash "${verifier}" "${trace_id}" chat-api 1 0

if KUBECTL_BIN="${fake_kubectl}" bash "${verifier}" \
  "${trace_id}" wrong-service 1 0; then
  echo 'Vector verifier accepted the wrong service' >&2
  exit 1
fi
