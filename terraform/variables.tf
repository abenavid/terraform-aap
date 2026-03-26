variable "tf_state_bucket_name" {
  type        = string
  description = "Prefix for the state bucket; a random suffix is appended so the full name is globally unique (avoids S3 409 conflicts)."
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Region for the default AWS provider (EC2, demo VPC, and related resources)."
}

variable "s3_state_region" {
  type        = string
  description = "Region where the state S3 bucket is created."
}
