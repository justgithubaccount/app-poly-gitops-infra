
---

-------------------------------------------
**role:** file
**file:** .gitignore
**chunk:** 1/1

```
**/charts
cluster-creds.sh
```

-------------------------------------------
**role:** documentation
**file:** README.md
**chunk:** 1/1

```
# Description
This repository contains a demo materials used for the following talks:
* TBD

## Additional materials
* [Presentation](https://docs.google.com/presentation/d/1FF2bA9-Nalt5FLEQcJYjZsuYHekxjBIn/edit?usp=share_link&ouid=105692284649335634634&rtpof=true&sd=true)

## Prerequisites
* [Azure account](https://azure.microsoft.com/en-us/free/)
* [Cloudflare account](https://www.cloudflare.com/)
* [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [Helm](https://helm.sh/docs/intro/install/)
* [Kustomize](https://kustomize.io/)
* [Taskfile](https://taskfile.dev/#/installation)
## Provisioning
First, you need to authenticate to Azure using Azure CLI or get a service principal credentials. Also, you need to create a Cloudflare API token.
Then, copy the example `.tfvars` file and fill all required variables:
```shell
$ cp _terraform/terraform.tfvars.example _terraform/terraform.tfvars
```
Now the environment is ready to be provisioned. Run the following commands to create the infrastructure:
```shell
$ terraform -chdir=_terraform plan
$ terraform -chdir=_terraform apply
```
## Usage
Then, modify secondary clusters credentials in the [./argocd/values.yaml](./argocd/values.yaml) file (lines 8,10,49,56). All required parameters can be found via the `terraform output` command.

When we have the infrastructure ready, we can bootstrap our ArgoCD cluster, run the following command:
```shell
$ task bootstrap
```
Finally, we can apply one of ArgoCD [patterns](./patterns/):
```shell
$ task app-of-apps
```
or
```shell
$ task application-sets
```

For further customization, please check the directory of a pattern you've insterested in.
```

-------------------------------------------
**role:** config-yaml
**file:** argocd/values.yaml
**chunk:** 1/1

