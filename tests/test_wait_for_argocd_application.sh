#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/scripts/wait-for-argocd-application.sh"
tmp_dir="$(mktemp -d)"
trap 'find "${tmp_dir}" -depth -delete' EXIT

test -x "${script}"

cat > "${tmp_dir}/kubectl-success" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

counter_file="${FAKE_KUBECTL_COUNTER}"
count=0
if [[ -f "${counter_file}" ]]; then
  count="$(cat "${counter_file}")"
fi
count=$((count + 1))
printf '%s\n' "${count}" > "${counter_file}"

case "${count}" in
  1)
    exit 1
    ;;
  2)
    printf '%s\n' 'OutOfSync Progressing Running'
    ;;
  *)
    printf '%s\n' 'Synced Healthy Succeeded'
    ;;
esac
EOF
chmod +x "${tmp_dir}/kubectl-success"

success_output="$({
  FAKE_KUBECTL_COUNTER="${tmp_dir}/success-count" \
  KUBECTL_BIN="${tmp_dir}/kubectl-success" \
  POLL_SECONDS=0 \
    "${script}" chat-api 10
} 2>&1)"

grep -q 'chat-api is Synced and Healthy' <<< "${success_output}"

cat > "${tmp_dir}/kubectl-degraded" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'Synced Degraded Failed'
EOF
chmod +x "${tmp_dir}/kubectl-degraded"

if KUBECTL_BIN="${tmp_dir}/kubectl-degraded" POLL_SECONDS=0 \
  "${script}" chat-api 10 > "${tmp_dir}/degraded-output" 2>&1; then
  echo 'degraded Argo CD application was accepted' >&2
  exit 1
fi

grep -q 'chat-api is Degraded' "${tmp_dir}/degraded-output"
