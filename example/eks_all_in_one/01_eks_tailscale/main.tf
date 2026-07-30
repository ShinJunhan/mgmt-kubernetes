# 01_eks_tailscale/main.tf 

# ---------------------------------------------------------
# 0. 버전 관리 
# ---------------------------------------------------------
terraform {
  required_version = ">= 1.10" 

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # EKS 1.35 API를 완벽 지원하기 위해 최소 5.75 이상 사용 권장
      version = ">= 5.75" 
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30" 
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

# ---------------------------------------------------------
# 1. 네트워크 계층 (VPC)
# ---------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-northeast-2a", "ap-northeast-2c"]
  # private subnet 당 약 4000 개의 ip 주소 확보 
  private_subnets = ["10.0.16.0/20", "10.0.32.0/20"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

# ---------------------------------------------------------
# 2. 인프라 계층 (EKS v20 최신 규격)
# ---------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "hello-eks"
  cluster_version = "1.35" # 🌟 1.34로 업데이트

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true
  enable_irsa = true

  # 🌟 EKS 1.35 호환 애드온 버전 자동 추적 옵션 추가
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })    
    }
  }

  node_security_group_additional_rules = {
    ingress_vpc_all = {
      description = "Allow all traffic from VPC CIDR (Cross-Node Pod Communication)"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = ["10.0.0.0/16"]
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 1
      max_size       = 4
      desired_size   = 2
      
      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              kubelet:
                config:
                  maxPods: 64
          EOT
        }
      ]      
    }
  }
}

# ---------------------------------------------------------
# 3. 애플리케이션 계층 (Nginx)
# ---------------------------------------------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    # 🌟 [매우 중요] K8s 1.30 이상에서 v1beta1 삭제됨. 반드시 v1으로 변경
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "ap-northeast-2"]
  }
}

# --- Tailscale Subnet Router 배포용 null_resource ---
resource "null_resource" "install_tailscale_router" {
  depends_on = [ module.eks ]

  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ap-northeast-2 --name hello-eks
      ansible-playbook -i localhost, -c local playbook-tailscale.yml --extra-vars 'tailscale_auth_key=${var.tailscale_auth_key}'
    EOT
  }
}

variable "tailscale_auth_key" {
    type        = string
    description = "tailscale 인증키" 
    sensitive   = true
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  value = module.vpc.private_subnets
}