```
_: &config
  execProviderConfig:
    apiVersion: client.authentication.k8s.io/v1beta1
    command: argocd-k8s-auth
    env:
      AAD_ENVIRONMENT_NAME: AzurePublicCloud
      AAD_LOGIN_METHOD: msi
      AZURE_TENANT_ID: <AZURE_TENANT_ID>
      # ArgoCD Cluster Kubelet Identity
      # Take from the `argocd_identity` Terraform output
      AZURE_CLIENT_ID: <AZURE_CLIENT_ID>
    args:
      - azure
  tlsClientConfig:
    insecure: true

global:
  domain: argocd.owlish.cloud

configs:
  cm:
    create: true
    admin.enabled: true

    timeout.reconciliation: 20s
    timeout.hard.reconciliation: 0s

    kustomize.buildOptions: --enable-helm

    resource.customizations.ignoreDifferences.admissionregistration.k8s.io_ValidatingWebhookConfiguration: |
      jqPathExpressions:
      - .webhooks[].namespaceSelector.matchExpressions[] | select(.key == "control-plane")
      - .webhooks[].namespaceSelector.matchExpressions[] | select(.key == "kubernetes.azure.com/managedby")

  params:
    create: true
    server.insecure: "true"

  repositories:
    argocd-demo-repo:
      url: https://github.com/devOwlish/argocd-demo


  clusterCredentials:
    - name: demo-worker1
      labels:
        reflector.demo.owlish.cloud/enabled: "true"
      annotations:
        nginx.demo.owlish.cloud/version: "4.9.1"
      # Cluster endpoint
      # Take from the `worker1_host` Terraform output
      server: https://demo-worker1-kkapl87c.hcp.eastus2.azmk8s.io:443
      config: *config
    - name: demo-worker2
      labels:
        reflector.demo.owlish.cloud/enabled: "true"
      annotations:
        reflector.demo.owlish.cloud/version: "6.1.47"
      # Cluster endpoint
      # Take from the `worker1_host` Terraform output
      server: https://demo-worker2-ym9zdh79.hcp.eastus2.azmk8s.io:443
      config: *config

  secret:
    # admin
    argocdServerAdminPassword: "$2a$10$p7bNbfp4fkash35ZZmoM5.mYrpcQljU.Keu/vkXhtMCjzDzpETkcm"

server:
  ingress:
    enabled: true
    ingressClassName: "nginx"

# App used to sync ArgoCD with ArgoCD
extraObjects:
  - apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: argocd
      namespace: argocd
      labels:
        tier: cluster-addons
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      destination:
        name: in-cluster
        namespace: argocd
      project: default
      sources:
        - chart: argo-cd
          repoURL: https://argoproj.github.io/argo-helm
          targetRevision: 6.5.0
          helm:
            valueFiles:
              - $values/argocd/values.yaml
        - repoURL: https://github.com/devOwlish/argocd-demo
          targetRevision: main
          ref: values
      syncPolicy:
        automated:
          allowEmpty: true
          selfHeal: true
          prune: true
        syncOptions:
        - Validate=true
        - CreateNamespace=true
        - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/argocd/reflector.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
spec:
  source:
    helm:
      valuesObject:
        fullnameOverride: demo-super-reflector
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/argocd/cert-manager.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
spec:
  source:
    targetRevision: main
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/argocd/kustomization.yaml
**chunk:** 1/1

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namePrefix: in-cluster-

resources:
  - ../../base/addons/cert-manager
  - ../../base/addons/ingress-nginx
  - ../../base/addons/reflector

patches:
  # Override .spec.destination.name
  - path: destination.yaml
    target:
      kind: Application
  # App-specific patches
  - path: cert-manager.yaml
    target:
      kind: Application
      name: cert-manager
  - path: reflector.yaml
    target:
      kind: Application
      name: reflector
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/argocd/destination.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: all
  namespace: argocd
spec:
  project: default
  destination:
    name: in-cluster
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/worker2/kustomization.yaml
**chunk:** 1/1

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# All app names must be unique across the ArgoCD instance
# So let's prefix the app names with the cluster name (demo-worker2-)
namePrefix: demo-worker2-

resources:
  - ../../base/addons/cert-manager
  - ../../base/addons/ingress-nginx
  - ../../base/addons/reflector

patches:
  # Override .spec.destination.name
  - path: destination.yaml
    target:
      kind: Application
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/worker2/destination.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: all
  namespace: argocd
spec:
  project: default
  destination:
    name: demo-worker2
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/worker1/kustomization.yaml
**chunk:** 1/1

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# All app names must be unique across the ArgoCD instance
# So let's prefix the app names with the cluster name (demo-worker1-)
namePrefix: demo-worker1-

resources:
  - ../../base/addons/cert-manager
  - ../../base/addons/ingress-nginx
  - ../../base/addons/reflector

patches:
  # Override .spec.destination.name
  - path: destination.yaml
    target:
      kind: Application
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/worker1/destination.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: all
  namespace: argocd
spec:
  project: default
  destination:
    name: demo-worker1
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/cert-manager/application.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  labels:
    tier: cluster-addons
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: CLUSTER
    namespace: cert-manager
  project: default
  source:
    repoURL: https://github.com/devOwlish/argocd-demo.git
    path: manifests/cert-manager
    targetRevision: main
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
      - Validate=true
      - CreateNamespace=true
      - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/cert-manager/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/ingress-nginx/application.yaml
**chunk:** 1/1

```
# Placeholders that MUST be overridden by an overlay:
# - CLUSTER: the name of the target cluster to which the application should be deployed

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ingress-nginx
  namespace: argocd
  labels:
    tier: cluster-addons
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: CLUSTER
    namespace: ingress-nginx
  project: PROJECT
  source:
    repoURL: https://kubernetes.github.io/ingress-nginx
    chart: ingress-nginx
    targetRevision: 4.10.0
    helm:
      values: |
        fullnameOverride: ingress-nginx
        controller:
          service:
            annotations:
              service.beta.kubernetes.io/azure-pip-name: ingress-pip
              service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
          externalTrafficPolicy: Local
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
      - Validate=true
      - CreateNamespace=true
      - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/ingress-nginx/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/reflector/application.yaml
**chunk:** 1/1

```
# Placeholders that MUST be overridden by an overlay:
# - CLUSTER: the name of the target cluster to which the application should be deployed

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: reflector
  namespace: argocd
  labels:
    tier: cluster-addons
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: CLUSTER
    namespace: reflector
  project: default
  source:
    repoURL: https://emberstack.github.io/helm-charts
    chart: reflector
    targetRevision: 7.1.256
    helm:
      valuesObject:
        fullnameOverride: reflector
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
      - Validate=true
      - CreateNamespace=true
      - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/reflector/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc1/application.yaml
**chunk:** 1/1

```

```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc1/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc2/application.yaml
**chunk:** 1/1

```

```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc2/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc3/application.yaml
**chunk:** 1/1

```

