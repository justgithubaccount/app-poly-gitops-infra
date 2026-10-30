#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cp "${repo_root}/scripts/argocd-sync-check.sh" "${tmp_dir}/argocd-sync-check.sh"
cat > "${tmp_dir}/wait-for-argocd-application.sh" <<'EOF'
#!/usr/bin/env bash
printf 'KUBECONFIG=%s\n' "${KUBECONFIG-}"
printf '%s\n' "$@"
EOF
chmod +x "${tmp_dir}/argocd-sync-check.sh" "${tmp_dir}/wait-for-argocd-application.sh"

test_home="${tmp_dir}/home"
mapfile -t defaults < <(env -u KUBECONFIG HOME="${test_home}" "${tmp_dir}/argocd-sync-check.sh")
[[ "${defaults[*]}" == "KUBECONFIG=${test_home}/.kube/timeweb-config dev-cluster 120" ]]

mapfile -t explicit < <(KUBECONFIG=/tmp/explicit-kubeconfig "${tmp_dir}/argocd-sync-check.sh" crewai 300)
[[ "${explicit[*]}" == "KUBECONFIG=/tmp/explicit-kubeconfig crewai 300" ]]
