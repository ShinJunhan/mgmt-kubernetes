terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.17"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# --- Providers ----------------------------------------------------------------
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailnet_name
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# --- Variables ----------------------------------------------------------------
variable "aws_region" { default = "ap-northeast-2" }
variable "aws_profile" { default = null }
variable "cidr_block" { default = "10.20.0.0/16" }
variable "public_subnet_cidr" { default = "10.20.1.0/24" }
variable "private_subnet_cidr" { default = "10.20.2.0/24" }
variable "ssh_key_name" { default = "k8s-lab-key" }
variable "private_key_filename" { default = "k8s-lab-key.pem" }
variable "master_instance_type" { default = "t3.medium" }
variable "worker_instance_type" { default = "t3.medium" }
variable "worker_count" { default = 2 }
variable "ansible_playbook_path" { default = "site.yml" }
variable "ansible_inventory_path" { default = "inventory.yml" }
variable "ansible_cfg_path" { default = "ansible.cfg" }
variable "ansible_ssh_user" { default = "ubuntu" }

variable "tailnet_name" { type = string }
variable "tailscale_api_key" { 
  type      = string 
  sensitive = true 
}

# Cloudflare Variables
variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}
variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID (도메인의 고유 ID)"
  type        = string
}
variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}
variable "domain_name" {
  description = "연결할 외부 도메인 (예: yourdomain.com)"
  type        = string
}

# --- Tailscale Auth Key -------------------------------------------------------
resource "tailscale_tailnet_key" "k8s_join_key" {
  reusable      = true
  ephemeral     = true
  preauthorized = true
  expiry        = 3600
}

# --- SSH Key ------------------------------------------------------------------
resource "tls_private_key" "k8s" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k8s" {
  key_name   = var.ssh_key_name
  public_key = tls_private_key.k8s.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  filename        = "${path.module}/${var.private_key_filename}"
  content         = tls_private_key.k8s.private_key_pem
  file_permission = "0600"
}

# --- VPC & Subnets ------------------------------------------------------------
resource "aws_vpc" "k8s" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "k8s-lab-vpc" }
}

resource "aws_internet_gateway" "k8s" {
  vpc_id = aws_vpc.k8s.id
  tags   = { Name = "k8s-lab-igw" }
}

data "aws_availability_zones" "available" { 
  state = "available" 
}

# Public Subnet (NAT 위치)
resource "aws_subnet" "k8s_public" {
  vpc_id                  = aws_vpc.k8s.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "k8s-lab-public-subnet" }
}

# Private Subnet (K8s 위치)
resource "aws_subnet" "k8s_private" {
  vpc_id                  = aws_vpc.k8s.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
  tags = { Name = "k8s-lab-private-subnet" }
}

# --- NAT Instance (Public) ----------------------------------------------------
resource "aws_security_group" "nat_sg" {
  name   = "k8s-nat-sg"
  vpc_id = aws_vpc.k8s.id
  
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "latest_al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "nat_ec2" {
  ami                         = data.aws_ami.latest_al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.k8s_public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.nat_sg.id]
  key_name                    = aws_key_pair.k8s.key_name
  source_dest_check           = false

  user_data = <<-EOF
      #!/bin/bash
      set -eux
      echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf
      sysctl -p /etc/sysctl.d/99-nat.conf
      dnf install -y iptables iptables-services
      systemctl enable --now iptables
      iptables -P FORWARD ACCEPT
      iptables -I FORWARD -j ACCEPT
      iptables -t nat -A POSTROUTING -s ${var.cidr_block} -j MASQUERADE
      service iptables save
  EOF
  tags = { Name = "k8s-nat-instance" }
}

# --- Route Tables -------------------------------------------------------------
resource "aws_route_table" "k8s_public" {
  vpc_id = aws_vpc.k8s.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s.id
  }
}

resource "aws_route_table_association" "k8s_public" {
  subnet_id      = aws_subnet.k8s_public.id
  route_table_id = aws_route_table.k8s_public.id
}

