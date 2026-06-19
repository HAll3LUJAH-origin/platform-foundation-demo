# Runbook — orders-api

On-call reference for alerts from `helm/orders-api/templates/prometheusrule.yaml`. Each alert's `runbook_url` points to the section below.

`NS` = `orders-api-dev` or `orders-api-stage`. In stage, high error rate and target-down are critical (page). Latency and replica shortfall warn everywhere.

First question, always: **did a deploy happen in the last 30 minutes?** If yes, roll back first and investigate after. It's almost always the deploy.

---

## High 5xx error rate

`OrdersApiHighErrorRate` fires when more than 5% of requests return 5xx for 5 consecutive minutes with real traffic.

Confirm the scope:

```bash
kubectl -n $NS get deploy,po
# error ratio right now — Prometheus or the "Error ratio" Grafana panel:
#   sum(rate(http_requests_total{namespace="$NS",status=~"5.."}[5m]))
#   / sum(rate(http_requests_total{namespace="$NS"}[5m]))
```

Check whether it lines up with a change:

```bash
kubectl -n $NS rollout history deploy/orders-api
helm -n $NS history orders-api
kubectl -n $NS get events --sort-by=.lastTimestamp | tail -20
```

The running build is in `app_build_info{namespace="$NS"}`. If the spike lines up with a version change, roll back and investigate later. Don't waste time diagnosing a bad deploy when you can just revert it.

Triage failing pods:

```bash
kubectl -n $NS get po -o wide
kubectl -n $NS logs deploy/orders-api --tail=100
kubectl -n $NS describe po <pod>     # OOMKilled? CrashLoopBackOff? probe failures?
kubectl -n $NS top po                # CPU/mem vs limits
```

What you're likely to find:

- **Bad release** — errors start exactly at deploy time. Logs show the new code path failing. Roll back.
- **OOMKilled** — describe shows OOMKilled, restart count climbing. Raise the memory limit or fix the leak.
- **Dependency down** — logs show timeouts, errors don't correlate with the deploy. Escalate to the dependency owner.
- **Overload** — CPU near limit, latency alert also firing, HPA already at max.

Mitigate:

```bash
# bad release
helm -n $NS rollback orders-api
kubectl -n $NS rollout status deploy/orders-api

# OOM / resource pressure — scale out short-term while a fix lands
kubectl -n $NS scale deploy/orders-api --replicas=N

# overload — check HPA, raise maxReplicas if it's pinned
kubectl -n $NS get hpa
```

For dependency outages, escalate to the owning team. Consider load shedding.

Recovery: error ratio under 5% and stable for 5 minutes — the alert resolves. Confirm with `kubectl -n $NS get po`, all Ready, restarts stable.

Short incident note: trigger, blast radius, root cause, fix, follow-ups. If it was a bad release, what test would have caught it?

---

## High latency

`OrdersApiHighLatencyP99` — p99 over 500ms for 10 minutes.

Service is up but slow:

```bash
kubectl -n $NS top po       # CPU saturation?
kubectl -n $NS get hpa      # scaled up? pinned at max?
```

CPU near limit with HPA at max → raise `maxReplicas` or the CPU limit. Latency without CPU pressure usually means a slow dependency or lock contention. Check logs, look at downstream latency, and check whether there's a correlated deploy:

```bash
helm -n $NS history orders-api
```

Roll back if it lines up. Otherwise scale out and fix the downstream.

---

## Target down

`OrdersApiTargetDown` — Prometheus can't scrape the service for 2 minutes. Process is probably crashing, OOMing, or unreachable.

```bash
kubectl -n $NS get po
kubectl -n $NS describe po <pod>      # last state, reason
kubectl -n $NS logs <pod> --previous  # crash logs from the prior container
```

CrashLoopBackOff after a deploy → roll back. All pods Pending → check nodes and quota: `kubectl -n $NS describe quota`, `kubectl get nodes`. Pods Running but not scraped → likely a ServiceMonitor label mismatch or NetworkPolicy blocking the monitoring namespace. Confirm the `monitoring` namespace label exists.

---

## Not enough ready replicas

`OrdersApiNotEnoughReadyReplicas` — available replicas below desired for 10 minutes. Capacity is degraded even if the surviving pods are serving fine.

```bash
kubectl -n $NS get deploy orders-api
kubectl -n $NS get po
kubectl -n $NS describe po <pod>
```

Pending / FailedScheduling → quota exhausted or no node capacity (`kubectl -n $NS describe quota`). Readiness failing → app not passing `/readyz`; check logs and readiness config in `values-<env>.yaml`. CrashLooping → see *Target down*.

---

## Escalation

1. On-call engineer (this runbook).
2. Service owner / platform channel.
3. For dependency outages, the team that owns the dependency.

Post in the incident channel on ack, on mitigation, and on close.
