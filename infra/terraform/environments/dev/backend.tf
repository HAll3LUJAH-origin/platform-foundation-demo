terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.27.0"
    }
  }
  # Local state for the sandbox. In real environments use isolated remote
  # state per env, e.g.:
  #   backend "s3" {
  #     bucket = "acme-tfstate"
  #     key    = "orders-api/dev/terraform.tfstate"
  #     region = "eu-central-1"
  #   }
  backend "local" {
    path = "terraform.tfstate"
  }
}
