# 03_efs_prepare/main.tf

terraform {
  required_version = ">= 1.10" 

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" 
    }
    # terraform 으로 k8s 자원들을 provision 할수 있도록 provider 추가 
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30" 
    }
  }
}

# ---------------------------------------------------------
# 1단계의 상태 장부(tfstate) 실시간 읽어오기
# ---------------------------------------------------------
data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "${path.module}/../01_eks_tailscale/terraform.tfstate"
  }
}

# 1단계 장부 기반 K8s 프로바이더 연결
provider "kubernetes" {
  host                   = data.terraform_remote_state.infra.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.eks_cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infra.outputs.eks_cluster_name, "--region", "ap-northeast-2"]
  }
}

# ---------------------------------------------------------
# 1-1. EFS 전용 보안 그룹 (NFS 2049 포트 개방)
# ---------------------------------------------------------
resource "aws_security_group" "efs_sg" {
  name        = "eks-efs-sg"
  description = "Allow NFS traffic for EKS EFS CSI"
  # 1단계 데이터 소스에서 VPC ID를 가져옵니다.
  vpc_id      = data.terraform_remote_state.infra.outputs.vpc_id

  ingress {
    description = "NFS traffic from EKS VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    #  1단계 데이터 소스에서 VPC CIDR 대역을 가져옵니다.
    cidr_blocks = [data.terraform_remote_state.infra.outputs.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------
# 1-2. EFS 파일 시스템 본체 생성
# ---------------------------------------------------------
resource "aws_efs_file_system" "eks_efs" {
  creation_token = "eks-efs-shared"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "eks-efs-shared"
  }
}

# ---------------------------------------------------------
# 1-3. EFS 마운트 타겟 생성 
# ---------------------------------------------------------
resource "aws_efs_mount_target" "eks_efs_mt" {
  #  1단계 데이터 소스에서 프라이빗 서브넷 개수를 동적으로 계산합니다.
  count = length(data.terraform_remote_state.infra.outputs.private_subnets)

  file_system_id  = aws_efs_file_system.eks_efs.id
  # 1단계 프라이빗 서브넷 ID에 한마운트 타겟을 매핑합니다.
  subnet_id       = data.terraform_remote_state.infra.outputs.private_subnets[count.index]
  security_groups = [aws_security_group.efs_sg.id]
}

# ---------------------------------------------------------
# 2-1. EFS CSI용 IAM 역할(IRSA) 생성 
# ---------------------------------------------------------
module "efs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "efs-csi-role"
  attach_efs_csi_policy = true 

  oidc_providers = {
    ex = {
      #  1단계 원격 장부에서 OIDC ARN을 가져옵니다.
      provider_arn               = data.terraform_remote_state.infra.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }
}

# ---------------------------------------------------------
# 2-2. EKS 전용 단독 리소스로 EFS 애드온 추가 장착!
# ---------------------------------------------------------
resource "aws_eks_addon" "efs_csi" {
  cluster_name             = data.terraform_remote_state.infra.outputs.eks_cluster_name
  addon_name               = "aws-efs-csi-driver"
  service_account_role_arn = module.efs_csi_irsa_role.iam_role_arn
}

# ---------------------------------------------------------
# 3. EFS용 StorageClass 생성
# ---------------------------------------------------------
resource "kubernetes_storage_class_v1" "efs_sc" {
  # 안전장치: EFS 애드온이 완벽히 설치된 후 생성되도록 보장
  depends_on = [aws_eks_addon.efs_csi]

  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap" # Access Point를 자동으로 생성해 주는 모드 
    fileSystemId     = aws_efs_file_system.eks_efs.id
    directoryPerms   = "700"
  }
}

# ---------------------------------------------------------
# 4. 아웃풋 출력 (Deploy 및 다음 단계 연동용)
# ---------------------------------------------------------
output "efs_file_system_id" {
  description = "AWS EFS File System ID"
  value       = aws_efs_file_system.eks_efs.id
}