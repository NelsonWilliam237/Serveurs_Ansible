# ============================================================
# outputs.tf — Useful values after apply
# ============================================================

output "master_public_ip" {
  description = "Public IP of the Ansible master (use this to SSH in)"
  value       = aws_eip.master.public_ip
}

output "master_private_ip" {
  description = "Private IP of the Ansible master"
  value       = aws_instance.master.private_ip
}

output "nodes_private_ips" {
  description = "Private IPs of all worker nodes"
  value = {
    for idx, node in aws_instance.nodes :
    "node${idx + 1}" => node.private_ip
  }
}

output "ssh_command_master" {
  description = "Ready-to-use SSH command to connect to the master"
  value       = "ssh -i ~/.ssh/williamkey ${var.ansible_user}@${aws_eip.master.public_ip}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.ansible_lab.id
}

output "ansible_inventory_path" {
  description = "Path to inventory on master"
  value       = "/etc/ansible/hosts"
}
