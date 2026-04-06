# ============================================================
# variables.tf — All input variables
# ============================================================

# ---- Terraform Cloud ----
variable "tfc_organization" {
  description = "Terraform Cloud organization name"
  type        = string
}

variable "tfc_workspace" {
  description = "Terraform Cloud workspace name"
  type        = string
  default     = "ansible-lab"
}

# ---- AWS ----
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# ---- Project ----
variable "project_name" {
  description = "Prefix used for all resource names"
  type        = string
  default     = "ansible-lab"
}

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "ansible-lab"
    ManagedBy   = "terraform"
    Environment = "lab"
  }
}

# ---- Networking ----
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (master node)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet (worker nodes)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDRs allowed to SSH into the master. Restrict to your IP!"
  type        = list(string)
  default     = ["0.0.0.0/0"] # ⚠️  Remplace par ton IP: ["X.X.X.X/32"]
}

# ---- SSH Key ----
variable "key_name" {
  description = "Name of the AWS Key Pair (must already exist in AWS)"
  type        = string
  default     = "williamkey"
}

variable "william_public_key" {
  description = "Content of williamkey.pub — added to authorized_keys on all nodes"
  type        = string
  sensitive   = true
}

variable "william_private_key" {
  description = "Content of williamkey (private) — placed on master for Ansible SSH"
  type        = string
  sensitive   = true
}

# ---- User ----
variable "ansible_user" {
  description = "Linux username created on every machine"
  type        = string
  default     = "admin12"
}

# ---- EC2 ----
variable "master_instance_type" {
  description = "Instance type for the master node"
  type        = string
  default     = "t3.medium"
}

variable "node_instance_type" {
  description = "Instance type for worker nodes"
  type        = string
  default     = "t3.micro"
}
