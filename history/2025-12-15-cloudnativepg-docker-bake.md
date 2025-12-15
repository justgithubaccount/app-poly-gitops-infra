# CloudNativePG: Customizing Docker Build Bake HCL

**Дата:** 2025-12-15
**Источник:** https://cloudnative-pg.io/blog/customizing-docker-build-bake/
**Автор:** Daniel Chambre

## Краткое содержание

Статья описывает кастомизацию Docker-образов PostgreSQL для CloudNativePG с использованием `docker buildx bake` и override HCL файлов.

## Проблема

Ручной процесс создания кастомных образов:
1. Клонировать репо
2. Редактировать Dockerfile
3. Билдить образ
4. Пушить в registry

Повторять для каждой версии PostgreSQL — много рутинной работы.

## Решение: docker buildx bake с override HCL

### Шаг 1: Подготовить локальный bake.hcl

```hcl
platforms = [
  "linux/amd64",
]

extensions = [
  "dbgsym",
  "partman",
  "oracle-fdw",
  "squeeze",
  "show-plans",
  "cron",
  "tds-fdw",
]

target "myimage" {
  dockerfile-inline = <<EOT
ARG BASE_IMAGE="ghcr.io/cloudnative-pg/postgresql:16.9-standard-bookworm"
FROM $BASE_IMAGE AS myimage
ARG EXTENSIONS
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends $EXTENSIONS \
    ldap-utils \
    ca-certificates \
    openssl \
    procps \
    postgresql-plpython3-"${getMajor(pgVersion)}" \
    python3-psutil \
    pgtop \
    pg-activity \
    nmon \
    libsybdb5 \
    freetds-dev \
    freetds-common && \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
    rm -rf /var/lib/apt/lists/* /var/cache/* /var/log/*
RUN sed -i -e 's/# de_AT.UTF-8 UTF-8/de_AT.UTF-8 UTF-8/' /etc/locale.gen && \
        locale-gen
ADD https://your.git.url/postgresql/-/blob/main/.psqlrc?ref_type=heads /var/lib/postgresql/
ADD https://your.git.url/cloudnativepg/-/blob/main/bake/files/etc/ldap/ldap.conf?ref_type=heads /etc/ldap/
ADD https://your.git.url/cloudnativepg/-/blob/main/bake/files/usr/local/share/ca-certificates/EuropeanSSLServerCA2.crt?ref_type=heads /usr/local/share/ca-certificates/
ADD https://your.git.url/cloudnativepg/-/blob/main/bake/files/usr/local/share/ca-certificates/RootCA1v0.crt?ref_type=heads /usr/local/share/ca-certificates/
ADD https://your.git.url/cloudnativepg/-/blob/main/bake/files/usr/local/share/ca-certificates/SubCA1v1.crt?ref_type=heads /usr/local/share/ca-certificates/
RUN update-ca-certificates
USER 26
EOT
  matrix = {
    tgt = [
      "myimage"
    ]
    pgVersion = [
      "13.21",
      "14.18",
      "15.13",
      "16.9",
      "17.5",
    ]
  }
  name = "postgresql-${index(split(".",cleanVersion(pgVersion)),0)}-standard-bookworm"
  target = "${tgt}"
  args = {
    BASE_IMAGE = "ghcr.io/cloudnative-pg/postgresql:${cleanVersion(pgVersion)}-standard-bookworm",
    EXTENSIONS = "${getExtensionsString(pgVersion, extensions)}",
  }
}
```

### Шаг 2: Билд образа

```bash
environment=production registry=your.repo.url docker buildx bake \
  -f docker-bake.hcl \
  -f cwd://bake.hcl \
  "https://github.com/cloudnative-pg/postgres-containers.git" \
  myimage
```

### Шаг 3: Использование

Обновить Image Catalog / Cluster Image Catalog с новыми образами.

## Что добавляется в кастомный образ

### Расширения PostgreSQL
- dbgsym, partman, oracle-fdw, squeeze, show-plans, cron, tds-fdw

### Утилиты
- ldap-utils, ca-certificates, openssl, procps
- postgresql-plpython3
- python3-psutil
- pgtop, pg-activity
- nmon
- libsybdb5, freetds-dev, freetds-common

### Конфигурация
- Кастомный .psqlrc
- LDAP конфигурация
- CA сертификаты
- Локали (de_AT.UTF-8)

## Преимущества

После настройки override файла остаётся только:
1. Обновить переменную `pgVersion`
2. Запустить `docker buildx bake`

## Ссылки

- [CloudNativePG](https://cloudnative-pg.io/)
- [postgres-containers repo](https://github.com/cloudnative-pg/postgres-containers)
- [CNCF Slack - CloudNativePG channels](https://slack.cncf.io/)

---

## Применимость к нашему проекту

В текущем GitOps-стеке (`app-poly-gitops-infra`) PostgreSQL ещё не развёрнут.

### Для интеграции CloudNativePG потребуется:

1. **Добавить CloudNativePG оператор** в `app-poly-gitops-k8s`:
   - ArgoCD Application для Helm-чарта оператора
   - Namespace для PostgreSQL

2. **Создать Cluster манифест**:
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: chat-postgres
   spec:
     instances: 3
     imageName: ghcr.io/cloudnative-pg/postgresql:16.9-standard-bookworm
     # или кастомный образ
     storage:
       size: 10Gi
   ```

3. **Настроить SealedSecrets** для credentials (уже есть таска `seal:postgree`)

4. **Опционально**: собрать кастомный образ по методике из статьи
