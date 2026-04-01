terraform {
  # check blocks (networking input validation) require 1.5+
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local state (terraform.tfstate) in this directory is ephemeral in many AAP job pods.
  # Use a remote backend (S3 + DynamoDB, Terraform Cloud, etc.) for repeatable team workflows.
  backend "local" {}
}

provider "aws" {
  region = var.region

  # Authentication: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN (optional),
  # shared config/credentials files, IAM role, etc. Never set keys in .tf or tfvars.
}
