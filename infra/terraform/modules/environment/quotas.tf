resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "compute-quota"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.common_labels
  }
  spec {
    hard = {
      "requests.cpu"    = var.quota.requests_cpu
      "requests.memory" = var.quota.requests_memory
      "limits.cpu"      = var.quota.limits_cpu
      "limits.memory"   = var.quota.limits_memory
      "pods"            = var.quota.max_pods
    }
  }
}

# LimitRange so pods without explicit requests/limits still land under the quota.
resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "default-limits"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.common_labels
  }
  spec {
    limit {
      type = "Container"
      default = {
        cpu    = var.default_container_limits.cpu
        memory = var.default_container_limits.memory
      }
      default_request = {
        cpu    = "50m"
        memory = "64Mi"
      }
    }
  }
}
