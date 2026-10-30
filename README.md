# GitOps Infrastructure

Terraform provisioning, Argo CD bootstrap, and bounded acceptance workflows for
the `app-poly-gitops` engineering lab. The repository targets Timeweb Cloud and
does not imply that a cluster is currently running.

## Overview

Terraform selects current Timeweb Kubernetes presets, estimates the requested run
cost, and calls the versioned
[`infra-cluster`](https://github.com/justgithubaccount/infra-cluster) managed
Kubernetes module. The Taskfile can then install Argo CD and apply the GitOps
root from
[`app-poly-gitops-k8s`](https://github.com/justgithubaccount/app-poly-gitops-k8s).

The default configuration is intentionally small: one worker, a 120-minute cost
estimate, and an 80 RUB pre-apply ceiling. The guard is an estimate based on
provider preset prices, not a billing guarantee.

## GitHub Actions workflows

| Workflow | Purpose | Infrastructure lifecycle |
| --- | --- | --- |
| **CI** | Terraform, Taskfile, YAML, shell, workflow-contract, and secret checks | No cloud changes |
| **Application live OpenAI smoke (no cloud)** | Pinned FastAPI, CrewAI, UI, browser, provider, and OTLP check | Runner-local only |
| **Timeweb smoke and debug** | Provision smoke cluster, reconcile apps, run FastAPI/CrewAI checks | Destroys by default |
| **Timeweb retained debug verify** | Reconcile and re-test a retained cluster | No Terraform apply/destroy |
| **Timeweb retained dev deploy** | Resize retained worker and switch to `clusters/dev` | Applies changes; keeps cluster |
| **Timeweb cleanup** | Destroy a retained cluster from its encrypted state artifact | Destroys exact retained run |
| **Timeweb floating IP cleanup** | Audit or delete exact floating-IP matches | Optional explicit deletion |

The no-cloud application smoke is dispatched from the default branch with
`confirm_live=true`. It uses the repository `OPENAI_API_KEY` through a
runner-local budget guard and uploads only a sanitized summary.

The Timeweb smoke workflow requires `TF_VAR_TIMEWEB_TOKEN` and
`OPENAI_API_KEY`. Select `keep_cluster=true` only for an interactive debug
session; it also requires `TIMEWEB_DEBUG_STATE_KEY` and uploads encrypted state
for one day. Always run **Timeweb cleanup** with the retained provisioning run ID
when debugging is complete.

## Local provisioning

Requirements: Terraform 1.6+, Task, kubectl, Helm 3, and a Timeweb API token.

~~~bash
cp .env.example .env
task plan
task up
~~~

`task up` is a mutating operation: it applies Terraform, writes kubeconfig to
`~/.kube/timeweb-config`, installs Argo CD, and applies the root application.
Review the plan, selected presets, and cost estimate first.

Useful read and cleanup commands:

~~~bash
task status
task argocd-password
task argocd-port-forward
task destroy
~~~

The local Terraform state is suitable for one disposable workflow. For a
persistent environment, copy `terraform/timeweb/backend.s3.tf.example` to a
`.tf` file and supply backend configuration outside Git.

## Configuration

| Terraform variable | Default | Purpose |
| --- | --- | --- |
| `timeweb_token` | required | Timeweb API token |
| `project_id` | `null` | Optional project override |
| `network_id` | `null` | Optional VPC override |
| `cluster_name` | `gitops-cluster` | Cluster name |
| `location` | `ru-1` | Preset location |
| `node_count` | `1` | Disposable worker count; validated as one |
| `max_runtime_minutes` | `120` | Cost-estimate duration |
| `max_cost_rub` | `80` | Estimated-cost ceiling |

Argo CD chart values are in `bootstrap/argocd/values.yaml`. The smoke root is
`bootstrap/argocd/gitops-smoke-root.yaml`.

## Repository structure

- `terraform/timeweb/` — Timeweb provider, preset selection, cost guard, and module call
- `bootstrap/argocd/` — bootstrap values and smoke root
- `.github/workflows/` — offline, application, and cloud lifecycle workflows
- `scripts/` — wait, smoke, telemetry, and cleanup helpers
- `tests/` — offline workflow and script contracts
- `Taskfile.yaml` — local provisioning and diagnostics

## Validation

Offline repository checks:

~~~bash
task --list
terraform fmt -check -recursive terraform
terraform -chdir=terraform/timeweb init -backend=false
terraform -chdir=terraform/timeweb validate
bash tests/test_ephemeral_smoke.sh
bash tests/test_timeweb_floating_ip_cleanup.sh
python3 -m unittest discover -s tests -p test_application_live_smoke.py -v
~~~

Do not run `task up`, Terraform apply/destroy, or the Timeweb workflows as a
documentation check.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Tenant applications](docs/TENANT-APPS.md)

## Related repositories

- [app-poly-gitops-k8s](https://github.com/justgithubaccount/app-poly-gitops-k8s) — desired state
- [app-poly-gitops-helm](https://github.com/justgithubaccount/app-poly-gitops-helm) — FastAPI chart
- [app-poly-gitops-fastapi](https://github.com/justgithubaccount/app-poly-gitops-fastapi) — chat backend
- [app-poly-gitops-crewai](https://github.com/justgithubaccount/app-poly-gitops-crewai) — Kubernetes automation
- [app-poly-gitops-ui](https://github.com/justgithubaccount/app-poly-gitops-ui) — standalone frontend
- [infra-cluster](https://github.com/justgithubaccount/infra-cluster) — reusable Terraform modules
- [app-mono-gitops](https://github.com/justgithubaccount/app-mono-gitops) — archived predecessor

## License

MIT
