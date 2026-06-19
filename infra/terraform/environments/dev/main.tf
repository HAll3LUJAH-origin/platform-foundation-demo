module "environment" {
  source      = "../../modules/environment"
  environment = "dev"
  app_name    = "orders-api"

  quota = {
    requests_cpu    = "1"
    requests_memory = "1Gi"
    limits_cpu      = "2"
    limits_memory   = "2Gi"
    max_pods        = "10"
  }
}

output "namespace" {
  value = module.environment.namespace
}
output "ci_deployer_token_secret" {
  value = module.environment.ci_deployer_token_secret
}