```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc3/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/_main_apps/demo-worker1-apps.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-worker1-apps
  namespace: argocd
  labels:
    tier: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: in-cluster
    namespace: argocd
  project: default
  source:
    repoURL: https://github.com/devOwlish/argocd-demo.git
    path: patterns/app-of-apps/clusters/worker1
    targetRevision: main
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
    - Validate=true
    - CreateNamespace=true
    - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/_main_apps/demo-argocd-apps.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-argocd-apps
  namespace: argocd
  labels:
    tier: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: in-cluster
    namespace: argocd
  project: default
  source:
    repoURL: https://github.com/devOwlish/argocd-demo.git
    path: patterns/app-of-apps/clusters/argocd
    targetRevision: main
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
    - Validate=true
    - CreateNamespace=true
    - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/_main_apps/demo-worker2-apps.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-worker2-apps
  namespace: argocd
  labels:
    tier: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: in-cluster
    namespace: argocd
  project: default
  source:
    repoURL: https://github.com/devOwlish/argocd-demo.git
    path: patterns/app-of-apps/clusters/worker2
    targetRevision: main
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
    - Validate=true
    - CreateNamespace=true
    - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/application-sets/reflector.yaml
**chunk:** 1/1

```
---
# Labels used:
#   reflector.demo.owlish.cloud/enabled: "true" | whether Reflector is to be deployed.
# Annotations used:
#   reflector.demo.owlish.cloud/version: "4.10.0" | reflector chart version.
# http://masterminds.github.io/sprig/

apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: reflector
spec:
  goTemplate: true
  generators:
    # Get all clusters with the reflector.demo.owlish.cloud/enabled="true" label
    # Use the reflector.demo.owlish.cloud/version annotation (if exists) to set the chart version
    - clusters:
        selector:
          #  matchExpressions is also supported
          matchLabels:
            reflector.demo.owlish.cloud/enabled: "true"
        values:
          chartVersion: '{{ default "7.1.256" ( index ( default dict .metadata.annotations ) "reflector.demo.owlish.cloud/version"  ) }}'
  # Returns
  # - name: demo-worker1
  #   values:
  #     chartVersion: 7.1.256 ( a default value )
  # - name: demo-worker2
  #   values:
  #     chartVersion: 6.1.47 ( via the annotation )
  template:
    metadata:
      name: '{{ .name }}-reflector'
      labels:
        tier: infra
    spec:
      destination:
        name: '{{ .name }}'
        namespace: reflector
      project: 'default'
      source:
        repoURL: https://emberstack.github.io/helm-charts
        chart: reflector
        targetRevision: '{{ .values.chartVersion }}'
        helm:
          valuesObject:
            fullnameOverride: reflector
      syncPolicy:
        automated:
          allowEmpty: true
          selfHeal: true
          prune: true
        syncOptions:
          - Validate=true
          - CreateNamespace=true
          - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/application-sets/cert-manager.yaml
**chunk:** 1/1

```
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cert-manager
spec:
  generators:
    # Get all clusters registered in ArgoCD
    - clusters: {}
  # Returns
  # - name: demo-argocd
  # - name: demo-worker1
  # - name: demo-worker2
  template:
    metadata:
      name: '{{ name }}-cert-manager'
      labels:
        tier: infra
    spec:
      destination:
        name: '{{ name }}'
        namespace: cert-manager
      project: 'default'
      source:
        repoURL: https://github.com/devOwlish/argocd-demo.git
        path: manifests/cert-manager
        targetRevision: main
      syncPolicy:
        automated:
          allowEmpty: true
          selfHeal: true
          prune: true
        syncOptions:
          - Validate=true
          - CreateNamespace=true
          - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/application-sets/ingress-nginx.yaml
**chunk:** 1/1

```
---
# Annotations used:
#   nginx.demo.owlish.cloud/version: "4.10.0" | ingress-nginx chart version.
# http://masterminds.github.io/sprig/

apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: ingress-nginx
spec:
  goTemplate: true
  generators:
    # Get all clusters registered in ArgoCD
    # Use the nginx.demo.owlish.cloud/version annotation (if exists) to set the chart version
    - clusters:
        values:
          chartVersion: '{{ default "4.10.0" ( index ( default dict .metadata.annotations ) "nginx.demo.owlish.cloud/version"  ) }}'
  # Returns
  # - name: demo-argocd
  #   values:
  #     chartVersion: 4.9.1 ( via the annotation )
  # - name: demo-worker1
  #   values:
  #     chartVersion: 4.10.0 ( a default value )
  # - name: demo-worker2
  #   values:
  #     chartVersion: 4.10.0 ( a default value )
  template:
    metadata:
      name: '{{ .name }}-ingress-nginx'
      labels:
        tier: infra
    spec:
      destination:
        name: '{{ .name }}'
        namespace: ingress-nginx
      project: 'default'
      source:
        repoURL: https://kubernetes.github.io/ingress-nginx
        chart: ingress-nginx
        targetRevision: '{{ .values.chartVersion }}'
        helm:
          values: |
            fullnameOverride: ingress-nginx
            controller:
              service:
                annotations:
                  service.beta.kubernetes.io/azure-pip-name: ingress-pip
                  service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
              externalTrafficPolicy: Local
      syncPolicy:
        automated:
          allowEmpty: true
          selfHeal: true
          prune: true
        syncOptions:
          - Validate=true
          - CreateNamespace=true
          - PruneLast=true
