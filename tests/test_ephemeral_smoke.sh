#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_dir="${repo_root}/terraform/timeweb"
workflow="${repo_root}/.github/workflows/timeweb-smoke.yaml"

bash "${repo_root}/tests/test_wait_for_kubernetes.sh"
bash "${repo_root}/tests/test_wait_for_argocd_application.sh"

grep -Eq 'source[[:space:]]*=[[:space:]]*"timeweb-cloud/timeweb-cloud"' "${tf_dir}/versions.tf"
grep -Eq 'version[[:space:]]*=[[:space:]]*"~> 1\.8"' "${tf_dir}/versions.tf"
grep -q 'ref=v0.1.0"' "${tf_dir}/main.tf"
! grep -Eq 'ref=main|ref=[0-9a-f]{40}|tf\.timeweb\.cloud/timeweb-cloud/timeweb-cloud' "${tf_dir}/main.tf" "${tf_dir}/versions.tf"

grep -q 'data "twc_k8s_preset" "master"' "${tf_dir}/main.tf"
grep -q 'data "twc_k8s_preset" "worker"' "${tf_dir}/main.tf"
grep -q 'resource "terraform_data" "cost_guard"' "${tf_dir}/main.tf"
grep -q 'max_cost_rub' "${tf_dir}/main.tf"

test -f "${workflow}"
grep -q 'TF_VAR_timeweb_token:.*secrets.TF_VAR_TIMEWEB_TOKEN' "${workflow}"
grep -q 'if:.*always()' "${workflow}"
grep -Eq 'terraform .*destroy' "${workflow}"
grep -q 'kubectl -n chat-api create job healthcheck' "${workflow}"
! grep -q 'port-forward' "${workflow}"
! grep -Eq 'ref: [0-9a-f]{40}' "${workflow}"
grep -q 'helm upgrade --install argocd' "${workflow}"
grep -q -- '--set-json.*extraObjects=\[\]' "${workflow}"
grep -q 'kubectl apply -f bootstrap/argocd/gitops-smoke-root.yaml' "${workflow}"
grep -q 'wait-for-argocd-application.sh gitops-smoke-root' "${workflow}"
grep -q 'wait-for-argocd-application.sh chat-api' "${workflow}"
grep -q 'wait-for-argocd-application.sh crewai' "${workflow}"
grep -q 'kubectl -n crewai-system create job crewai-healthcheck' "${workflow}"
grep -q 'http://crewai/health' "${workflow}"
grep -q 'http://crewai/flows' "${workflow}"
grep -q 'http://crewai/agents' "${workflow}"
grep -q 'KUBECONFIG=/tmp/auto-k8s-pilot-kubeconfig kubectl get pods' "${workflow}"
! grep -q 'helm upgrade --install chat-api' "${workflow}"
grep -q 'bash scripts/wait-for-kubernetes.sh' "${workflow}"
! grep -q 'kubectl -n app-smoke create deployment' "${workflow}"

root_app="${repo_root}/bootstrap/argocd/gitops-smoke-root.yaml"
test -f "${root_app}"
grep -q 'name: gitops-smoke-root' "${root_app}"
grep -q 'repoURL: https://github.com/justgithubaccount/app-poly-gitops-k8s.git' "${root_app}"
grep -q 'targetRevision: v1.1.0' "${root_app}"
grep -q 'path: clusters/smoke' "${root_app}"
! grep -Eq 'targetRevision: [0-9a-f]{40}' "${root_app}"

grep -q 'bash tests/test_ephemeral_smoke.sh' "${repo_root}/.github/workflows/ci.yaml"
grep -q 'github_token:.*secrets.GITHUB_TOKEN' "${repo_root}/.github/workflows/ci.yaml"

if grep -Eq 'AWS_ACCESS_KEY_ID=[A-Z0-9]{10,}|AWS_SECRET_ACCESS_KEY=[A-Za-z0-9/+]{20,}' "${repo_root}/.env.example"; then
  echo "credential-like value found in .env.example" >&2
  exit 1
fi
