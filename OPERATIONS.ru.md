# Operations — orders-api

Повседневные процедуры: деплой, откат, мониторинг.

---

## Деплой

### Через CI

Мерджишь в `main` — `ci.yaml` собирает и пушит `ghcr.io/<org>/orders-api:sha-<gitsha>`. Потом Actions → deploy → Run workflow, выбираешь окружение и тег образа из этого запуска CI.

Для stage нужен аппрув. После него workflow запускает `helm upgrade --install --rollback-on-failure`, ждёт выкатки и делает smoke-проверку. Если upgrade падает — Helm откатывается автоматически, наполовину применённого релиза не остаётся.

### Локально

```bash
make deploy ENV=dev TAG=sha-local
# или напрямую:
helm upgrade --install orders-api helm/orders-api \
  --namespace orders-api-dev \
  --values helm/orders-api/values-dev.yaml \
  --set image.tag=sha-local --rollback-on-failure --timeout 5m
```

У `image.tag` нет значения по умолчанию. Чарт падает сразу если он пуст — каждый деплой должен быть явным.

---

## Откат

Каждый `helm upgrade` создаёт новую ревизию. Откат применяет предыдущую точно как она была — тот же образ, те же values.

```bash
# история ревизий
helm -n orders-api-stage history orders-api

# откат на одну ревизию (самый частый сценарий)
helm -n orders-api-stage rollback orders-api

# откат к конкретной ревизии
helm -n orders-api-stage rollback orders-api 7

# подтвердить
kubectl -n orders-api-stage rollout status deploy/orders-api --timeout=180s
```

Иммутабельные теги означают, что ревизия N всегда тянет ровно тот образ, что работал раньше — нет проблемы «latest уехал». `maxUnavailable: 0` гарантирует, что выкатка не опускается ниже желаемого числа реплик в процессе.

`--rollback-on-failure` ловит провалы деплоя автоматически. Ручной откат — для случая когда деплой прошёл, но новая версия оказалась сломанной.

Крайняя мера если завис сам Helm state: `kubectl -n <ns> rollout undo deploy/orders-api`.

После отката смотреть дашборд. Доля ошибок и готовые реплики должны вернуться к baseline до того, как закрывать инцидент.

---

## Мониторинг

Импортировать `observability/grafana-dashboard.json` в Grafana, или пользоваться `observability/dashboard.md` для списка метрик и раскладки панелей. Дашборд покрывает rate запросов, долю ошибок, перцентили задержки, ready vs desired реплики, рестарты и CPU vs request.

Алерты в PrometheusRule чарта. Шаги реагирования — в `RUNBOOK.md`.

Быстрая проверка из CLI:

```bash
kubectl -n <ns> get deploy,po,hpa
kubectl -n <ns> port-forward svc/orders-api 8080:80
curl localhost:8080/metrics
```

Какая сборка запущена: `app_build_info{namespace="<ns>"}` → метка `version`.

---

## Креды деплоя из CI

Деплойщик — ServiceAccount `ci-deployer` с namespaced Role, созданный Terraform в `infra/terraform/modules/environment/rbac.tf`.

`Role` + `RoleBinding` в одном namespace, никогда не ClusterRole. Утёкший dev-токен не тронет stage и никакие объекты уровня кластера.

Role покрывает только те типы ресурсов, которыми управляет чарт: Deployments, ReplicaSets, Services, ConfigMaps, ServiceAccounts, HPA, PDB, NetworkPolicies, ServiceMonitors, PrometheusRules. Pods, логи и events — только чтение.

Доступ к Secrets нужен потому что Helm хранит state релиза как Secrets в целевом namespace. За пределами namespace он читать их не может.

У каждого окружения свой токен как GitHub Environment secret. Dev-креды не пересекают границу env.

Песочница использует долгоживущий токен для удобства. В реальном кластере — OIDC-федерация / IRSA / Workload Identity: короткоживущие аудируемые токены без статического секрета для ротации.

Чтобы подключить CI к кластеру, задать `KUBE_SERVER`, `KUBE_CA_DATA` и `KUBE_DEPLOYER_TOKEN` (из вывода Terraform `ci_deployer_token_secret`) как GitHub Environment secrets.
