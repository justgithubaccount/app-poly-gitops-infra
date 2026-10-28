#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/timeweb-dev-deploy.yaml"

test -f "${workflow}"
grep -q 'provision_run_id:' "${workflow}"
grep -q 'gitops_revision:' "${workflow}"
grep -q 'worker_cpu:' "${workflow}"
grep -q 'TF_VAR_worker_cpu:.*inputs.worker_cpu' "${workflow}"
grep -q 'TF_VAR_max_cost_rub:.*inputs.max_cost_rub' "${workflow}"
grep -q 'Preserve retained Kubernetes version' "${workflow}"
grep -q 'TF_VAR_k8s_version=' "${workflow}"
grep -q 'module.k8s.twc_k8s_cluster.main' "${workflow}"
grep -Eq 'terraform .*plan' "${workflow}"
grep -Eq 'terraform .*apply' "${workflow}"
! grep -Eq 'terraform .*destroy' "${workflow}"

grep -q 'path: clusters/dev' "${workflow}"
grep -q 'kubectl -n argocd patch application gitops-smoke-root' "${workflow}"
grep -q "operation:{sync:" "${workflow}"
grep -q 'prune:true' "${workflow}"
grep -q 'wait-for-argocd-application.sh vector-gateway' "${workflow}"
grep -q 'wait-for-argocd-application.sh loki' "${workflow}"
grep -q 'wait-for-argocd-application.sh grafana' "${workflow}"
grep -q 'wait-for-argocd-application.sh chat-api' "${workflow}"
grep -q 'wait-for-argocd-application.sh crewai' "${workflow}"

grep -q 'chat-openrouter' "${workflow}"
grep -q 'crewai-llm' "${workflow}"
grep -q 'scripts/fastapi-runtime-smoke.sh' "${workflow}"
grep -q 'http://crewai/run/k8s-healthcheck' "${workflow}"
grep -q 'scripts/verify-vector-trace.sh' "${workflow}"
if grep -q 'service/jaeger' "${workflow}"; then
  echo 'dev workflow still depends on Jaeger' >&2
  exit 1
fi
grep -q 'scripts/verify-loki-log.sh' "${workflow}"

grep -q 'actions/upload-artifact@v4' "${workflow}"
grep -q 'timeweb-debug-state-${{ github.run_id }}' "${workflow}"
