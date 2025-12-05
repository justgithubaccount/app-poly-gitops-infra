# Architecture Overview

## Repository Ecosystem

```mermaid
flowchart TB
    subgraph INFRA["🏗️ INFRASTRUCTURE"]
        infra[app-poly-gitops-infra]
        infra --> |"Terraform"| cluster[K8s Cluster]
        infra --> |"Taskfile"| argocd_install[ArgoCD Install]
    end

    subgraph GITOPS["📦 GITOPS"]
        k8s[app-poly-gitops-k8s]
        helm[app-poly-gitops-helm]
        k8s --> |"references"| helm
    end

    subgraph APP["🚀 APPLICATION"]
        fastapi[app-poly-gitops-fastapi]
        fastapi --> |"builds"| ghcr[ghcr.io/image]
    end

    subgraph OBS["👁️ OBSERVABILITY"]
        crewai[app-poly-gitops-crewai]
    end

    cluster --> argocd[ArgoCD]
    argocd --> |"syncs"| k8s
    argocd --> |"deploys"| helm
    ghcr --> |"Image Updater"| k8s
    crewai --> |"monitors"| cluster
```

## Data Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant FastAPI as app-poly-gitops-fastapi
    participant GHCR as ghcr.io
    participant K8s as app-poly-gitops-k8s
    participant ArgoCD as ArgoCD
    participant Helm as app-poly-gitops-helm
    participant Cluster as K8s Cluster

    Dev->>FastAPI: git push (code)
    FastAPI->>GHCR: CI builds image
    GHCR->>K8s: Image Updater updates tag
    K8s->>ArgoCD: webhook/poll
    ArgoCD->>Helm: fetch chart
    ArgoCD->>Cluster: deploy
```

## Repository Responsibilities

```mermaid
pie showData
    title "Repository Ownership"
    "infra (DevOps)" : 1
    "k8s (DevOps)" : 1
    "helm (Dev+DevOps)" : 1
    "fastapi (Dev)" : 1
    "crewai (SRE)" : 1
```

## Repository Matrix

| Repository | Layer | Owner | Changes When |
|------------|-------|-------|--------------|
| **app-poly-gitops-infra** | Infrastructure | DevOps | New cluster, infra changes |
| **app-poly-gitops-k8s** | GitOps | DevOps | New apps, environments, policies |
| **app-poly-gitops-helm** | Deployment | Dev + DevOps | App deployment structure |
| **app-poly-gitops-fastapi** | Application | Dev | Application code |
| **app-poly-gitops-crewai** | Observability | SRE | Monitoring rules |

## Environments Flow

```mermaid
gitGraph
    commit id: "feature"
    branch dev
    commit id: "deploy to dev"
    branch tst
    commit id: "deploy to tst"
    branch stg
    commit id: "deploy to stg"
    branch prd
    commit id: "deploy to prd"
```

## Bootstrap Sequence

```mermaid
flowchart LR
    A[task init] --> B[Terraform apply]
    B --> C[K8s cluster created]
    C --> D[task bootstrap]
    D --> E[ArgoCD installed]
    E --> F[task app-of-apps]
    F --> G[Root Application deployed]
    G --> H[ArgoCD syncs all apps]
```

## Deployment Chain

The complete dependency chain showing how repositories connect:

```mermaid
flowchart LR
    A[app-poly-gitops-infra] --> B[app-poly-gitops-k8s]
    B --> C[app-poly-gitops-helm]
    C --> D[Docker image]
    D --> E[app-poly-gitops-fastapi]

    F[app-poly-gitops-crewai] -.->|monitors| B
    F -.->|monitors| C
    F -.->|monitors| D
```

## Startup Sequence

| Step | Repository | Action |
|------|------------|--------|
| 1 | **infra** | `task up` → Terraform creates k8s → installs ArgoCD |
| 2 | **k8s** | ArgoCD syncs manifests → creates Applications |
| 3 | **helm** | ArgoCD renders Helm chart with values from k8s |
| 4 | **fastapi** | CI builds Docker → pushes to ghcr.io |
| 5 | **k8s** | Image Updater detects new tag → commits to k8s |
| 6 | **crewai** | Monitors that everything works |

## Dependency Tree

```
infra
└── creates cluster + ArgoCD
    └── k8s (ArgoCD Applications)
        └── helm (Helm charts)
            └── Docker image
                └── fastapi (code)

crewai → observes all of the above
```

## Related Links

- [app-poly-gitops-infra](https://github.com/justgithubaccount/app-poly-gitops-infra) - This repository
- [app-poly-gitops-k8s](https://github.com/justgithubaccount/app-poly-gitops-k8s) - GitOps manifests
- [app-poly-gitops-helm](https://github.com/justgithubaccount/app-poly-gitops-helm) - Helm charts
- [app-poly-gitops-fastapi](https://github.com/justgithubaccount/app-poly-gitops-fastapi) - FastAPI application
- [app-poly-gitops-crewai](https://github.com/justgithubaccount/app-poly-gitops-crewai) - CrewAI monitoring