```

-------------------------------------------
**role:** documentation
**file:** context_output.md
**chunk:** 1/2

```
# 📦 CREWAI/AI-КОНТЕКСТ: ПРОЕКТНЫЕ ФАЙЛЫ

Это экспорт файлов из проекта для передачи искусственному интеллекту или агенту (например, LLM или crewAI).  
Здесь каждый файл разбит на **чанки** — отдельные куски данных, чтобы AI мог эффективно читать, анализировать и строить ответы на их основе.

---

### 🤖 Зачем это нужно?

- Большой проект невозможно отправить AI-агенту целиком — его "контекстное окно" ограничено.
- Файлы делятся на логические части ("чанки").
- У каждого чанка есть метаданные: роль, путь, тип, номер чанка.
- В таком виде проект можно анализировать, рефакторить, строить документацию или делать автотесты силами ИИ.

---

### 🧩 Что такое "чанк"?

**Чанк** — это кусок файла ограниченного размера.  
Так проще пересылать и обрабатывать большие данные.

---

### ⚙️ Как устроен этот экспорт?

- Пробегаемся по проекту, исключая техпапки (.git, node_modules, ...).
- Для каждого файла определяем его роль по расширению.
- Если файл большой — делим на чанки.
- Каждый чанк оформлен в markdown с подписями.

---

-------------------------------------------
**role:** file
**file:** .gitignore
**chunk:** 1/1

```
**/charts
cluster-creds.sh
```

-------------------------------------------
**role:** documentation
**file:** README.md
**chunk:** 1/1

```
# Description
This repository contains a demo materials used for the following talks:
* TBD

## Additional materials
* [Presentation](https://docs.google.com/presentation/d/1FF2bA9-Nalt5FLEQcJYjZsuYHekxjBIn/edit?usp=share_link&ouid=105692284649335634634&rtpof=true&sd=true)

## Prerequisites
* [Azure account](https://azure.microsoft.com/en-us/free/)
* [Cloudflare account](https://www.cloudflare.com/)
* [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [Helm](https://helm.sh/docs/intro/install/)
* [Kustomize](https://kustomize.io/)
* [Taskfile](https://taskfile.dev/#/installation)
## Provisioning
First, you need to authenticate to Azure using Azure CLI or get a service principal credentials. Also, you need to create a Cloudflare API token.
Then, copy the example `.tfvars` file and fill all required variables:
```shell
$ cp _terraform/terraform.tfvars.example _terraform/terraform.tfvars
```
Now the environment is ready to be provisioned. Run the following commands to create the infrastructure:
```shell
$ terraform -chdir=_terraform plan
$ terraform -chdir=_terraform apply
```
## Usage
Then, modify secondary clusters credentials in the [./argocd/values.yaml](./argocd/values.yaml) file (lines 8,10,49,56). All required parameters can be found via the `terraform output` command.

When we have the infrastructure ready, we can bootstrap our ArgoCD cluster, run the following command:
```shell
$ task bootstrap
```
Finally, we can apply one of ArgoCD [patterns](./patterns/):
```shell
$ task app-of-apps
```
or
```shell
$ task application-sets
```

For further customization, please check the directory of a pattern you've insterested in.
```

-------------------------------------------
**role:** config-yaml
**file:** argocd/values.yaml
**chunk:** 1/1

