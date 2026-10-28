# app-poly-gitops-infra

Infrastructure provisioning and ArgoCD bootstrap for GitOps platform.

## Prerequisites

- [Terraform](https://terraform.io) >= 0.13
- [Taskfile](https://taskfile.dev)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh)
- [twc CLI](https://timeweb.cloud/docs/cli) (Timeweb Cloud CLI)
- Timeweb Cloud account with API token

For the GitHub Actions smoke run, add repository secrets named
`TF_VAR_TIMEWEB_TOKEN` and `OPENAI_API_KEY`. The workflow provisions one small worker, bootstraps
Argo CD, reconciles the versioned GitOps root from `app-poly-gitops-k8s`, checks
both `chat-api` and CrewAI through Argo CD, probes CrewAI discovery endpoints
and its read-only Kubernetes access, and executes the real Kubernetes health flow.
By default it destroys the cluster in the same job. Set `keep_cluster=true` for
interactive debugging; the workflow then retains the cluster and uploads a
state/kubeconfig artifact encrypted with the `TIMEWEB_DEBUG_STATE_KEY` repository
secret for one day. Delete that cluster by running the `Timeweb cleanup` workflow
with the provisioning run ID.

To test a newer versioned GitOps release on the retained cluster, run `Timeweb
retained debug verify` with the provisioning run ID, the GitOps tag, and the
expected CrewAI image tag. This workflow reconciles and tests applications only;
it never applies or destroys Terraform infrastructure. It also verifies the exact
FastAPI and CrewAI trace IDs through Jaeger's API v3.

To promote the retained two-CPU smoke cluster to the complete application
platform, run `Timeweb retained dev deploy`. It applies the bounded worker resize
through the same Terraform state and cost guard, switches the Argo CD root to
`clusters/dev`, verifies FastAPI and CrewAI, checks traces through Vector and
Jaeger, and checks the matching FastAPI log in Loki. It never destroys the
cluster and publishes a refreshed encrypted state artifact under its own run ID;
use that new run ID for later verification or cleanup.

The smoke workflow accepts `location=ru-1` or `location=nl-1`. Use `nl-1` when
the application must call an API that does not serve requests from Russia; the
same preset lookup and cost guard are applied before Terraform creates anything.

## Quick Start

```bash
# 1. Copy .env.example to .env and fill in your credentials
cp .env.example .env
# Edit .env with your tokens

# 2. Full setup (Taskfile will automatically load .env)
task up
```

Alternative (manual export):
```bash
export TF_VAR_timeweb_token="your-timeweb-token"
export AWS_ACCESS_KEY_ID="s3-access-key"
export AWS_SECRET_ACCESS_KEY="s3-secret-key"
task up
```

## Available Tasks

| Task | Description |
|------|-------------|
| `task init` | Initialize Terraform and create k8s cluster |
| `task plan` | Show Terraform plan |
| `task kubeconfig` | Get kubeconfig from Timeweb |
| `task bootstrap` | Install ArgoCD via Helm |
| `task app-of-apps` | Deploy root Application |
| `task argocd-password` | Get ArgoCD admin password |
| `task argocd-port-forward` | Port-forward ArgoCD UI |
| `task destroy` | Destroy infrastructure |
| `task up` | Full workflow (init + bootstrap + app-of-apps) |

## Architecture

```mermaid
flowchart TB
    subgraph CLOUD["Timeweb Cloud"]
        subgraph CLUSTER["Kubernetes Cluster"]
            subgraph ARGOCD["ArgoCD"]
                root[app-of-apps]
                root --> platform
                root --> tenants
            end
            subgraph PLATFORM["Platform"]
                nginx[ingress-nginx]
                cert[cert-manager]
                dns[external-dns]
                sealed[sealed-secrets]
                longhorn[longhorn]
                cnpg[cloudnative-pg]
                loki[loki]
                grafana[grafana]
                otel[otel-collector]
            end
        end
    end

    subgraph REPOS["Git Repositories"]
        k8s[app-poly-gitops-k8s]
        helm[app-poly-gitops-helm]
        infra[app-poly-gitops-infra]
    end

    k8s --> |"GitOps sync"| ARGOCD
    helm --> |"Helm charts"| ARGOCD
    infra --> |"Bootstrap"| CLUSTER
```

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [app-poly-gitops-k8s](https://github.com/justgithubaccount/app-poly-gitops-k8s) | GitOps manifests (Kustomize + ArgoCD) |
| [app-poly-gitops-helm](https://github.com/justgithubaccount/app-poly-gitops-helm) | Helm charts |
| [app-poly-gitops-fastapi](https://github.com/justgithubaccount/app-poly-gitops-fastapi) | FastAPI application |
| [app-poly-gitops-crewai](https://github.com/justgithubaccount/app-poly-gitops-crewai) | CrewAI monitoring |

## Configuration

### Terraform Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `timeweb_token` | - | Timeweb API token (sensitive) |
| `project_id` | `null` | Optional Timeweb project ID; account default when omitted |
| `network_id` | `null` | Optional Timeweb VPC ID |
| `cluster_name` | gitops-cluster | Kubernetes cluster name |
| `location` | ru-1 | Location used for dynamic preset selection |
| `node_count` | 1 | Number of worker nodes in the disposable environment |
| `max_runtime_minutes` | 120 | Runtime used for the cost estimate |
| `max_cost_rub` | 80 | Pre-apply estimated-cost ceiling |

The default local Terraform state is intentional for the single-job disposable
run. For persistent environments, copy `terraform/timeweb/backend.s3.tf.example`
to a `.tf` file and pass the bucket/key and credentials outside Git.

### ArgoCD

ArgoCD configuration is in `bootstrap/argocd/values.yaml`. After initial bootstrap, ArgoCD becomes self-managed through the multi-source Application.

## Workflow

1. **Provision**: `task init` creates k8s cluster in Timeweb Cloud
2. **Bootstrap**: `task bootstrap` installs ArgoCD with initial values
3. **GitOps**: `task app-of-apps` deploys root Application from app-poly-gitops-k8s
4. **Self-managed**: ArgoCD now manages itself and all applications

## Golden Install Notes

При чистой установке с нуля:

1. **ArgoCD Ingress** управляется через GitOps в `app-poly-gitops-k8s`, не через Helm chart
2. **ArgoCD insecure mode** — сервер работает в HTTP режиме, ingress без `backend-protocol: HTTPS`
3. **Cloudflare token** — ключ в секрете: `CF_API_TOKEN`
4. **Sync Waves** — операторы (wave: 1) деплоятся раньше их CR (wave: 3+)

## Access

- **ArgoCD UI**: https://argo.syncjob.ru
- **Admin password**: `task argocd-password`

## Cleanup

```bash
task destroy
```

This will destroy the Kubernetes cluster and all resources.
