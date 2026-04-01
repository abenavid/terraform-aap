output "public_ips" {
  description = "Public IPv4 addresses of EC2 instances."
  value       = [aws_instance.app.public_ip]
}

output "private_ips" {
  description = "Private IPv4 addresses of EC2 instances."
  value       = [aws_instance.app.private_ip]
}

output "instance_ids" {
  description = "EC2 instance IDs."
  value       = [aws_instance.app.id]
}

output "instance_names" {
  description = "EC2 Name tag values."
  value       = [aws_instance.app.tags["Name"]]
}

output "vpc_id" {
  description = "VPC used for the instance and security group (created or existing)."
  value       = local.vpc_id
}

output "subnet_id" {
  description = "Subnet used for the instance (created or existing)."
  value       = local.public_subnet_id
}
