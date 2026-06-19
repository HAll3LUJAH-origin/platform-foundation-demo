# Release checklist — orders-api

Not a ceremony. A short gate to catch the things that actually cause bad deploys: unpinned image, untested rollback, alert with no owner. Copy into the PR or release ticket and check off items. Cross out anything that doesn't apply and say why.

Promotion order is always **dev → stage**. Nothing skips dev.

---

## 1. Before merge (in the PR)

- [ ] CI green — `lint-test` passed (gofmt, vet, `go test -race`, helm lint/template, terraform validate, hadolint, trivy config).
- [ ] Image built and pushed by CI with an immutable `sha-<gitsha>` tag. Never `latest`.
- [ ] Chart changes render cleanly for both envs (`helm template -f values-dev.yaml` and `-f values-stage.yaml`).
- [ ] If requests/limits, replica count, or HPA bounds changed — in the per-env values file, not in `values.yaml`.
- [ ] No secrets, tokens, kubeconfigs, or `*.tfvars` in the diff (gitleaks/pre-commit clean).
- [ ] Reviewer approved.

## 2. Deploy to dev

- [ ] Ran `deploy` workflow → env `dev`, with the exact `image_tag` from CI.
- [ ] `helm upgrade --install --rollback-on-failure` succeeded; rollout finished, no stuck pods.
- [ ] `/healthz` and `/readyz` return 200; smoke check on `/` passes.
- [ ] Dashboards show traffic, error ratio at baseline, p99 normal.
- [ ] No new alerts firing for `namespace=orders-api-dev`.

## 3. Validate in dev

- [ ] The actual change works — feature does what it should, or fix is confirmed.
- [ ] If the failure path is affected: ran `make drill` and confirmed the alert fires and the runbook steps are still accurate.
- [ ] Migration / config compatibility checked if applicable — forward-compatible means old and new pods can coexist during rollout, `maxUnavailable: 0` rolls additively.

## 4. Promote to stage

- [ ] Same `image_tag` that was validated in dev. Don't rebuild for stage.
- [ ] Ran `deploy` workflow → env `stage`; approval gate cleared by an authorized approver.
- [ ] Rollout finished; PDB respected (didn't drop below `minAvailable: 2`).
- [ ] `/readyz` 200 on all replicas; error ratio and p99 at baseline after deploy.
- [ ] No new alerts for `namespace=orders-api-stage` after a 10-minute soak.

## 5. Rollback readiness (check this before you need it)

- [ ] Previous good `image_tag` recorded in the release ticket.
- [ ] `helm history orders-api -n orders-api-stage` shows a known-good revision.
- [ ] Rollback command is one line and has been run at least once: `helm rollback orders-api <REV> -n orders-api-stage --wait` (see OPERATIONS.md → Rollback).
- [ ] Rollback is deterministic — immutable tags mean it always returns to the exact image, not whatever `latest` is today.

## 6. After release

- [ ] Release ticket updated: deploy tag, dev/stage timestamps, approver, previous good tag.
- [ ] Every new alert from this release has an owner and a runbook section. No orphaned alerts.
- [ ] If the release revealed a gap (flaky probe, missed check) — follow-up filed.

---

### Hotfix

For an urgent fix to stage, compress the dev step, don't skip it: deploy the fix to dev, run a smoke check and the relevant drill, then promote the same tag. Section 5 (rollback readiness) is never skipped — a hotfix is exactly when you need a rehearsed path back.