resource "aws_route_table" "k8s_private" {
  vpc_id = aws_vpc.k8s.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat_ec2.primary_network_interface_id
  }
}

resource "aws_route_table_association" "k8s_private" {
  subnet_id      = aws_subnet.k8s_private.id
  route_table_id = aws_route_table.k8s_private.id
}

# --- K8s Security Group -------------------------------------------------------
resource "aws_security_group" "k8s" {
  name   = "k8s-lab-sg"
  vpc_id = aws_vpc.k8s.id

  # 1. SSH 접속 전면 허용 (Private 망이므로 외부 노출 위험 없음)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # SSH, K8s API, 내부 통신 전면 허용 (Private Subnet이므로 안전함)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block, "172.16.8.0/24"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- K8s Instances (Private Subnet) -------------------------------------------
# data "aws_ami" "ubuntu" {
#   most_recent = true
#   owners      = ["099720109477"]
#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
#   }
#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }
# }
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] 
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Master Node (Tailscale 연동)
resource "aws_instance" "master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.master_instance_type
  subnet_id                   = aws_subnet.k8s_private.id
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  associate_public_ip_address = false
  key_name                    = aws_key_pair.k8s.key_name
  source_dest_check           = false

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
      #!/bin/bash
      exec > >(tee -a /var/log/user_data_final.log) 2>&1
      hostnamectl set-hostname "k8s-master"
      echo "127.0.0.1 k8s-master" >> /etc/hosts
      
      until ping -c 1 8.8.8.8 &> /dev/null; do sleep 5; done        
      
      curl -fsSL https://tailscale.com/install.sh | sh
      systemctl enable --now tailscaled

      # [추가됨] 확실한 라우팅 및 IP 포워딩 설정
      sysctl -w net.ipv4.ip_forward=1
      echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-tailscale.conf
      echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-tailscale.conf
      sysctl -p /etc/sysctl.d/99-tailscale.conf

      # [추가됨] 강력한 SNAT(마스커레이딩) 적용 - 워커가 리턴 패킷을 길 잃지 않도록 강제
      iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
      iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE 

      tailscale up --authkey=${tailscale_tailnet_key.k8s_join_key.key} \
                   --advertise-routes=${var.cidr_block} \
                   --accept-routes \
                   --hostname=k8s-master
  EOF
  tags = { Name = "k8s-master" }
}

# [수정됨] Tailscale 타이밍 이슈 방지 (60초 휴식)
resource "time_sleep" "wait_for_tailscale_sync" {
  depends_on      = [aws_instance.master]
  create_duration = "60s"
}

data "tailscale_device" "master_device" {
  hostname   = "k8s-master"
  wait_for   = "180s"
  depends_on = [time_sleep.wait_for_tailscale_sync]
}

resource "tailscale_device_subnet_routes" "approve_routes" {
  device_id = data.tailscale_device.master_device.id
  routes    = [var.cidr_block]
}

# Worker Nodes
resource "aws_instance" "workers" {
  count                       = var.worker_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.k8s_private.id
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  associate_public_ip_address = false
  key_name                    = aws_key_pair.k8s.key_name
  source_dest_check           = false

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
      #!/bin/bash
      exec > >(tee -a /var/log/user_data_final.log) 2>&1
      hostnamectl set-hostname "k8s-worker-${count.index + 1}"
      echo "127.0.0.1 k8s-worker-${count.index + 1}" >> /etc/hosts
      until ping -c 1 8.8.8.8 &> /dev/null; do sleep 5; done        
      echo "Worker Ready"
  EOF
  tags = { Name = "k8s-worker-${count.index + 1}" }
}


# --- Cloudflare Tunnel 본체 생성 -------------------------------------------
resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

resource "cloudflare_tunnel" "k8s_tunnel" {
  account_id = var.cloudflare_account_id
  name       = "k8s-local-tunnel"
  secret     = base64encode(random_password.tunnel_secret.result)
}

