# CLAUDE.md

Инфраструктурный репозиторий: Kubernetes кластер в Timeweb Cloud + ArgoCD bootstrap.

## Команды

**Taskfile.yaml — источник правды.** Смотри `task --list` для актуального списка команд.

Основные:
- `task up` — полный setup (init + bootstrap + app-of-apps)
- `task destroy` — удалить инфраструктуру
- `task status` — проверить статус ArgoCD приложений
- `task argocd-password` — получить пароль admin
- `task argocd-port-forward` — проброс порта ArgoCD UI

Sealed Secrets:
- `task seal:openrouter` — создать SealedSecret для OpenRouter API
- `task seal:github` — создать SealedSecret для GitHub репо
- `task seal:postgree` — создать SealedSecret для PostgreSQL

## Переменные окружения

Хранятся в `.env` (загружается автоматически через dotenv в Taskfile):
- `TF_VAR_timeweb_token` — токен Timeweb Cloud
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — для S3 backend
- `OPENROUTER_API_KEY` — ключ OpenRouter API
- `GITHUB_PAT` / `GITHUB_USERNAME` / `GITHUB_REPO_URL` — для ArgoCD Image Updater
- `CLOUDFLARE_TOKEN` — токен Cloudflare API для cert-manager и external-dns

## Структура

```
terraform/timeweb/   # Terraform (k8s cluster)
bootstrap/argocd/    # ArgoCD Helm values (self-managed ArgoCD Application)
scripts/             # Вспомогательные скрипты для task
  - argocd-status.sh   # Проверка статуса ArgoCD
  - seal.sh            # Создание SealedSecrets
Taskfile.yaml        # Все команды здесь
```

## Kubeconfig

После `task init` kubeconfig сохраняется в `~/.kube/timeweb-config`.
Taskfile автоматически использует этот путь через `KUBECONFIG` env.

## ArgoCD доступ

- URL: https://argo.syncjob.ru
- User: admin
- Password: `task argocd-password`

## Golden Install — важные настройки

При чистой установке с нуля учитывай следующие моменты:

1. **ArgoCD Ingress** — управляется через GitOps в `app-poly-gitops-k8s` (ingress-argo.yaml), не через Helm chart. В `values.yaml` отключён `server.ingress.enabled: false`.

2. **ArgoCD insecure mode** — сервер работает в HTTP режиме (`server.insecure: true`). Ingress НЕ должен иметь аннотацию `backend-protocol: HTTPS`.

3. **Cloudflare token secret** — ключ в секрете должен быть `CF_API_TOKEN` (не `cloudflare-api-token`). Используется cert-manager и external-dns.

4. **Reflector аннотации** — для репликации секретов между namespaces (например cloudflare-token из external-dns в cert-manager).

5. **Sync Waves** — критичны для CRD-зависимых ресурсов. Операторы (sync-wave: "1") должны деплоиться раньше их CR (sync-wave: "3"+).

## Связанные репозитории

- `app-poly-gitops-k8s` — GitOps манифесты (ArgoCD Applications, kustomize overlays)
- `app-poly-gitops-helm` — Helm charts для приложений
- `app-poly-gitops-fastapi` — FastAPI сервис (chat-api)
