# Дашборд orders-api

Готовый к импорту Grafana JSON лежит в `observability/grafana-dashboard.json`. Этот файл — человекочитаемая версия того, что в нём.

## Метрики на `/metrics`

| Метрика | Тип | Метки | Назначение |
|---|---|---|---|
| `http_requests_total` | counter | `method`, `path`, `status` | трафик, доля ошибок |
| `http_request_duration_seconds_bucket` | histogram | `method`, `path`, `le` | перцентили задержки (p50/p95/p99) |
| `http_request_duration_seconds_sum` / `_count` | counter | `method`, `path` | средняя задержка |
| `app_build_info` | gauge | `version` | какая сборка запущена |

Инфра-сигналы из kube-state-metrics и node exporter (kube-prometheus-stack): `kube_deployment_status_replicas_available`, `kube_pod_container_status_restarts_total`, `container_memory_working_set_bytes`, `up`.

## Раскладка панелей

```
+----------------------------+----------------------------+
| Rate запросов (req/s)      | Доля ошибок (5xx %)        |
| sum(rate(requests_total))  | 5xx / total, порог 5%      |
+----------------------------+----------------------------+
| Задержка p50 / p95 / p99   | Ready vs desired реплики   |
| histogram_quantile(...)    | available vs spec реплик   |
+----------------------------+----------------------------+
| Рестарты подов (rate)      | CPU vs request / уровень HPA|
| rate restarts_total        | показывает работу autoscale|
+----------------------------+----------------------------+
```

## PromQL

Rate запросов
```
sum(rate(http_requests_total{namespace="orders-api-stage"}[5m]))
```

Доля ошибок
```
sum(rate(http_requests_total{namespace="orders-api-stage",status=~"5.."}[5m]))
/
sum(rate(http_requests_total{namespace="orders-api-stage"}[5m]))
```

Задержка p99
```
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{namespace="orders-api-stage"}[5m])) by (le))
```

Рестарты
```
sum(rate(kube_pod_container_status_restarts_total{namespace="orders-api-stage"}[15m]))
```
