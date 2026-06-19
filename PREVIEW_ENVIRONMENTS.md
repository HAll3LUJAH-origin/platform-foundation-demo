# Preview environments

> Status: design note, not built yet. This is how I'd add per-PR preview environments on top of what's already here, what it costs, and why it's not worth building right now. For one service and a small team, a shared `dev` namespace plus `make drill` covers most of the value. Previews start paying off when multiple engineers are shipping to the same service simultaneously and stepping on each other in `dev`.

## The idea

Every open PR gets a short-lived isolated deployment. Reviewers click a real running instance instead of imagining the diff. It tears down when the PR closes.

The chart doesn't need new templates for this — previews are just another set of Helm values pointed at a per-PR namespace.

## How it fits onto what's already here

The chart is already parameterised enough without changes:

- **Namespace per PR** — `orders-api-pr-<number>`. Created by the preview job, labelled the same way the Terraform module labels dev/stage, so existing NetworkPolicy and Kyverno `orders-api-*` selectors apply unchanged.
- **Release name per PR** — `helm upgrade --install orders-api-pr-<number>`.
- **Image** — the immutable `sha-<gitsha>` already built by CI. No special build; previews reuse the same artifact as promotion.
- **Values** — start from `values-dev.yaml` (1 replica, cheap resources, `debugEndpoints: true`, HPA + PDB off) with a small overlay:
  - `ingress.host: pr-<number>.preview.example.com`
  - tighter resource ceilings
  - `autoscaling.enabled: false`, `pdb.enabled: false`

## Lifecycle

```
PR opened / pushed   ->  build sha tag (existing CI)  ->  helm upgrade --install
                         into orders-api-pr-<n>  ->  comment URL on the PR
PR closed / merged   ->  helm uninstall + delete namespace
Nightly sweep        ->  GC any preview namespace whose PR is no longer open
                         (catches anything leaked by a failed cleanup job)
```

The nightly sweep is not optional. Orphaned namespaces quietly burning quota is the most common way preview setups rot. Reconcile against the open PR list and delete anything stale.

## Cost and isolation

**Cost.** Each preview is real CPU and memory. Keep it in check: 1 replica, low requests, hard ResourceQuota on the preview namespace, and a TTL so nothing outlives its PR. On kind this is nearly free. On a real cluster it's the main reason to keep previews small and garbage-collect aggressively.

**Isolation.** Namespace-level only, which is fine for a stateless service. The moment orders-api needs a database, "preview" also means provisioning throwaway storage or seeding a shared store with per-PR schema. That's where the real complexity lives — not the compute side. It's also the real reason this is deferred.

**Secrets.** Previews must use non-production credentials only, wired from the same External Secrets / SOPS path as dev. Never stage credentials.

**DNS/ingress.** A wildcard `*.preview.example.com` pointed at the ingress controller keeps per-PR hostnames zero-touch.

## Why it's deferred

One service, small team — contention in shared `dev` is low. The payoff is limited right now.

No datastore yet. The hard part of preview environments (ephemeral data) doesn't exist yet. Building the scaffolding before the problem arrives is just churn.

`make drill` already lets a reviewer exercise failure modes locally, which covers most of what previews would be used for at this stage.

When the team grows or a second service lands, this is a half-day addition: a `preview.yaml` values overlay and one GitHub Actions job on `pull_request` `opened/synchronize/closed`, reusing the deploy plumbing that's already here.
