# Platform Foundation — orders-api

Minimal platform foundation for `orders-api`. Runs locally in `kind`, ships to dev and stage, and has just enough observability and guardrails that you can deploy without holding your breath.

No cloud account needed. Swap the Terraform provider auth and backend and it runs on EKS/GKE/AKS.

---

## Running it locally

Prerequisites: `docker`, `kind`, `kubectl`, `helm`, `terraform`, `make`.

```bash
# 1. Cluster + local registry
make cluster

# 2. Monitoring stack (Prometheus Operator + Prometheus + Grafana)
make monitoring

# 3. Infra for dev: namespace, quota, default-deny netpol, CI deploy RBAC
make infra ENV=dev

# 4. Build the image into the local registry
make build TAG=sha-local

# 5. Deploy to dev
make deploy ENV=dev TAG=sha-local

# Probe it
kubectl -n orders-api-dev port-forward svc/orders-api 8080:80
curl localhost:8080/healthz && curl localhost:8080/metrics
```

For stage: steps 3–5 with `ENV=stage`, or `make all ENV=stage` in one go.

Trigger alerts on demand (dev has debug endpoints on):

```bash
make drill ENV=dev      # 60% error rate + 700ms latency, continuous load
```

Roll back:

```bash
make rollback ENV=dev
```

---

## What's here

```
app/                      Minimal Go service (stdlib only): health probes + Prometheus metrics
infra/terraform/          IaC — per-env roots for clean state separation
  modules/environment/    namespace, quota, limitrange, default-deny netpol, least-priv RBAC
  environments/dev|stage/ thin roots with separate state and sizing
helm/orders-api/          Chart: Deployment, Service, HPA, PDB, probes, ServiceMonitor, alerts, NetworkPolicy
  values.yaml             defaults
  values-dev.yaml         dev overrides (cheap, debug on)
  values-stage.yaml       stage overrides (HA, debug off)
.github/workflows/        ci.yaml (lint/test/build/scan) + deploy.yaml (manual, env-gated)
observability/            dashboard sketch, metric list, importable Grafana JSON
policy/                   Kyverno admission policies
scripts/                  kind + local registry bootstrap
RUNBOOK.md                incident response (primary: high 5xx)
OPERATIONS.md             deploy / rollback / monitor procedures
RELEASE_CHECKLIST.md      pre-release gate
PREVIEW_ENVIRONMENTS.md   per-PR preview env strategy (design note, not yet built)
SECRETS.md                no-secrets-in-git, network policy, webhook allowlist
```

## The service

`orders-api` is a tiny stand-in workload. Six endpoints:

- `GET /` — primary route, recorded in metrics
- `GET /healthz` — liveness (process up)
- `GET /readyz` — readiness (warmed up; fails during shutdown drain)
- `GET /metrics` — Prometheus exposition
- `GET /debug/fail?rate=&latency_ms=` — fault injection, dev only, for alert drills

Zero external dependencies. Hermetic build. Ships in `distroless/static:nonroot` — no shell, uid 65532, read-only root filesystem.

---

## Design decisions

**Per-env Terraform roots, not workspaces.** Separate state files and `*.tfvars` make dev/stage differences explicit and reviewable. Workspaces share state, which is fine until someone applies to the wrong env — separate roots removes that failure mode entirely.

**Namespace as the isolation boundary.** One namespace per env, each with its own quota, default-deny NetworkPolicy, and a namespaced deployer Role. Cheaper than separate clusters and enough for this scale. Moving to separate clusters later is a provider config change.

**Alerts ship with the chart** (PrometheusRule), so they version alongside the code. An alert referencing a metric that got renamed is a silent gap; keeping them together makes that visible in the same PR.

**Immutable image tags only** — `sha-<gitsha>` everywhere. `latest` is refused at deploy time and blocked by Kyverno. Rollback re-runs the exact bytes from that revision, not whatever the tag points at today.

**Manual deploys via GitHub Environments.** The approval gate and scoped Kubernetes credentials live on the environment. A dev token literally cannot reach stage.

**Trivy is non-blocking for now.** Vulns surface in the Security tab; one `exit-code` change makes it a hard gate when needed.

See `OPERATIONS.md` for procedures, `RUNBOOK.md` for incident response, and inline comments in each file for smaller decisions.

## Security baseline

No secrets in git — see `SECRETS.md`. App config is a non-sensitive ConfigMap; real secrets come from an external store (SOPS / External Secrets) and never get committed. `.gitignore` covers tfstate, kubeconfigs, and `*.tfvars`.

Network is default-deny at the namespace level. The chart adds explicit allows: ingress-nginx reaches the app port, monitoring reaches `/metrics`, nothing else gets in.

CI runs as `ci-deployer` — a namespaced Role limited to exactly the resource types this chart manages. Details in `OPERATIONS.md`.
