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

output "inventory_snippet" {
  description = "Example inventory line for Ansible (set ansible_ssh_private_key_file to the matching private key)."
  value       = "${aws_instance.app.tags["Name"]} ansible_host=${aws_instance.app.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=PATH_TO_MATCHING_PRIVATE_KEY"
}
