# ============================================================
# main.tf — Ansible Lab Infrastructure on AWS
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Terraform Cloud backend
  cloud {
    organization = var.tfc_organization

    workspaces {
      name = var.tfc_workspace
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================
# DATA SOURCES
# ============================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_key_pair" "williamkey" {
  key_name = var.key_name
}

# ============================================================
# VPC & NETWORKING
# ============================================================

resource "aws_vpc" "ansible_lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet Gateway (for public subnet)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ansible_lab.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

# Public Subnet (Master)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.ansible_lab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-subnet-public"
  })
}

# Private Subnet (Nodes)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.ansible_lab.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-subnet-private"
  })
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-eip"
  })
}

# NAT Gateway (allows private nodes to reach internet for updates)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-gw"
  })

  depends_on = [aws_internet_gateway.igw]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.ansible_lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-public"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.ansible_lab.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-private"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ============================================================
# SECURITY GROUPS
# ============================================================

# Master Security Group — SSH from internet + all traffic from private subnet
resource "aws_security_group" "master" {
  name        = "${var.project_name}-sg-master"
  description = "Ansible master node - SSH public access"
  vpc_id      = aws_vpc.ansible_lab.id

  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "All traffic from private subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-sg-master"
  })
}

# Nodes Security Group — SSH and all traffic from master only
resource "aws_security_group" "nodes" {
  name        = "${var.project_name}-sg-nodes"
  description = "Ansible nodes - accessible from master only"
  vpc_id      = aws_vpc.ansible_lab.id

  ingress {
    description     = "SSH from master"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.master.id]
  }

  ingress {
    description = "All traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-sg-nodes"
  })
}

# ============================================================
# ELASTIC IP for MASTER
# ============================================================

resource "aws_eip" "master" {
  domain   = "vpc"
  instance = aws_instance.master.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-master-eip"
  })

  depends_on = [aws_internet_gateway.igw]
}

# ============================================================
# USER DATA SCRIPTS
# ============================================================

locals {
  # Common user-data for ALL nodes (master + workers)
  common_userdata = <<-EOF
    #!/bin/bash
    set -e

    # ------- Create shared user -------
    USERNAME="${var.ansible_user}"
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME
    chmod 440 /etc/sudoers.d/$USERNAME

    # ------- SSH key setup -------
    mkdir -p /home/$USERNAME/.ssh
    chmod 700 /home/$USERNAME/.ssh
    echo "${var.william_public_key}" >> /home/$USERNAME/.ssh/authorized_keys
    chmod 600 /home/$USERNAME/.ssh/authorized_keys
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

    # ------- Basic packages -------
    apt-get update -y
    apt-get install -y python3 python3-pip curl wget git
  EOF

  # Extra user-data for MASTER only — installs Ansible
  master_userdata = <<-EOF
    #!/bin/bash
    set -e

    # ------- Create shared user -------
    USERNAME="${var.ansible_user}"
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME
    chmod 440 /etc/sudoers.d/$USERNAME

    # ------- SSH key setup (public key for inbound connections) -------
    mkdir -p /home/$USERNAME/.ssh
    chmod 700 /home/$USERNAME/.ssh
    echo "${var.william_public_key}" >> /home/$USERNAME/.ssh/authorized_keys
    chmod 600 /home/$USERNAME/.ssh/authorized_keys

    # ------- Private key for Ansible to connect to nodes -------
    cat <<'PRIVKEY' > /home/$USERNAME/.ssh/williamkey
    ${var.william_private_key}
    PRIVKEY
    chmod 600 /home/$USERNAME/.ssh/williamkey
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

    # ------- SSH client config (use williamkey for all hosts) -------
    cat <<'SSHCFG' > /home/$USERNAME/.ssh/config
    Host *
        IdentityFile ~/.ssh/williamkey
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
    SSHCFG
    chmod 600 /home/$USERNAME/.ssh/config
    chown $USERNAME:$USERNAME /home/$USERNAME/.ssh/config

    # ------- Basic packages -------
    apt-get update -y
    apt-get install -y python3 python3-pip curl wget git software-properties-common

    # ------- Install Ansible -------
    add-apt-repository --yes --update ppa:ansible/ansible
    apt-get install -y ansible

    # ------- Ansible inventory -------
    mkdir -p /etc/ansible
    cat <<'INV' > /etc/ansible/hosts
    [master]
    master ansible_connection=local

    [nodes]
    ${var.project_name}-node1 ansible_host=${cidrhost(var.private_subnet_cidr, 11)}
    ${var.project_name}-node2 ansible_host=${cidrhost(var.private_subnet_cidr, 12)}
    ${var.project_name}-node3 ansible_host=${cidrhost(var.private_subnet_cidr, 13)}
    ${var.project_name}-node4 ansible_host=${cidrhost(var.private_subnet_cidr, 14)}

    [all:vars]
    ansible_user=${var.ansible_user}
    ansible_ssh_private_key_file=/home/${var.ansible_user}/.ssh/williamkey
    ansible_python_interpreter=/usr/bin/python3
    INV

    # ------- Ansible config -------
    cat <<'ACFG' > /etc/ansible/ansible.cfg
    [defaults]
    inventory          = /etc/ansible/hosts
    remote_user        = ${var.ansible_user}
    private_key_file   = /home/${var.ansible_user}/.ssh/williamkey
    host_key_checking  = False
    retry_files_enabled = False

    [privilege_escalation]
    become       = True
    become_method = sudo
    become_user  = root
    ACFG

    chown -R $USERNAME:$USERNAME /etc/ansible

    echo "✅ Ansible master setup complete" >> /var/log/ansible-setup.log
  EOF
}

# ============================================================
# EC2 INSTANCES
# ============================================================

# MASTER NODE
resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.master.id]
  key_name               = data.aws_key_pair.williamkey.key_name

  user_data = local.master_userdata

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-master"
    Role = "ansible-master"
  })
}

# WORKER NODES (node1 to node4)
resource "aws_instance" "nodes" {
  count = 4

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.node_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.nodes.id]
  key_name               = data.aws_key_pair.williamkey.key_name

  private_ip = cidrhost(var.private_subnet_cidr, 11 + count.index)
  user_data  = local.common_userdata

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 15
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-node${count.index + 1}"
    Role = "ansible-node"
  })
}
