terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state file (terraform.tfstate) lives in this directory. Use a remote backend
  # in your own wrapper if needed; credentials always come from the environment.
  backend "local" {}
}

provider "aws" {
  region = var.region

  # Authentication: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN (optional),
  # or shared config/credentials files, IAM role, etc. Never set keys in .tf or tfvars.
}
