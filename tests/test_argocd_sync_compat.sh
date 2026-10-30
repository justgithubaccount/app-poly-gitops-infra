#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cp "${repo_root}/scripts/argocd-sync-check.sh" "${tmp_dir}/argocd-sync-check.sh"
cat > "${tmp_dir}/wait-for-argocd-application.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
chmod +x "${tmp_dir}/argocd-sync-check.sh" "${tmp_dir}/wait-for-argocd-application.sh"

mapfile -t defaults < <("${tmp_dir}/argocd-sync-check.sh")
[[ "${defaults[*]}" == "dev-cluster 120" ]]

mapfile -t explicit < <("${tmp_dir}/argocd-sync-check.sh" crewai 300)
[[ "${explicit[*]}" == "crewai 300" ]]
