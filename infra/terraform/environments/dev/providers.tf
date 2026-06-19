# Local sandbox points at the kind cluster context. In a real setup these
# would target the dev cluster (EKS/GKE) via the appropriate auth.
provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.kube_context
}

variable "kubeconfig" {
  type    = string
  default = "~/.kube/config"
}

variable "kube_context" {
  type    = string
  default = "kind-platform-foundation"
}
