# Tenant Applications (CNCF/OpenGitOps)

## Overview

This document describes the multi-environment deployment pattern for tenant applications following CNCF GitOps principles.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Git Repository                        │
│                    (Single Source of Truth)                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  tenants/product-team/apps/chat/                            │
│  ├── base/                      # Template (DRY)            │
│  │   ├── application.yaml       # Base ArgoCD Application   │
│  │   └── kustomization.yaml                                 │
│  │                                                          │
│  └── overlays/                  # Env-specific              │
│      ├── dev/   (secrets + patches)                         │
│      ├── tst/   (secrets + patches)                         │
│      ├── stg/   (secrets + patches)                         │
│      └── prd/   (secrets + patches)                         │
│                                                              │
│  clusters/                      # Cluster entry points       │
│  ├── dev/kustomization.yaml  → overlays/dev                 │
│  ├── tst/kustomization.yaml  → overlays/tst                 │
│  ├── stg/kustomization.yaml  → overlays/stg                 │
│  └── prd/kustomization.yaml  → overlays/prd                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         ArgoCD                               │
│                                                              │
│  dev-cluster App ──► clusters/dev/ ──► chat-api App         │
│  tst-cluster App ──► clusters/tst/ ──► chat-api App         │
│  stg-cluster App ──► clusters/stg/ ──► chat-api App         │
│  prd-cluster App ──► clusters/prd/ ──► chat-api App         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## CNCF GitOps Principles

| Principle | Implementation |
|-----------|----------------|
| **Declarative** | All config in YAML manifests |
| **Versioned** | Git as single source of truth |
| **Pulled automatically** | ArgoCD pulls from Git |
| **Continuously reconciled** | selfHeal + prune enabled |

## Directory Structure

### Base Template

`tenants/product-team/apps/chat/base/application.yaml`:
- Contains the ArgoCD Application template
- Image Updater annotations for automatic updates
- Reference to Helm chart repository
- Automated sync policy

### Environment Overlays

Each overlay in `overlays/{env}/` contains:
- **kustomization.yaml** - References base + patches
- **secrets** - SealedSecrets for env-specific credentials
- **patches** - JSON patches for Application customization

## Environment Configuration

| Env | Replicas | CPU Limit | Memory | Host |
|-----|----------|-----------|--------|------|
| dev | 2 | 1000m | 1Gi | chat-dev.syncjob.ru |
| tst | 1 | 500m | 512Mi | chat-tst.syncjob.ru |
| stg | 2 | 1000m | 1Gi | chat-stg.syncjob.ru |
| prd | 3 | 2000m | 2Gi | chat.syncjob.ru |

## Adding a New Application

1. **Create base template**:
   ```bash
   mkdir -p tenants/product-team/apps/new-app/base
   # Create application.yaml and kustomization.yaml
   ```

2. **Create overlays for each environment**:
   ```bash
   for env in dev tst stg prd; do
     mkdir -p tenants/product-team/apps/new-app/overlays/$env
     # Create kustomization.yaml with patches
   done
   ```

3. **Reference from cluster**:
   ```yaml
   # clusters/dev/kustomization.yaml
   resources:
     - ../../tenants/product-team/apps/new-app/overlays/dev
   ```

## Kustomize Patches Example

```yaml
patches:
  - target:
      kind: Application
      name: chat-api
    patch: |
      - op: add
        path: /metadata/labels/env
        value: dev
      - op: add
        path: /spec/source/helm/values
        value: |
          replicaCount: 2
          ingress:
            host: chat-dev.syncjob.ru
```

## Image Updater

The base Application includes Image Updater annotations:
- `argocd-image-updater.argoproj.io/image-list` - Image to track
- `argocd-image-updater.argoproj.io/chat.update-strategy` - semver
- `argocd-image-updater.argoproj.io/write-back-method` - git

This enables automatic image tag updates when new versions are pushed.

## Secrets Management

Each environment has its own SealedSecrets:
- `postgree-secrets.yaml` - Database credentials
- `openrouter-secrets.yaml` - API keys
- `github-secrets.yaml` - Git credentials for Image Updater

Create secrets using kubeseal:
```bash
kubectl create secret generic chat-openrouter \
  --from-literal=OPENROUTER_API_KEY=xxx \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace sealed-secrets \
           --controller-name sealed-secrets \
           -o yaml > openrouter-secrets.yaml
```

## Validation

Test kustomize build before committing:
```bash
kustomize build tenants/product-team/apps/chat/overlays/dev
```

## TODO

- [ ] Create SealedSecrets for tst, stg, prd environments
- [ ] Add tst, stg, prd cluster configurations
- [ ] Set up separate credentials per environment