```
_: &config
  execProviderConfig:
    apiVersion: client.authentication.k8s.io/v1beta1
    command: argocd-k8s-auth
    env:
      AAD_ENVIRONMENT_NAME: AzurePublicCloud
      AAD_LOGIN_METHOD: msi
      AZURE_TENANT_ID: <AZURE_TENANT_ID>
      # ArgoCD Cluster Kubelet Identity
      # Take from the `argocd_identity` Terraform output
      AZURE_CLIENT_ID: <AZURE_CLIENT_ID>
    args:
      - azure
  tlsClientConfig:
    insecure: true

global:
  domain: argocd.owlish.cloud

configs:
  cm:
    create: true
    admin.enabled: true

    timeout.reconciliation: 20s
    timeout.hard.reconciliation: 0s

    kustomize.buildOptions: --enable-helm

    resource.customizations.ignoreDifferences.admissionregistration.k8s.io_ValidatingWebhookConfiguration: |
      jqPathExpressions:
      - .webhooks[].namespaceSelector.matchExpressions[] | select(.key == "control-plane")
      - .webhooks[].namespaceSelector.matchExpressions[] | select(.key == "kubernetes.azure.com/managedby")

  params:
    create: true
    server.insecure: "true"

  repositories:
    argocd-demo-repo:
      url: https://github.com/devOwlish/argocd-demo


  clusterCredentials:
    - name: demo-worker1
      labels:
        reflector.demo.owlish.cloud/enabled: "true"
      annotations:
        nginx.demo.owlish.cloud/version: "4.9.1"
      # Cluster endpoint
      # Take from the `worker1_host` Terraform output
      server: https://demo-worker1-kkapl87c.hcp.eastus2.azmk8s.io:443
      config: *config
    - name: demo-worker2
      labels:
        reflector.demo.owlish.cloud/enabled: "true"
      annotations:
        reflector.demo.owlish.cloud/version: "6.1.47"
      # Cluster endpoint
      # Take from the `worker1_host` Terraform output
      server: https://demo-worker2-ym9zdh79.hcp.eastus2.azmk8s.io:443
      config: *config

  secret:
    # admin
    argocdServerAdminPassword: "$2a$10$p7bNbfp4fkash35ZZmoM5.mYrpcQljU.Keu/vkXhtMCjzDzpETkcm"

server:
  ingress:
    enabled: true
    ingressClassName: "nginx"

# App used to sync ArgoCD with ArgoCD
extraObjects:
  - apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: argocd
      namespace: argocd
      labels:
        tier: cluster-addons
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      destination:
        name: in-cluster
        namespace: argocd
      project: default
      sources:
        - chart: argo-cd
          repoURL: https://argoproj.github.io/argo-helm
          targetRevision: 6.5.0
          helm:
            valueFiles:
              - $values/argocd/values.yaml
        - repoURL: https://github.com/devOwlish/argocd-demo
          targetRevision: main
          ref: values
      syncPolicy:
        automated:
          allowEmpty: true
          selfHeal: true
          prune: true
        syncOptions:
        - Validate=true
        - CreateNamespace=true
        - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/argocd/reflector.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
spec:
  source:
    helm:
      valuesObject:
        fullnameOverride: demo-super-reflector
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/argocd/cert-manager.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
spec:
  source:
    targetRevision: main
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/argocd/kustomization.yaml
**chunk:** 1/1

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namePrefix: in-cluster-

resources:
  - ../../base/addons/cert-manager
  - ../../base/addons/ingress-nginx
  - ../../base/addons/reflector

patches:
  # Override .spec.destination.name
  - path: destination.yaml
    target:
      kind: Application
  # App-specific patches
  - path: cert-manager.yaml
    target:
      kind: Application
      name: cert-manager
  - path: reflector.yaml
    target:
      kind: Application
      name: reflector
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/argocd/destination.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: all
  namespace: argocd
spec:
  project: default
  destination:
    name: in-cluster
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/worker2/kustomization.yaml
**chunk:** 1/1

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# All app names must be unique across the ArgoCD instance
# So let's prefix the app names with the cluster name (demo-worker2-)
namePrefix: demo-worker2-

resources:
  - ../../base/addons/cert-manager
  - ../../base/addons/ingress-nginx
  - ../../base/addons/reflector

patches:
  # Override .spec.destination.name
  - path: destination.yaml
    target:
      kind: Application
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/worker2/destination.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: all
  namespace: argocd
spec:
  project: default
  destination:
    name: demo-worker2
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/worker1/kustomization.yaml
**chunk:** 1/1

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# All app names must be unique across the ArgoCD instance
# So let's prefix the app names with the cluster name (demo-worker1-)
namePrefix: demo-worker1-

resources:
  - ../../base/addons/cert-manager
  - ../../base/addons/ingress-nginx
  - ../../base/addons/reflector

patches:
  # Override .spec.destination.name
  - path: destination.yaml
    target:
      kind: Application
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/clusters/worker1/destination.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: all
  namespace: argocd
spec:
  project: default
  destination:
    name: demo-worker1
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/cert-manager/application.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  labels:
    tier: cluster-addons
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: CLUSTER
    namespace: cert-manager
  project: default
  source:
    repoURL: https://github.com/devOwlish/argocd-demo.git
    path: manifests/cert-manager
    targetRevision: main
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
      - Validate=true
      - CreateNamespace=true
      - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/cert-manager/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/ingress-nginx/application.yaml
**chunk:** 1/1

```
# Placeholders that MUST be overridden by an overlay:
# - CLUSTER: the name of the target cluster to which the application should be deployed

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ingress-nginx
  namespace: argocd
  labels:
    tier: cluster-addons
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: CLUSTER
    namespace: ingress-nginx
  project: PROJECT
  source:
    repoURL: https://kubernetes.github.io/ingress-nginx
    chart: ingress-nginx
    targetRevision: 4.10.0
    helm:
      values: |
        fullnameOverride: ingress-nginx
        controller:
          service:
            annotations:
              service.beta.kubernetes.io/azure-pip-name: ingress-pip
              service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
          externalTrafficPolicy: Local
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
      - Validate=true
      - CreateNamespace=true
      - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/ingress-nginx/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/reflector/application.yaml
**chunk:** 1/1

