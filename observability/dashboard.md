# orders-api dashboard

The importable Grafana JSON is at `observability/grafana-dashboard.json`. This file is the human-readable version of what's in it.

## Metrics on `/metrics`

| Metric | Type | Labels | Use |
|---|---|---|---|
| `http_requests_total` | counter | `method`, `path`, `status` | traffic, error ratio |
| `http_request_duration_seconds_bucket` | histogram | `method`, `path`, `le` | latency percentiles (p50/p95/p99) |
| `http_request_duration_seconds_sum` / `_count` | counter | `method`, `path` | average latency |
| `app_build_info` | gauge | `version` | which build is running |

Infrastructure signals come from kube-state-metrics and node exporter (kube-prometheus-stack): `kube_deployment_status_replicas_available`, `kube_pod_container_status_restarts_total`, `container_memory_working_set_bytes`, `up`.

## Panel layout

```
+----------------------------+----------------------------+
| Request rate (req/s)       | Error ratio (5xx %)        |
| sum(rate(requests_total))  | 5xx / total, threshold 5%  |
+----------------------------+----------------------------+
| Latency p50 / p95 / p99    | Ready vs desired replicas  |
| histogram_quantile(...)    | available vs spec replicas |
+----------------------------+----------------------------+
| Pod restarts (rate)        | CPU vs request / HPA level |
| restarts_total rate        | shows autoscaling working  |
+----------------------------+----------------------------+
```

## PromQL

Request rate
```
sum(rate(http_requests_total{namespace="orders-api-stage"}[5m]))
```

Error ratio
```
sum(rate(http_requests_total{namespace="orders-api-stage",status=~"5.."}[5m]))
/
sum(rate(http_requests_total{namespace="orders-api-stage"}[5m]))
```

p99 latency
```
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{namespace="orders-api-stage"}[5m])) by (le))
```

Restarts
```
sum(rate(kube_pod_container_status_restarts_total{namespace="orders-api-stage"}[15m]))
```
