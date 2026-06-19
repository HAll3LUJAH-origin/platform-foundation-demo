# Platform Foundation — orders-api

Минимальная платформенная основа для `orders-api`. Запускается локально в `kind`, деплоится в dev и stage, и имеет ровно столько обзервабилности и ограждений, чтобы деплоить без лишних нервов.

Облачный аккаунт не нужен. Меняешь аутентификацию провайдера и Terraform backend — и всё это работает на EKS/GKE/AKS.

---

## Запуск локально

Нужно: `docker`, `kind`, `kubectl`, `helm`, `terraform`, `make`.

```bash
# 1. Кластер + локальный registry
make cluster

# 2. Стек мониторинга (Prometheus Operator + Prometheus + Grafana)
make monitoring

# 3. Инфраструктура для dev
make infra ENV=dev

# 4. Сборка образа
make build TAG=sha-local

# 5. Деплой в dev
make deploy ENV=dev TAG=sha-local

# Проверка
kubectl -n orders-api-dev port-forward svc/orders-api 8080:80
curl localhost:8080/healthz && curl localhost:8080/metrics
```

Для stage — шаги 3–5 с `ENV=stage`, или `make all ENV=stage` разом.

Алерты по требованию (в dev включены debug-эндпоинты):

```bash
make drill ENV=dev      # 60% ошибок + 700ms задержки, непрерывная нагрузка
```

Откат:

```bash
make rollback ENV=dev
```

---

## Что внутри

```
app/                      Минимальный Go-сервис (только stdlib): health-пробы + метрики
infra/terraform/          IaC — отдельный root на каждый env
  modules/environment/    namespace, quota, limitrange, default-deny netpol, least-priv RBAC
  environments/dev|stage/ тонкие root'ы с отдельным state
helm/orders-api/          Чарт: Deployment, Service, HPA, PDB, пробы, ServiceMonitor, алерты, NetworkPolicy
  values.yaml             значения по умолчанию
  values-dev.yaml         переопределения dev (дёшево, debug включён)
  values-stage.yaml       переопределения stage (HA, debug выключен)
.github/workflows/        ci.yaml (lint/test/build/scan) + deploy.yaml (ручной, с гейтом)
observability/            эскиз дашборда, список метрик, импортируемый Grafana JSON
policy/                   admission-политики Kyverno
scripts/                  bootstrap kind + локального registry
RUNBOOK.md                реагирование на инциденты (основной: высокий 5xx)
OPERATIONS.md             процедуры деплоя / отката / мониторинга
RELEASE_CHECKLIST.md      гейт перед релизом
PREVIEW_ENVIRONMENTS.md   preview-окружения на PR (проектная заметка, не реализовано)
SECRETS.md                нет секретов в git, network policy, allowlist вебхуков
```

## Сервис

`orders-api` — намеренно крошечная заглушка нагрузки. Шесть эндпоинтов:

- `GET /` — основной маршрут, учитывается в метриках
- `GET /healthz` — liveness (процесс жив)
- `GET /readyz` — readiness (прогрелся; отдаёт ошибку при drain)
- `GET /metrics` — экспозиция Prometheus
- `GET /debug/fail?rate=&latency_ms=` — инъекция отказов, только dev

Ноль внешних зависимостей. Герметичная сборка. Образ `distroless/static:nonroot` — без shell, uid 65532, read-only корневая ФС.

---

## Решения

**Отдельные Terraform-root'ы на env, а не workspaces.** Отдельные state-файлы и `*.tfvars` делают различия dev/stage явными и ревьюабельными. Workspaces используют общий state, и это нормально — пока кто-нибудь не применит не то окружение. Отдельные root'ы этот сценарий просто исключают.

**Namespace как граница изоляции.** По одному namespace на env, каждый со своей квотой, default-deny NetworkPolicy и namespaced-Role для деплойщика. Дешевле отдельных кластеров. Переход на них потом — изменение конфига провайдера, не переархитектура.

**Алерты едут вместе с чартом** (PrometheusRule) и версионируются с кодом. Алерт, ссылающийся на метрику которую переименовали — тихий пробел. Когда они в одном PR, это видно сразу.

**Только иммутабельные теги** — `sha-<gitsha>`. `latest` отвергается при деплое и блокируется Kyverno. Откат воспроизводит ровно те байты, которые там были, а не то, куда тег указывает сегодня.

**Ручные деплои через GitHub Environments.** Гейт аппрува и ограниченные Kubernetes-креды живут на окружении. Dev-токен физически не дотянется до stage.

**Trivy пока не блокирующий.** Уязвимости видны во вкладке Security. Один флаг `exit-code` превратит это в жёсткий гейт.

См. `OPERATIONS.md` для процедур и `RUNBOOK.md` для реагирования на инциденты.

## Базовая безопасность

Нет секретов в git — см. `SECRETS.md`. Конфиг приложения нечувствительный, лежит в ConfigMap; настоящие секреты приходят из внешнего хранилища (SOPS / External Secrets). `.gitignore` блокирует tfstate, kubeconfig'и и `*.tfvars`.

Сеть — default-deny на уровне namespace. Чарт добавляет явные allow'ы: ingress-nginx к порту приложения, monitoring к `/metrics`.

CI работает как `ci-deployer` — namespaced Role, ограниченная ровно теми типами ресурсов которыми управляет чарт. Детали в `OPERATIONS.md`.
