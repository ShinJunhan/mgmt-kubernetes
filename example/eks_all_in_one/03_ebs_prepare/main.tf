# 03_ebs_prepare/main.tf
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
#  1단계의 상태 장부(tfstate)를 실시간으로 읽어옵니다
# ---------------------------------------------------------
data "terraform_remote_state" "infra" {
  backend = "local"

  config = {
    # 1단계 폴더에 있는 장부 파일의 상대 경로를 지정합니다.
    path = "${path.module}/../01_eks_tailscale/terraform.tfstate"
  }
}

# ---------------------------------------------------------
# 장부에서 빼온 정보를 토대로 K8s 프로바이더 연결
# ---------------------------------------------------------
provider "kubernetes" {
  # data.terraform_remote_state.infra.outputs.XXXX 형태로 1단계 값을 꺼내 씁니다.
  host                   = data.terraform_remote_state.infra.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.eks_cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infra.outputs.eks_cluster_name, "--region", "ap-northeast-2"]
  }
}

# ---------------------------------------------------------
# 1. EBS CSI 드라이버가 디스크를 제어할 수 있는 권한(IAM Role) 생성
# ---------------------------------------------------------
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "ebs-csi-role"
  attach_ebs_csi_policy = true # 🌟 AWS가 미리 만들어둔 EBS 제어 권한 자동 연결!

  oidc_providers = {
    ex = {
      provider_arn               = data.terraform_remote_state.infra.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ---------------------------------------------------------
# 2. EKS 전용 단독 리소스로 애드온 추가
# ---------------------------------------------------------
resource "aws_eks_addon" "ebs_csi" {
  # 1단계 장부에서 알아낸 클러스터 이름 지정
  cluster_name = data.terraform_remote_state.infra.outputs.eks_cluster_name
  addon_name   = "aws-ebs-csi-driver"

  # 위에서 만든 3단계 IAM 역할을 드라이버에 쥐여줍니다!
  service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
}

# ---------------------------------------------------------
# 3. EBS용 StorageClass (gp3 타입 지정)
# ---------------------------------------------------------
resource "kubernetes_storage_class_v1" "ebs_sc" {
  metadata { name = "ebs-gp3" }
  
  storage_provisioner = "ebs.csi.aws.com"
  
  # 볼륨 생성 지연 (VolumeBindingMode)
  # EBS는 특정 가용영역(AZ)에 묶이는 디스크입니다. 파드가 뜨는 AZ를 확인한 후, 그곳에 디스크를 만들도록 기다리게 합니다!
  volume_binding_mode = "WaitForFirstConsumer" 
  
  # [볼륨 확장을 허용하는 옵션 ]
  # 나중에 pvc 의 용량만 늘려서 연결하면 된다.
  allow_volume_expansion = true
  
  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }
}
