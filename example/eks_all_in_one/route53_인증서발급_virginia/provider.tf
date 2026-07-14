# route53_인증서발급_virginia/provider.tf
# Terraform 및 Provider 버전 설정
terraform {
  required_version = "~>1.14.0" # 테라폼 실행기 자체의 버전을 제약합니다.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # 최신 기능 사용을 위해 5.0 이상 권장 (현재 6.0은 아직 대중적이지 않을 수 있음)
    }
  }
}

# AWS 프로바이더 설정: 모든 리소스는 서울 리전에 생성됩니다.
provider "aws" {
  alias = "virginia"
  region = "us-east-1"
}

