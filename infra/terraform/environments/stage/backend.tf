terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.27.0"
    }
  }
  # Separate state file from dev — environments never share state.
  #   backend "s3" {
  #     bucket = "acme-tfstate"
  #     key    = "orders-api/stage/terraform.tfstate"
  #     region = "eu-central-1"
  #   }
  backend "local" {
    path = "terraform.tfstate"
  }
}
