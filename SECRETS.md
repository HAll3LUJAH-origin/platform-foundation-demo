# Secrets & security baseline

## No secrets in git

App runtime config is non-sensitive and lives in a ConfigMap — `PORT`, `WARMUP`, `DEBUG_ENDPOINTS`, `ENVIRONMENT`. Nothing sensitive is committed.

`.gitignore` covers Terraform state (`*.tfstate*`, which can contain the deployer token), `*.tfvars`, kubeconfigs, and `.env*`.

Real secrets come from outside the repo. For CI: GitHub Environment secrets scoped per env — `KUBE_SERVER`, `KUBE_CA_DATA`, `KUBE_DEPLOYER_TOKEN`. Dev secrets are invisible to stage jobs.

For cluster app secrets, use SOPS-encrypted files (commit the ciphertext, decrypt in CI with a KMS key) or External Secrets Operator pulling from AWS Secrets Manager, Vault, or GCP Secret Manager. The chart consumes secrets via `envFrom`/`secretRef` — it never templates secret values inline.

Add `gitleaks` or `trufflehog` as a pre-commit hook and a CI secret-scan step. Catching an accidental commit locally is much cheaper than rotating a leaked token.

## Network policy

Two layers. Default-deny first.

The namespace baseline (Terraform) starts with a `default-deny-all` that blocks all ingress and egress, then opens the minimum: DNS egress to `kube-system` on UDP/TCP 53, and same-namespace pod-to-pod ingress.

The Helm chart adds an app-scoped layer on top: the app port accepts ingress only from `ingress-nginx`, and `/metrics` only from the `monitoring` namespace.

That's it. A pod can resolve DNS and talk within its namespace. The ingress controller can reach the app. Prometheus can scrape it. Nothing else gets in. Adding a new dependency means adding one explicit allow.

## Webhook allowlist

For inbound webhooks (payment provider, VCS, anything calling back):

1. **Verify the signature.** Validate the provider's HMAC over the raw body using a secret from the secret store. Check the timestamp to reject replays. Requests that fail verification get dropped before any business logic runs.
2. **Source-IP allowlist at the edge.** Restrict the webhook path to the provider's published egress CIDRs via ingress annotations (`nginx.ingress.kubernetes.io/whitelist-source-range`) or the cloud LB/WAF. Keep the CIDR list in config so changes go through PR review.
3. **NetworkPolicy on the receiver.** Webhook-handling pods accept ingress only from the ingress controller.

The IP allowlist reduces attack surface but CIDRs can drift or be spoofed — the signature check is the real gate. The allowlist is defense-in-depth.

## Workload hardening

Set in `values.yaml`, not relaxed per environment, enforced by Kyverno: `runAsNonRoot`, uid 65532, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, all capabilities dropped, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`, distroless image with no shell.
