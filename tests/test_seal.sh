#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cat > "${tmp_dir}/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >> "${KUBECTL_LOG}"
printf '\n' >> "${KUBECTL_LOG}"
printf 'sealed-secrets-controller 1/1 Running\n'
EOF

cat > "${tmp_dir}/kubeseal" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >> "${KUBESEAL_LOG}"
printf '\n' >> "${KUBESEAL_LOG}"
cat > "${KUBESEAL_INPUT}"
printf 'kind: SealedSecret\nmetadata:\n  name: sanitized\n'
EOF
chmod +x "${tmp_dir}/kubectl" "${tmp_dir}/kubeseal"

export PATH="${tmp_dir}:${PATH}"
export KUBECTL_LOG="${tmp_dir}/kubectl.log"
export KUBESEAL_LOG="${tmp_dir}/kubeseal.log"
export KUBESEAL_INPUT="${tmp_dir}/secret.json"
export DATABASE_URL='postgresql://test-user:dummy-secret@test.invalid/db'

stdout="${tmp_dir}/stdout"
stderr="${tmp_dir}/stderr"
"${repo_root}/scripts/seal.sh" chat-postgres chat-api DATABASE_URL >"${stdout}" 2>"${stderr}"

grep -q 'kind: SealedSecret' "${stdout}"
if grep -R -F 'dummy-secret' "${stdout}" "${stderr}" "${KUBECTL_LOG}" "${KUBESEAL_LOG}"; then
  echo 'secret value leaked to output or command arguments' >&2
  exit 1
fi

python3 - "${KUBESEAL_INPUT}" <<'PY'
import base64
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["metadata"]["name"] == "chat-postgres"
assert payload["metadata"]["namespace"] == "chat-api"
assert base64.b64decode(payload["data"]["DATABASE_URL"]).decode() == (
    "postgresql://test-user:dummy-secret@test.invalid/db"
)
PY

(
  cd "${repo_root}"
  task seal:postgree >"${stdout}" 2>"${stderr}"
)
python3 - "${KUBESEAL_INPUT}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["metadata"]["name"] == "chat-postgree"
assert payload["metadata"]["namespace"] == "chat-api"
PY

export GITHUB_REPO_URL='https://github.com/example/repo'
export GITHUB_USERNAME='test-user'
export GITHUB_PAT='another-dummy-secret'
"${repo_root}/scripts/seal.sh" chat-github argocd --repo \
  url:GITHUB_REPO_URL username:GITHUB_USERNAME password:GITHUB_PAT \
  >"${stdout}" 2>"${stderr}"

if grep -R -F 'another-dummy-secret' "${stdout}" "${stderr}" "${KUBECTL_LOG}" "${KUBESEAL_LOG}"; then
  echo 'repository secret value leaked to output or command arguments' >&2
  exit 1
fi

python3 - "${KUBESEAL_INPUT}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["metadata"]["labels"]["argocd.argoproj.io/secret-type"] == "repository"
assert set(payload["data"]) == {"url", "username", "password"}
PY

if DATABASE_URL='' "${repo_root}/scripts/seal.sh" chat-postgres chat-api DATABASE_URL \
    >"${stdout}" 2>"${stderr}"; then
  echo 'empty environment value was accepted' >&2
  exit 1
fi
grep -q 'is unset or empty' "${stderr}"

if "${repo_root}/scripts/seal.sh" chat-postgres chat-api 'DATABASE_URL=legacy-value' \
    >"${stdout}" 2>"${stderr}"; then
  echo 'legacy KEY=value argument was accepted' >&2
  exit 1
fi
grep -q 'KEY\[:ENV_VAR\]' "${stderr}"
