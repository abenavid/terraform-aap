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
  description = "EC2 key pair name in AWS."
}

variable "web_demo_ssh_pubkey" {
  type        = string
  description = "SSH public key material for the EC2 key pair (OpenSSH format)."
}

variable "vpc_cidr" {
  type        = string
  description = "VPC IPv4 CIDR."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Public subnet IPv4 CIDR (must sit inside vpc_cidr)."
  default     = "10.0.1.0/24"
}
