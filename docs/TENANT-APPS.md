# Tenant applications

Tenant application desired state lives in
[`app-poly-gitops-k8s/tenants`](https://github.com/justgithubaccount/app-poly-gitops-k8s/tree/main/tenants).
This infrastructure repository provisions the cluster and bootstraps Argo CD; it
does not duplicate application manifests.

## Current applications

### FastAPI

`tenants/product-team/apps/chat/base` defines one Argo CD `Application` for
the versioned `app-poly-gitops-helm` chart. The dev overlay supplies the
FastAPI image, resources, OpenAI-compatible provider endpoint/model, Vector OTLP
endpoint, and existing Secret name.

`clusters/smoke` uses the same base application with bounded inline values for
Jaeger and its provider endpoint. The `tst`, `stg`, and `prd` overlays are
incomplete scaffolding and are not part of the CI environment matrix.

### CrewAI

`tenants/product-team/apps/crewai/runtime` contains Deployment, Service,
ServiceAccount, and read-only Kubernetes RBAC. Dev and smoke overlays supply
their telemetry endpoints. The active environment roots patch the Argo CD
application to a versioned GitOps revision.

## Composition

~~~text
clusters/dev
  -> FastAPI dev overlay
     -> versioned Helm chart
        -> versioned FastAPI image
  -> CrewAI application
     -> dev runtime overlay
        -> versioned CrewAI image

clusters/smoke
  -> FastAPI base plus smoke values
  -> CrewAI base plus smoke runtime overlay
  -> Jaeger smoke manifests
~~~

Argo CD pulls the declared state and continuously reconciles it. Git history
provides the versioned, auditable source; automatic reconciliation does not make
an unreviewed branch a release.

## Secrets

Secrets are runtime inputs and are not stored in plaintext:

- FastAPI expects `chat-api/chat-openrouter` with
  `OPENROUTER_API_KEY` in the active profiles.
- CrewAI expects `crewai-system/crewai-llm` with
  `openai-api-key`.
- Dev public networking has additional Cloudflare, Grafana, and HTTP basic-auth
  Secrets documented in
  [DEV-WEBS.md](https://github.com/justgithubaccount/app-poly-gitops-k8s/blob/main/docs/DEV-WEBS.md).

The disposable Timeweb workflow creates the two application Secrets from the
`OPENAI_API_KEY` Actions secret. A local environment variable or repository
secret does not otherwise become a Kubernetes Secret.

## Adding an application

1. Add the application base under
   `tenants/<team>/apps/<application>/base`.
2. Pin its chart, image, or Git source to a reviewed version.
3. Add an environment overlay only when it has a complete runtime contract.
4. Reference that overlay from an active `clusters/<environment>` root.
5. Add rendered-contract tests and include the root in CI before calling the
   environment supported.
6. Document required Secrets and mutation permissions without committing values.

Render the affected root before proposing it:

~~~bash
kubectl kustomize clusters/dev > /tmp/app-poly-dev.yaml
kubectl kustomize clusters/smoke > /tmp/app-poly-smoke.yaml
~~~

See the GitOps repository
[architecture](https://github.com/justgithubaccount/app-poly-gitops-k8s/blob/main/docs/architecture.md)
for the active component and evidence boundaries.
