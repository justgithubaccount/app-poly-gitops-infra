#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_dir="${repo_root}/terraform/timeweb"
workflow="${repo_root}/.github/workflows/timeweb-smoke.yaml"

grep -Eq 'source[[:space:]]*=[[:space:]]*"timeweb-cloud/timeweb-cloud"' "${tf_dir}/versions.tf"
grep -Eq 'version[[:space:]]*=[[:space:]]*"~> 1\.8"' "${tf_dir}/versions.tf"
grep -Eq 'ref=[0-9a-f]{40}"' "${tf_dir}/main.tf"
! grep -Eq 'ref=main|tf\.timeweb\.cloud/timeweb-cloud/timeweb-cloud' "${tf_dir}/main.tf" "${tf_dir}/versions.tf"

grep -q 'data "twc_k8s_preset" "master"' "${tf_dir}/main.tf"
grep -q 'data "twc_k8s_preset" "worker"' "${tf_dir}/main.tf"
grep -q 'resource "terraform_data" "cost_guard"' "${tf_dir}/main.tf"
grep -q 'max_cost_rub' "${tf_dir}/main.tf"

test -f "${workflow}"
grep -q 'TF_VAR_timeweb_token:.*secrets.TF_VAR_TIMEWEB_TOKEN' "${workflow}"
grep -q 'if:.*always()' "${workflow}"
grep -Eq 'terraform .*destroy' "${workflow}"
grep -q 'kubectl -n app-smoke create job healthcheck' "${workflow}"
! grep -q 'port-forward' "${workflow}"
grep -q 'repository: justgithubaccount/app-poly-gitops-helm' "${workflow}"
grep -Eq 'ref: [0-9a-f]{40}' "${workflow}"
grep -q 'helm upgrade --install chat-api' "${workflow}"
! grep -q 'kubectl -n app-smoke create deployment' "${workflow}"

if grep -Eq 'AWS_ACCESS_KEY_ID=[A-Z0-9]{10,}|AWS_SECRET_ACCESS_KEY=[A-Za-z0-9/+]{20,}' "${repo_root}/.env.example"; then
  echo "credential-like value found in .env.example" >&2
  exit 1
fi
