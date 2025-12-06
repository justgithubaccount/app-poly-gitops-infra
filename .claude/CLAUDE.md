# CLAUDE.md

## Обзор проекта

Это часть **app-poly-gitops** — экосистемы из 5 репозиториев для GitOps-управления Kubernetes кластером.

Данный репозиторий (`app-poly-gitops-infra`) — инфраструктурный, для provisioning Kubernetes кластера в Timeweb Cloud и bootstrap ArgoCD.

## Экосистема app-poly-gitops (5 репозиториев)

Все репозитории расположены в `~/docs/github/`:

| Репозиторий | Назначение |
|-------------|------------|
| `app-poly-gitops-infra` | **Этот репо.** Terraform + Taskfile для создания кластера и bootstrap ArgoCD |
| `app-poly-gitops-k8s` | GitOps манифесты: ArgoCD Applications, platform (ingress, cert-manager, etc.), tenants |
| `app-poly-gitops-helm` | Helm chart для chat-api сервиса |
| `app-poly-gitops-fastapi` | FastAPI сервис — исходный код приложения |
| `app-poly-gitops-crewai` | CrewAI агенты для мониторинга и автоматизации |

### Поток данных

```
app-poly-gitops-infra     →  Создает K8s кластер + ArgoCD
         ↓
app-poly-gitops-k8s       →  ArgoCD читает манифесты и деплоит
         ↓
app-poly-gitops-helm      →  Helm chart для сервисов (chat-api)
         ↓
app-poly-gitops-fastapi   →  Docker image → GHCR → Image Updater → Helm
```

## Структура этого репозитория

```
terraform/timeweb/   # Terraform для Timeweb Cloud (k8s cluster)
bootstrap/argocd/    # ArgoCD Helm values для начальной установки
scripts/             # Утилиты (seal.sh, argocd-status.sh, etc.)
Taskfile.yaml        # Автоматизация через Taskfile
.env                 # Секреты (не коммитить!)
.env.example         # Шаблон секретов с документацией
```

## Переменные окружения (.env)

Скопировать `.env.example` → `.env` и заполнить значения.

### Обязательные

| Переменная | Описание |
|------------|----------|
| `TF_VAR_timeweb_token` | Timeweb Cloud API token |
| `AWS_ACCESS_KEY_ID` | S3 credentials для Terraform state |
| `AWS_SECRET_ACCESS_KEY` | S3 credentials для Terraform state |

### Для SealedSecrets

| Переменная | Описание |
|------------|----------|
| `OPENROUTER_API_KEY` | OpenRouter API для chat-api |
| `GITHUB_PAT` | GitHub PAT для Image Updater |
| `GITHUB_USERNAME` | GitHub username |
| `GITHUB_REPO_URL` | URL Helm репозитория |
| `CLOUDFLARE_TOKEN` | Cloudflare API для DNS |

## Основные команды Taskfile

### Полный workflow

```bash
task up       # Создать кластер: init + bootstrap + app-of-apps
task down     # Удалить кластер (alias для destroy)
task destroy  # Удалить кластер с подтверждением
```

### Инфраструктура

```bash
task init       # Terraform init + apply + kubeconfig
task plan       # Показать Terraform plan
task kubeconfig # Получить kubeconfig из Terraform
task refresh    # Обновить Terraform state
```

### ArgoCD Bootstrap

```bash
task bootstrap         # Установить ArgoCD через Helm
task app-of-apps       # Деплой root Application
task argocd-password   # Получить пароль admin
task argocd-port-forward  # Port-forward UI на localhost:8080
```

### ArgoCD CLI

```bash
task argocd:login       # Залогиниться в ArgoCD CLI
task argocd:list        # Список всех Applications
task argocd:get -- app  # Детали приложения
task argocd:sync -- app # Синхронизировать приложение
task argocd:sync-all    # Синхронизировать все
task argocd:refresh -- app  # Обновить манифесты из Git
task argocd:diff -- app     # Показать diff
task argocd:wait -- app     # Ждать sync + healthy
```

### Диагностика

```bash
task status              # Проверить статус ArgoCD (через скрипт)
task status -- app       # Детали конкретного приложения
task sync-wait -- app    # Ждать синхронизации

task nodes               # Ноды кластера
task pods -- ns          # Pods в namespace
task pods:all            # Все pods
task events -- ns        # События в namespace
task logs -- pod -n ns   # Логи пода
task describe -- pod/x -n ns  # Describe ресурса
```

### SealedSecrets

```bash
task seal:openrouter     # Создать OpenRouter SealedSecret
task seal:github         # Создать GitHub SealedSecret
task seal:cloudflare     # Создать Cloudflare SealedSecret
task seal:postgres       # Создать PostgreSQL SealedSecret
task seal -- name ns KEY=value  # Произвольный секрет
```

## Workflow: Создание кластера с нуля

1. **Подготовка**
   ```bash
   cp .env.example .env
   # Заполнить .env реальными значениями
   ```

2. **Создание кластера**
   ```bash
   task up
   ```
   Это выполнит:
   - `task init` — Terraform создаст k8s кластер в Timeweb
   - `task bootstrap` — Установит ArgoCD
   - `task app-of-apps` — Задеплоит root Application
   - `task argocd-password` — Покажет пароль admin

3. **Доступ к ArgoCD**
   ```bash
   task argocd-port-forward  # В отдельном терминале
   # Открыть https://localhost:8080
   # Login: admin / пароль из task argocd-password
   ```

4. **Создание секретов** (после первого sync)
   ```bash
   task argocd:login
   task seal:openrouter     # Для chat-api
   task seal:cloudflare     # Для external-dns и cert-manager
   # Закоммитить SealedSecrets в app-poly-gitops-k8s
   ```

## Архитектура GitOps

```
task up
    │
    ├── Terraform → K8s Cluster (Timeweb)
    │
    ├── Helm → ArgoCD (bootstrap)
    │
    └── kubectl apply → app-of-apps.yaml
                            │
                            ├── argocd Application (self-managed)
                            ├── dev-cluster Application
                            │       ├── Platform (cert-manager, ingress, etc.)
                            │       └── Tenants (chat-api, PostgreSQL, etc.)
                            └── ... other environments
```

## Важные заметки

- **Terraform state** хранится в S3 (Timeweb Object Storage)
- **ArgoCD** после bootstrap становится self-managed через app-of-apps
- **Секреты** — используем SealedSecrets, создаются через `task seal:*`
- **Reflector** — реплицирует секреты между namespaces (cloudflare-token)
- **KUBECONFIG** — автоматически экспортируется через `env:` в Taskfile

## Troubleshooting

```bash
# Проверить статус ArgoCD apps
task status
task argocd:list

# Синхронизировать конкретное приложение
task argocd:sync -- dev-cluster

# Ждать синхронизации
task sync-wait -- dev-cluster

# Посмотреть логи
task logs -- argocd-server-xxx -n argocd

# Проверить events
task events -- chat-api
```