resource "cloudflare_record" "k8s_dns" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = "${cloudflare_tunnel.k8s_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_tunnel_config" "k8s_config" {
  account_id = cloudflare_tunnel.k8s_tunnel.account_id
  tunnel_id  = cloudflare_tunnel.k8s_tunnel.id

  config {
    ingress_rule {
      hostname = var.domain_name
      #NodePort 로 찌르기
      #service  = "http://localhost:32080" 
      # [변경됨] localhost 대신 K8s 내부 서비스 DNS 이름을 직접 찌릅니다!
      # 형식: http://<서비스이름>.<네임스페이스>.svc.cluster.local:<포트>
      service  = "http://nginx-nodeport-svc.default.svc.cluster.local:80"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}


# --- Ansible Automation -------------------------------------------------------
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/${var.ansible_inventory_path}"
  content = yamlencode({
    all = {
      vars = {
        ansible_user                 = var.ansible_ssh_user
        ansible_ssh_private_key_file = "${path.module}/${var.private_key_filename}"
        ansible_python_interpreter   = "/usr/bin/python3"
      }
      children = {
        master = {
          hosts = {
            "k8s-master" = {
              ansible_host = aws_instance.master.private_ip 
            }
          }
        }
        workers = {
          hosts = {
            for idx, inst in aws_instance.workers :
            "k8s-worker-${idx + 1}" => {
              ansible_host = inst.private_ip 
            }
          }
        }
      }
    }
  })
}

resource "local_file" "ansible_config" {
  filename = "${path.module}/${var.ansible_cfg_path}"
  content  = <<-EOF
    [defaults]
    inventory = ./${var.ansible_inventory_path}
    host_key_checking = False
    retry_files_enabled = False
    timeout = 30
    [ssh_connection]
    pipelining = True
  EOF
}

# 1. 인스턴스 대기
resource "terraform_data" "wait_for_instances" {
  depends_on = [
    aws_instance.master,
    aws_instance.workers,
    local_file.ansible_inventory,
    tailscale_device_subnet_routes.approve_routes
  ]
  triggers_replace = {
    master_id  = aws_instance.master.id
    worker_ids = join(",", aws_instance.workers[*].id)
  }
  provisioner "local-exec" {
    command = "sleep 240"
  }
}

# 2. K8s/Swarm 기본 세팅 실행
resource "terraform_data" "run_k8s_ansible" {
  depends_on = [terraform_data.wait_for_instances]
  triggers_replace = {
    always_run = "${timestamp()}"
  }
  provisioner "local-exec" {
    working_dir = path.module
    command     = "ANSIBLE_CONFIG=${var.ansible_cfg_path} ansible-playbook ${var.ansible_playbook_path}"
  }
}




# =================================================================
# 4. K8s 앱 자동 배포 (클라우드플레어 터널이 뚫린 후 실행)
# =================================================================
resource "terraform_data" "run_app_deploy" {
  depends_on = [
    terraform_data.run_k8s_ansible,         # K8s 기본 세팅이 끝난 후
    cloudflare_tunnel_config.k8s_config,    # 터널 설정이 끝난 후
    cloudflare_record.k8s_dns               # DNS 레코드 생성이 끝난 후
  ]

  triggers_replace = {
    always_run = "${timestamp()}" # apply 할 때마다 변경사항 반영
  }

  provisioner "local-exec" {
    working_dir = path.module
    #command     = "ANSIBLE_CONFIG=${var.ansible_cfg_path} ansible-playbook deploy-app.yml"
    # [변경됨] deploy-app.yml 실행 시 tunnel_token을 변수로 넘겨줍니다.
    command     = "ANSIBLE_CONFIG=${var.ansible_cfg_path} ansible-playbook deploy-app.yml --extra-vars 'tunnel_token=${nonsensitive(cloudflare_tunnel.k8s_tunnel.tunnel_token)}'"
  }
}
output "master_private_ip" { value = aws_instance.master.private_ip }
output "worker_private_ips" { value = aws_instance.workers[*].private_ip }