output "namespace" {
  description = "Created namespace name."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "ci_deployer_service_account" {
  description = "Name of the least-privilege CI deployer ServiceAccount."
  value       = kubernetes_service_account_v1.ci_deployer.metadata[0].name
}

output "ci_deployer_token_secret" {
  description = "Secret holding the CI deployer token (consume in CI; do not commit)."
  value       = kubernetes_secret_v1.ci_deployer_token.metadata[0].name
}
