module "environment" {
  source      = "../../modules/environment"
  environment = "stage"
  app_name    = "orders-api"

  # Stage gets a larger budget than dev to allow HA + autoscaling headroom.
  quota = {
    requests_cpu    = "3"
    requests_memory = "3Gi"
    limits_cpu      = "6"
    limits_memory   = "6Gi"
    max_pods        = "30"
  }
}

output "namespace" {
  value = module.environment.namespace
}
output "ci_deployer_token_secret" {
  value = module.environment.ci_deployer_token_secret
}
