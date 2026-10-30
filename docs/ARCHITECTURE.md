# Architecture

`app-poly-gitops-infra` owns the infrastructure lifecycle boundary: Timeweb
Cloud provisioning, kubeconfig output, initial Argo CD installation, and
acceptance workflows. Application desired state remains in separate repositories.

## Repository relationships

~~~mermaid
flowchart LR
    Infra[app-poly-gitops-infra] -->|Terraform module| Modules[infra-cluster]
    Infra -->|bootstrap| Argo[Argo CD]
    Desired[app-poly-gitops-k8s] -->|reconciled by| Argo
    Chart[app-poly-gitops-helm] -->|FastAPI package| Argo
    Images[FastAPI and CrewAI images] -->|pulled by| Cluster[Kubernetes]
    Argo --> Cluster
    UI[app-poly-gitops-ui] -. standalone frontend .-> Images
~~~

| Repository | Responsibility |
| --- | --- |
| `app-poly-gitops-infra` | Provision, bootstrap, verify, and clean up |
| `infra-cluster` | Reusable Timeweb Terraform modules |
| `app-poly-gitops-k8s` | Argo CD desired state and environment composition |
| `app-poly-gitops-helm` | FastAPI Kubernetes package |
| `app-poly-gitops-fastapi` | Chat API and persistence |
| `app-poly-gitops-crewai` | Kubernetes automation API |
| `app-poly-gitops-ui` | Standalone browser frontend |

## Provisioning

`terraform/timeweb`:

1. configures the official Timeweb provider;
2. selects master and worker presets by CPU count, location, and type;
3. estimates the bounded run cost and rejects values above `max_cost_rub`;
4. calls `infra-cluster//modules/timeweb-k8s?ref=v0.1.0`;
5. exposes IDs, selected presets, estimated cost, and sensitive kubeconfig.

Project and network IDs are optional. The disposable configuration restricts
`node_count` to one. The default state is local because the primary workflow
creates and destroys infrastructure in one job. A documented S3 backend example
is available for persistent use.

## Bootstrap

The Taskfile and cloud workflow install Argo CD chart `9.1.6` with server
Ingress disabled and `server.insecure=true`. The public Ingress, if enabled by
the dev profile, belongs to the GitOps repository.

Local bootstrap renders the chart once, applies that immutable temporary
render, and retries the same file once on a transient apply failure. The
self-managed Argo CD values source intentionally remains on `main` until a
release newer than `v0.1.0` contains an immutable self-reference. Pinning the
Application to `v0.1.0` is unsafe because that tag's own values file points back
to `main`, allowing the Application to reconcile its source revision away from
the requested pin. This exception applies only to Argo CD self-management. The
local GitOps root defaults to `app-poly-gitops-k8s@v1.5.1`, and the Taskfile
rejects branch names; an operator can override it only with a semantic release
tag or full commit SHA.

After bootstrap, one root application selects the environment path:

- `clusters/smoke` for disposable acceptance;
- `clusters/dev` for the expanded development profile.

Argo CD then reconciles child applications. Bootstrap success alone does not
prove that every child is healthy.

## Lifecycle paths

### Disposable smoke

The **Timeweb smoke and debug** workflow plans and applies the cost-guarded
cluster, installs Argo CD, and reconciles `clusters/smoke` from the released
`app-poly-gitops-k8s@v1.5.1` root. It executes a real FastAPI project/chat flow,
the deterministic CrewAI Kubernetes health flow, and verifies both trace IDs in
the smoke Jaeger backend. It destroys the cluster by default. Cleanup runs in
the same job even after an application check fails.

The older `v1.2.0` smoke pin was an intentional historical acceptance point but
no longer matched the current Jaeger and application contract. The workflow is
now advanced only to an existing reviewed GitOps release, never to `main`.

### Retained debugging

`keep_cluster=true` encrypts Terraform state and kubeconfig with
`TIMEWEB_DEBUG_STATE_KEY` and stores the artifact for one day. Subsequent
verification restores only the kubeconfig; dev promotion restores state and
performs a bounded resize. The retained workflows accept only semantic GitOps
release tags and semantic application image tags before reading state or
performing cloud work.

**Timeweb cleanup** restores the exact state and runs Terraform destroy. When
automatic destroy or empty-state verification fails, both the disposable and
cleanup workflows upload a new one-day encrypted recovery artifact and report
its run ID. A successful default destroy uploads no state.

### Runner-local application smoke

**Application live OpenAI smoke (no cloud)** starts pinned commit revisions on an
Actions runner. A local transport holds the provider key and enforces request,
model, input, output-token, and retry bounds. This validates application wiring
but not Kubernetes, Argo CD, DNS, or cluster telemetry.

## Runtime data and credentials

Credentials are supplied as local environment variables, GitHub Actions secrets,
or Kubernetes Secrets. They are not committed. Cloud workflows stream LLM keys
to `kubectl` through standard input instead of placing values in process
arguments. Retained Terraform state and kubeconfig are encrypted before artifact
upload and expire after one day.

The cloud workflow creates short-lived application Secrets needed by smoke
checks. Public dev networking also requires the separately documented Cloudflare,
Grafana, and basic-auth Secrets in
[`app-poly-gitops-k8s/docs/DEV-WEBS.md`](https://github.com/justgithubaccount/app-poly-gitops-k8s/blob/main/docs/DEV-WEBS.md).

## Evidence boundaries

- Terraform validate proves configuration consistency, not provider availability.
- Kustomize/Helm rendering proves desired-state assembly, not reconciliation.
- An Argo CD `Synced/Healthy` state does not prove a paid LLM request succeeded.
- The runner-local live smoke does not prove a Kubernetes deployment.
- Retained state is operational recovery material, not a durable environment
  registry.

No current cluster or endpoint status is recorded in this document.