```
# Placeholders that MUST be overridden by an overlay:
# - CLUSTER: the name of the target cluster to which the application should be deployed

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: reflector
  namespace: argocd
  labels:
    tier: cluster-addons
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: CLUSTER
    namespace: reflector
  project: default
  source:
    repoURL: https://emberstack.github.io/helm-charts
    chart: reflector
    targetRevision: 7.1.256
    helm:
      valuesObject:
        fullnameOverride: reflector
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
      - Validate=true
      - CreateNamespace=true
      - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/addons/reflector/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc1/application.yaml
**chunk:** 1/1

```

```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc1/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc2/application.yaml
**chunk:** 1/1

```

```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc2/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc3/application.yaml
**chunk:** 1/1

```

```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/base/services/custom-svc3/kustomization.yaml
**chunk:** 1/1

```
resources:
  - application.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/_main_apps/demo-worker1-apps.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
k
```

-------------------------------------------
**role:** documentation
**file:** context_output.md
**chunk:** 2/2

```
ind: Application
metadata:
  name: demo-worker1-apps
  namespace: argocd
  labels:
    tier: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: in-cluster
    namespace: argocd
  project: default
  source:
    repoURL: https://github.com/devOwlish/argocd-demo.git
    path: patterns/app-of-apps/clusters/worker1
    targetRevision: main
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
    - Validate=true
    - CreateNamespace=true
    - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/_main_apps/demo-argocd-apps.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-argocd-apps
  namespace: argocd
  labels:
    tier: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: in-cluster
    namespace: argocd
  project: default
  source:
    repoURL: https://github.com/devOwlish/argocd-demo.git
    path: patterns/app-of-apps/clusters/argocd
    targetRevision: main
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
    - Validate=true
    - CreateNamespace=true
    - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/app-of-apps/_main_apps/demo-worker2-apps.yaml
**chunk:** 1/1

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-worker2-apps
  namespace: argocd
  labels:
    tier: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    name: in-cluster
    namespace: argocd
  project: default
  source:
    repoURL: https://github.com/devOwlish/argocd-demo.git
    path: patterns/app-of-apps/clusters/worker2
    targetRevision: main
  syncPolicy:
    automated:
      allowEmpty: true
      selfHeal: true
      prune: true
    syncOptions:
    - Validate=true
    - CreateNamespace=true
    - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/application-sets/reflector.yaml
**chunk:** 1/1

```
---
# Labels used:
#   reflector.demo.owlish.cloud/enabled: "true" | whether Reflector is to be deployed.
# Annotations used:
#   reflector.demo.owlish.cloud/version: "4.10.0" | reflector chart version.
# http://masterminds.github.io/sprig/

apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: reflector
spec:
  goTemplate: true
  generators:
    # Get all clusters with the reflector.demo.owlish.cloud/enabled="true" label
    # Use the reflector.demo.owlish.cloud/version annotation (if exists) to set the chart version
    - clusters:
        selector:
          #  matchExpressions is also supported
          matchLabels:
            reflector.demo.owlish.cloud/enabled: "true"
        values:
          chartVersion: '{{ default "7.1.256" ( index ( default dict .metadata.annotations ) "reflector.demo.owlish.cloud/version"  ) }}'
  # Returns
  # - name: demo-worker1
  #   values:
  #     chartVersion: 7.1.256 ( a default value )
  # - name: demo-worker2
  #   values:
  #     chartVersion: 6.1.47 ( via the annotation )
  template:
    metadata:
      name: '{{ .name }}-reflector'
      labels:
        tier: infra
    spec:
      destination:
        name: '{{ .name }}'
        namespace: reflector
      project: 'default'
      source:
        repoURL: https://emberstack.github.io/helm-charts
        chart: reflector
        targetRevision: '{{ .values.chartVersion }}'
        helm:
          valuesObject:
            fullnameOverride: reflector
      syncPolicy:
        automated:
          allowEmpty: true
          selfHeal: true
          prune: true
        syncOptions:
          - Validate=true
          - CreateNamespace=true
          - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/application-sets/cert-manager.yaml
**chunk:** 1/1

```
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cert-manager
spec:
  generators:
    # Get all clusters registered in ArgoCD
    - clusters: {}
  # Returns
  # - name: demo-argocd
  # - name: demo-worker1
  # - name: demo-worker2
  template:
    metadata:
      name: '{{ name }}-cert-manager'
      labels:
        tier: infra
    spec:
      destination:
        name: '{{ name }}'
        namespace: cert-manager
      project: 'default'
      source:
        repoURL: https://github.com/devOwlish/argocd-demo.git
        path: manifests/cert-manager
        targetRevision: main
      syncPolicy:
        automated:
          allowEmpty: true
          selfHeal: true
          prune: true
        syncOptions:
          - Validate=true
          - CreateNamespace=true
          - PruneLast=true
