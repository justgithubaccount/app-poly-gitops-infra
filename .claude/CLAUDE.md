# CLAUDE.md

Инфраструктурный репозиторий: Kubernetes кластер в Timeweb Cloud + ArgoCD bootstrap.

## Команды

**Taskfile.yaml — источник правды.** Смотри `task --list` для актуального списка команд.

Основные:
- `task up` — полный setup (init + bootstrap + app-of-apps)
- `task destroy` — удалить инфраструктуру

## Переменные окружения

Хранятся в `.env` (загружается автоматически через dotenv в Taskfile):
- `TF_VAR_timeweb_token` — токен Timeweb Cloud
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — для S3 backend

## Структура

```
terraform/timeweb/   # Terraform (k8s cluster)
bootstrap/argocd/    # ArgoCD Helm values
scripts/             # Вспомогательные скрипты для task
Taskfile.yaml        # Все команды здесь
```

## Связанные репозитории

- `app-poly-gitops-k8s` — GitOps манифесты (ArgoCD Applications)
- `app-poly-gitops-helm` — Helm charts
- `app-poly-gitops-fastapi` — FastAPI сервис
