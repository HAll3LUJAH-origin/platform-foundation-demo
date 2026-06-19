variable "environment" {
  type        = string
  description = "Logical environment name (dev|stage)."
  validation {
    condition     = contains(["dev", "stage"], var.environment)
    error_message = "environment must be dev or stage."
  }
}

variable "app_name" {
  type        = string
  description = "Application / namespace base name."
  default     = "orders-api"
}

variable "namespace" {
  type        = string
  description = "Namespace to create. Defaults to <app>-<env>."
  default     = ""
}

variable "quota" {
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    max_pods        = string
  })
  description = "ResourceQuota for the namespace. dev should be smaller than stage."
}

variable "default_container_limits" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "LimitRange default per-container limits."
  default = {
    cpu    = "250m"
    memory = "128Mi"
  }
}

variable "ingress_namespace" {
  type        = string
  description = "Namespace of the ingress controller allowed to reach workloads."
  default     = "ingress-nginx"
}

variable "monitoring_namespace" {
  type        = string
  description = "Namespace of Prometheus, allowed to scrape metrics."
  default     = "monitoring"
}

variable "ci_deployer_namespace" {
  type        = string
  description = "Namespace where the CI deployer ServiceAccount token lives."
  default     = ""
}