```

-------------------------------------------
**role:** config-yaml
**file:** patterns/application-sets/ingress-nginx.yaml
**chunk:** 1/1

```
---
# Annotations used:
#   nginx.demo.owlish.cloud/version: "4.10.0" | ingress-nginx chart version.
# http://masterminds.github.io/sprig/

apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: ingress-nginx
spec:
  goTemplate: true
  generators:
    # Get all clusters registered in ArgoCD
    # Use the nginx.demo.owlish.cloud/version annotation (if exists) to set the chart version
    - clusters:
        values:
          chartVersion: '{{ default "4.10.0" ( index ( default dict .metadata.annotations ) "nginx.demo.owlish.cloud/version"  ) }}'
  # Returns
  # - name: demo-argocd
  #   values:
  #     chartVersion: 4.9.1 ( via the annotation )
  # - name: demo-worker1
  #   values:
  #     chartVersion: 4.10.0 ( a default value )
  # - name: demo-worker2
  #   values:
  #     chartVersion: 4.10.0 ( a default value )
  template:
    metadata:
      name: '{{ .name }}-ingress-nginx'
      labels:
        tier: infra
    spec:
      destination:
        name: '{{ .name }}'
        namespace: ingress-nginx
      project: 'default'
      source:
        repoURL: https://kubernetes.github.io/ingress-nginx
        chart: ingress-nginx
        targetRevision: '{{ .values.chartVersion }}'
        helm:
          values: |
            fullnameOverride: ingress-nginx
            controller:
              service:
                annotations:
                  service.beta.kubernetes.io/azure-pip-name: ingress-pip
                  service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
              externalTrafficPolicy: Local
      syncPolicy:
        automated:
          allowEmpty: true
          selfHeal: true
          prune: true
        syncOptions:
          - Validate=true
          - CreateNamespace=true
          - PruneLast=true
```
```

-------------------------------------------
**role:** config-yaml
**file:** manifests/cert-manager/kustomization.yaml
**chunk:** 1/1

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
  - name: cert-manager
    repo: https://charts.jetstack.io
    version: v1.14.3
    namespace: cert-manager
    valuesInline:
      fullnameOverride: cert-manager
      installCRDs: true

resources:
  - cluster-issuer.yaml
```

-------------------------------------------
**role:** config-yaml
**file:** manifests/cert-manager/cluster-issuer.yaml
**chunk:** 1/1

```
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: me@owlish.cloud
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - http01:
          ingress:
            class: nginx

---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: me@owlish.cloud
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

-------------------------------------------
**role:** file
**file:** _terraform/.gitignore
**chunk:** 1/1

```
# Local .terraform directories
**/.terraform/*

# .tfstate files
*.tfstate
*.tfstate.*

# Crash log files
crash.log
crash.*.log

# Exclude all .tfvars files, which are likely to contain sensitive data, such as
# password, private keys, and other secrets. These should not be part of version
# control as they are data points which are potentially sensitive and subject
# to change depending on the environment.
*.tfvars
*.tfvars.json

# Ignore override files as they are usually used to override resources locally and so
# are not checked in
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Include override files you do wish to add to version control using negated pattern
# !example_override.tf

# Include tfplan files to ignore the plan output of command: terraform plan -out=tfplan
# example: *tfplan*

# Ignore CLI configuration files
.terraformrc
terraform.rc
```

-------------------------------------------
**role:** file
**file:** _terraform/modules/aks/outputs.tf
**chunk:** 1/1

```
output "ingress_ip" {
  value = azurerm_public_ip.ingress.ip_address
}

output "host" {
  value = azurerm_kubernetes_cluster.cluster.kube_config.0.host
}

output "identity" {
  value = azurerm_kubernetes_cluster.cluster.kubelet_identity.0.object_id
}

output "id" {
  value = azurerm_kubernetes_cluster.cluster.id
}
```

-------------------------------------------
**role:** file
**file:** _terraform/modules/aks/variables.tf
**chunk:** 1/1

```
variable "location" {
  description = "The location/region where the AKS clusters will be created"
  default     = "eastus2"
}

variable "name" {
  description = "The name of the AKS cluster"
}

variable "subnet_cidr" {
  description = "The CIDR block for the AKS subnet"
  default     = ["10.1.1.0/24"]
}
```

-------------------------------------------
**role:** file
**file:** _terraform/modules/aks/main.tf
**chunk:** 1/1

