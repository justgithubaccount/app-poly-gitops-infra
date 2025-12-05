# CLAUDE.md

## Обзор проекта

Инфраструктурный репозиторий для provisioning Kubernetes кластера в Timeweb Cloud и bootstrap ArgoCD.

## Структура

```
terraform/timeweb/   # Terraform для Timeweb Cloud (k8s cluster)
bootstrap/argocd/    # ArgoCD Helm values для начальной установки
Taskfile.yaml        # Автоматизация через Taskfile
```

## Связанные репозитории

- `app-poly-gitops-k8s` — GitOps манифесты (ArgoCD Applications)
- `app-poly-gitops-helm` — Helm chart для сервисов
- `app-poly-gitops-fastapi` — FastAPI сервис
- `app-poly-gitops-crewai` — CrewAI мониторинг

## Основные команды

```bash
# Полный setup (terraform + argocd + app-of-apps)
task up

# Отдельные шаги
task init          # Terraform init + apply
task kubeconfig    # Получить kubeconfig
task bootstrap     # Установить ArgoCD
task app-of-apps   # Деплой root Application

# Утилиты
task argocd-password      # Получить пароль admin
task argocd-port-forward  # Port-forward UI

# Удаление
task destroy       # Уничтожить инфраструктуру
```

## Переменные окружения

```bash
export TF_VAR_timeweb_token="your-token"
export AWS_ACCESS_KEY_ID="s3-access-key"      # Для S3 backend
export AWS_SECRET_ACCESS_KEY="s3-secret-key"  # Для S3 backend
```

## Workflow

1. `task init` — создает k8s кластер в Timeweb
2. `task bootstrap` — устанавливает ArgoCD через Helm
3. `task app-of-apps` — деплоит root Application из app-poly-gitops-k8s

После этого ArgoCD управляет сам собой через multi-source Application.

## Важно

- Terraform state хранится в S3 (Timeweb)
- Токен Timeweb передается через `TF_VAR_timeweb_token`
- ArgoCD после bootstrap становится self-managed
- Все изменения ArgoCD делаются через bootstrap/argocd/values.yaml
