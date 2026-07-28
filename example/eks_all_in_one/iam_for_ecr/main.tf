# eks_all_in_one/iam_for_ecr/main.tf 파일

terraform {
  required_version = ">= 1.10" 

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" 
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

# 1. ECR 전용 IAM 사용자 생성
resource "aws_iam_user" "jenkins_ecr_user" {
  name = "jenkins-ecr-deployer"
  # 이 user 가 어떤 user 인지 식별하기 쉽도록 경로를 부여한다 
  path = "/cicd/"
  
  tags = {
    Description = "IAM User for Jenkins CI/CD to access ECR"
  }
}

# 2. ECR 접근 권한 정책 연결
# AmazonEC2ContainerRegistryPowerUser는 이미지 Push/Pull은 가능하지만, 
# ECR 리포지토리 자체를 삭제할 수는 없는 CI/CD에 가장 적합한 AWS 관리형 권한입니다.
resource "aws_iam_user_policy_attachment" "jenkins_ecr_attach" {
  user       = aws_iam_user.jenkins_ecr_user.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# 3. Jenkins에 등록할 Access Key 및 Secret Key 생성
resource "aws_iam_access_key" "jenkins_ecr_key" {
  user = aws_iam_user.jenkins_ecr_user.name
}

# 4. 출력(Output) 설정 - apply 후 터미널에서 키 값을 확인하기 위함
output "jenkins_ecr_access_key_id" {
  value       = aws_iam_access_key.jenkins_ecr_key.id
  description = "The Access Key ID for Jenkins"
}

output "jenkins_ecr_secret_access_key" {
  value       = aws_iam_access_key.jenkins_ecr_key.secret
  description = "The Secret Access Key for Jenkins"
  sensitive   = true # 화면에 마스킹 처리됨
}

# 확인 방법
# terraform output -raw jenkins_ecr_secret_access_key