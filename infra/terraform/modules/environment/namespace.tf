locals {
  namespace = var.namespace != "" ? var.namespace : "${var.app_name}-${var.environment}"

  common_labels = {
    "app.kubernetes.io/part-of" = var.app_name
    "environment"               = var.environment
    "managed-by"                = "terraform"
  }
}

# metadata.name label is required by NetworkPolicies and ServiceMonitor selectors.
resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = local.namespace
    labels = merge(local.common_labels, {
      "kubernetes.io/metadata.name" = local.namespace
    })
  }
}
