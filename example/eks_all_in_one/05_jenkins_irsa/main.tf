# 05_jenkins_irsa/main.tf 파일

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30" 
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

# AWS 리전 설정
provider "aws" {
  region = "ap-northeast-2"
}

# K8s 및 Helm Provider 설정
# 현재 로컬 환경(~/.kube/config)에 세팅된 EKS 컨텍스트를 사용하여 클러스터와 제어 평면 통신을 수행합니다.
provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# ---------------------------------------------------------
# [IRSA 설정] Jenkins 파드가 ECR에 접근할 수 있도록 IAM 권한(Role) 생성 및 매핑
# ---------------------------------------------------------

# 현재 실행 중인 AWS 계정(Account ID) 정보를 가져옵니다.
data "aws_caller_identity" "current" {}

# 대상 EKS 클러스터의 상세 정보(OIDC Issuer URL 등)를 조회합니다.
data "aws_eks_cluster" "this" {
  name = "hello-eks" # 실제 운영 중인 EKS 클러스터 이름으로 지정
}

# EKS 클러스터와 연동된 OIDC(OpenID Connect) 자격 증명 공급자 객체를 가져옵니다.
# (이후 IAM Role의 Trust Policy에서 안전하고 깔끔하게 ARN을 참조하기 위해 사용)
data "aws_iam_openid_connect_provider" "eks_oidc" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# Jenkins 파드가 AWS 리소스(ECR 등)에 접근할 때 사용할 IAM 역할을 생성합니다.
resource "aws_iam_role" "jenkins_irsa_role" {
  name = "jenkins-ecr-irsa-role"

  # Trust Policy (신뢰 정책): 이 역할을 위임받을 수 있는 주체와 조건을 엄격하게 정의합니다.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        
        # 1. 인증 주체: AWS IAM 사용자가 아닌, EKS 클러스터의 OIDC 공급자를 신뢰하도록 설정합니다.
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks_oidc.arn
        }
        
        # 2. 인증 방식: K8s 파드의 서비스 어카운트 토큰(JWT)을 검증하고 임시 자격 증명(STS)을 발급받습니다.
        Action = "sts:AssumeRoleWithWebIdentity"
        
        # 3. 보안 장벽: 클러스터 내 아무 파드나 이 역할을 쓰지 못하도록 특정 네임스페이스와 서비스 어카운트 이름으로 좁힙니다.
        Condition = {
          "StringEquals" = {
            # "jenkins 네임스페이스에 있는 jenkins-sa 라는 서비스 어카운트만 이 Role을 넘겨받을 수 있다"는 의미입니다.
            "${data.aws_iam_openid_connect_provider.eks_oidc.url}:sub" = "system:serviceaccount:jenkins:jenkins-sa"
          }
        }
      }
    ]
  })
}

# 위에서 생성한 Jenkins 전용 Role에 실제 권한(ECR PowerUser)을 부여합니다.
# 이를 통해 Jenkins CI/CD 파이프라인에서 도커 이미지를 ECR에 Push/Pull 할 수 있습니다.
resource "aws_iam_role_policy_attachment" "jenkins_ecr_policy" {
  role       = aws_iam_role.jenkins_irsa_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# ---------------------------------------------------------
# [Helm 배포] Jenkins 설치 및 K8s ServiceAccount ↔ IAM Role 연동 (IRSA)
# ---------------------------------------------------------

resource "helm_release" "my_jenkins" {
  name             = "my-jenkins" 
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  version          = "5.9.34"
  namespace        = "jenkins"
  create_namespace = true

  # 별도의 values 파일에서 Jenkins 세부 설정(플러그인, 리소스 제한 등)을 주입합니다.
  values = [
    file("${path.module}/jenkins-values.yaml")
  ]

  # [IRSA 연동] Helm 차트가 K8s ServiceAccount를 생성하도록 지시합니다.
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  # IAM Trust Policy의 Condition에 명시한 이름(jenkins-sa)과 정확히 일치시켜야 합니다.
  set {
    name  = "serviceAccount.name"
    value = "jenkins-sa"
  }

  # K8s 서비스 어카운트의 annotation에 생성된 IAM Role의 ARN을 매핑합니다.
  # 이 어노테이션이 있어야 AWS 웹훅이 파드 기동 시 임시 자격 증명 토큰을 자동으로 마운트해 줍니다.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.jenkins_irsa_role.arn
  }
}

# 향후 검증 및 다른 모듈에서의 참조를 위해 생성된 IAM Role의 ARN을 출력합니다.
output "jenkins_irsa_role_arn" {
  value       = aws_iam_role.jenkins_irsa_role.arn
  description = "Jenkins가 ECR에 접근하기 위해 발급받은 IRSA 역할의 ARN"
}