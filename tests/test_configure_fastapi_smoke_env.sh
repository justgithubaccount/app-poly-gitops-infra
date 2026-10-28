#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/scripts/configure-fastapi-smoke-env.sh"
tmp_dir="$(mktemp -d)"
trap 'find "${tmp_dir}" -depth -delete' EXIT

cat > "${tmp_dir}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_KUBECTL_LOG}"
EOF
chmod +x "${tmp_dir}/kubectl"

FAKE_KUBECTL_LOG="${tmp_dir}/calls" \
KUBECTL_BIN="${tmp_dir}/kubectl" \
  bash "${script}" chat-api chat-api fastapi-runtime-smoke-llm

test "$(wc -l < "${tmp_dir}/calls")" -eq 1
grep -q -- '-n chat-api patch deployment chat-api --type strategic --patch' "${tmp_dir}/calls"
grep -q 'OPENROUTER_API_KEY' "${tmp_dir}/calls"
grep -q 'fastapi-runtime-smoke-llm' "${tmp_dir}/calls"
grep -q 'OPENROUTER_API_URL' "${tmp_dir}/calls"
grep -q 'https://api.openai.com/v1/chat/completions' "${tmp_dir}/calls"
grep -q 'OPENROUTER_MODEL' "${tmp_dir}/calls"
grep -q 'gpt-4o-mini' "${tmp_dir}/calls"