```
resource "azurerm_resource_group" "cluster" {
  location = var.location
  name     = var.name
}

resource "azurerm_virtual_network" "cluster" {
  name                = var.name
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  address_space       = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "cluster" {
  name                 = var.name
  resource_group_name  = azurerm_resource_group.cluster.name
  virtual_network_name = azurerm_virtual_network.cluster.name
  address_prefixes     = var.subnet_cidr
}


resource "azurerm_kubernetes_cluster" "cluster" {
  name                = var.name
  dns_prefix          = var.name
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  node_resource_group = "${azurerm_resource_group.cluster.name}-nodepool"


  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.cluster.id
  }

  identity {
    type = "SystemAssigned"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    managed            = true
  }
}

resource "azurerm_public_ip" "ingress" {
  name                = "ingress-pip"
  location            = azurerm_kubernetes_cluster.cluster.location
  resource_group_name = "${azurerm_resource_group.cluster.name}-nodepool"
  sku                 = "Standard"
  allocation_method   = "Static"
}
```

-------------------------------------------
**role:** file
**file:** _terraform/cloudflare.tf
**chunk:** 1/1

```
data "cloudflare_zone" "owlish" {
  name = var.cloudflare_zone_name
}

resource "cloudflare_record" "argocd" {
  zone_id = data.cloudflare_zone.owlish.id
  name    = "argocd"
  value   = module.aks["demo-argocd"].ingress_ip
  type    = "A"
  ttl     = 1
  proxied = true
}
```

-------------------------------------------
**role:** file
**file:** _terraform/outputs.tf
**chunk:** 1/1

```
output "argocd_identity" {
  value = module.aks["demo-argocd"].identity
}
output "worker1_host" {
  value     = module.aks["demo-worker1"].host
  sensitive = true
}
output "worker2_host" {
  value     = module.aks["demo-worker2"].host
  sensitive = true
}
```

-------------------------------------------
**role:** file
**file:** _terraform/terraform.tfvars.example
**chunk:** 1/1

```
tenant_id = ""
subscription_id = ""
cloudflare_api_token = ""
cloudflare_account_id = ""
cloudflare_zone_name = ""
```

-------------------------------------------
**role:** file
**file:** _terraform/variables.tf
**chunk:** 1/1

```
variable "tenant_id" {}
variable "subscription_id" {}
variable "cloudflare_api_token" {}
variable "cloudflare_account_id" {}
variable "cloudflare_zone_name" {}
##
variable "location" {
  description = "The location/region where the AKS clusters will be created"
  default     = "eastus2"
}

variable "prefix" {
  description = "The prefix which should be used for all resources in this example"
  default     = "demo"
}

variable "cluster_names" {
  type        = set(string)
  description = "Names of the AKS clusters to create"
  default = [
    "argocd",
    "worker1",
    "worker2"
  ]
}
```

-------------------------------------------
**role:** file
**file:** _terraform/provider.tf
**chunk:** 1/1

```
terraform {
  required_version = ">=1.3"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.51, < 4.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

}
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
```

-------------------------------------------
**role:** file
**file:** _terraform/main.tf
**chunk:** 1/1

```
locals {
  clusters_names = toset([for name in var.cluster_names : "${var.prefix}-${name}"])
}

module "aks" {
  source = "./modules/aks"

  for_each = local.clusters_names

  location = var.location
  name     = each.value
}


resource "azurerm_role_assignment" "worker1" {
  scope                            = module.aks["demo-worker1"].id
  role_definition_name             = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id                     = module.aks["demo-argocd"].identity
  skip_service_principal_aad_check = true
}


resource "azurerm_role_assignment" "worker2" {
  scope                            = module.aks["demo-worker2"].id
  role_definition_name             = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id                     = module.aks["demo-argocd"].identity
  skip_service_principal_aad_check = true
}
```

-------------------------------------------
**role:** config-yaml
**file:** Taskfile.yml
**chunk:** 1/1

```
# https://taskfile.dev
version: '3'

tasks:
  bootstrap:
    desc: "Bootstrap the demo environment"
    cmds:
      - task: cluster-creds
      - kubectl config use-context demo-argocd
      - task: argocd

  cluster-creds:
    desc: "Get cluster credentials"
    cmds:
      - az aks get-credentials --resource-group demo-worker1 --name demo-worker1 --overwrite-existing
      - az aks get-credentials --resource-group demo-worker2 --name demo-worker2 --overwrite-existing
      - az aks get-credentials --resource-group demo-argocd --name demo-argocd --overwrite-existing

  argocd:
    desc: "Install ArgoCD"
    cmds:
      - kubectl create namespace argocd
      - kubectl config set-context --current --namespace=argocd
      - helm template argocd argo/argo-cd --version 5.53.0 --values argocd/values.yaml | kubectl apply -f - || helm template argocd argo/argo-cd --version 5.53.0 --values argocd/values.yaml | kubectl apply -f -


  app-of-apps:
    desc: "Deploy the app-of-apps pattern"
    cmds:
      - kubectl apply -f patterns/app-of-apps/_main_apps

  application-sets:
    desc: "Deploy the app-of-apps pattern"
    cmds:
      - kubectl apply -f patterns/application-sets
```

