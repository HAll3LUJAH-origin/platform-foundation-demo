# Operations — orders-api

Day-to-day: deploy, roll back, monitor.

---

## Deploy

### Via CI

Merge to `main`, and `ci.yaml` builds and pushes `ghcr.io/<org>/orders-api:sha-<gitsha>`. Then go to Actions → deploy → Run workflow, pick the environment and the image tag from that CI run.

Stage requires an approval gate. Once approved, the workflow runs `helm upgrade --install --rollback-on-failure`, waits for the rollout, and does a smoke check. If the upgrade fails for any reason, Helm rolls back automatically — you won't be left with a half-applied release.

### Locally

```bash
make deploy ENV=dev TAG=sha-local
# or directly:
helm upgrade --install orders-api helm/orders-api \
  --namespace orders-api-dev \
  --values helm/orders-api/values-dev.yaml \
  --set image.tag=sha-local --rollback-on-failure --timeout 5m
```

`image.tag` has no default. The chart fails fast if it's empty — every deploy has to be explicit.

---

## Rollback

Every `helm upgrade` creates a new revision. Rollback re-applies a previous one exactly as it was — same image, same values.

```bash
# check revision history
helm -n orders-api-stage history orders-api

# roll back one revision (the common case)
helm -n orders-api-stage rollback orders-api

# roll back to a specific revision
helm -n orders-api-stage rollback orders-api 7

# confirm
kubectl -n orders-api-stage rollout status deploy/orders-api --timeout=180s
```

Immutable tags mean revision N always pulls the exact image it ran before — no "latest moved under us" problem. `maxUnavailable: 0` means the rollout never drops below desired replica count mid-change.

`--rollback-on-failure` catches deploy-time failures automatically. Manual rollback is for when the deploy succeeded but the new version turned out to be broken.

Last resort if Helm state is wedged: `kubectl -n <ns> rollout undo deploy/orders-api`.

Check the dashboard after rollback. Error ratio and ready replicas should be back to baseline before you close the incident.

---

## Monitor

Import `observability/grafana-dashboard.json` into Grafana, or use `observability/dashboard.md` for the metric list and panel layout. The dashboard covers request rate, error ratio, latency percentiles, ready vs desired replicas, restarts, and CPU vs request.

Alerts are in the chart's PrometheusRule. Response steps are in `RUNBOOK.md`.

Quick CLI check:

```bash
kubectl -n <ns> get deploy,po,hpa
kubectl -n <ns> port-forward svc/orders-api 8080:80
curl localhost:8080/metrics
```

Which build is live: `app_build_info{namespace="<ns>"}` → `version` label.

---

## CI deploy credentials

The deploy identity is `ci-deployer` — a ServiceAccount with a namespaced Role, created by Terraform at `infra/terraform/modules/environment/rbac.tf`.

It's a `Role` + `RoleBinding` in one namespace, never a ClusterRole. A leaked dev token can't touch stage or any cluster-scoped objects.

The role covers only the resource types this chart manages: Deployments, ReplicaSets, Services, ConfigMaps, ServiceAccounts, HPAs, PDBs, NetworkPolicies, ServiceMonitors, PrometheusRules. Pods, logs, and events are read-only — enough to watch a rollout, not to mutate anything.

Helm stores release state as Secrets in the target namespace, which is the only reason the role can touch Secrets. It can't read them anywhere else.

Each environment gets its own token as a GitHub Environment secret. Dev credentials can't be used against stage.

The sandbox uses a long-lived token for convenience. In a real cluster, OIDC federation / IRSA / Workload Identity gets you short-lived auditable tokens with no static secret to rotate.

To wire CI to a cluster, set `KUBE_SERVER`, `KUBE_CA_DATA`, and `KUBE_DEPLOYER_TOKEN` (from the Terraform output `ci_deployer_token_secret`) as GitHub Environment secrets.
