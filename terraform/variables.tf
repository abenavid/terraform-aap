variable "region" {
  type        = string
  description = "AWS region for all resources."
  default     = "us-east-1"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type."
  default     = "t2.micro"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names and tags."
  default     = "tf-demo"
}

variable "web_demo_key_name" {
  type        = string
  default     = ""
  description = <<-EOT
    EC2 key pair name in AWS. If empty, Terraform generates a unique name (name_prefix-key-<suffix>)
    so re-applies after lost state are less likely to hit InvalidKeyPair.Duplicate. Set explicitly only if
    you need a stable name and manage state carefully.
  EOT
}

variable "web_demo_ssh_pubkey" {
  type        = string
  description = "SSH public key material for the EC2 key pair (OpenSSH format)."
}

variable "create_vpc" {
  type        = bool
  default     = false
  description = <<-EOT
    When true, Terraform creates a new VPC (and ignores existing ID variables if set).
    When false with both existing_vpc_id and existing_subnet_id set, those are reused.
    When false with both empty, Terraform auto-creates a VPC (same as a full create path).
  EOT
}

variable "existing_vpc_id" {
  type        = string
  default     = ""
  description = "Existing VPC ID for the security group. Use with existing_subnet_id, or leave empty for auto-create."
}

variable "existing_subnet_id" {
  type        = string
  default     = ""
  description = "Existing subnet ID for the instance. Use with existing_vpc_id, or leave empty for auto-create."
}

variable "vpc_cidr" {
  type        = string
  description = "VPC IPv4 CIDR (used only when a new VPC is created)."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Public subnet IPv4 CIDR (must sit inside vpc_cidr; used only when a new VPC is created)."
  default     = "10.0.1.0/24"
}
