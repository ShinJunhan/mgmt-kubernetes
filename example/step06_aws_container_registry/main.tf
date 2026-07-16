# step06_aws_container_registry/main.tf

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


resource "aws_ecr_repository" "member-app" {
  name                 = "member-app" # 창고 이름
  image_tag_mutability = "MUTABLE"        # 동일한 태그(v1) 덮어쓰기 허용

  image_scanning_configuration {
    scan_on_push = true                   # 이미지 올릴 때마다 보안 취약점 검사 (필수!)
  }
}

# # ECR 수명 주기 정책 (Lifecycle Policy)
resource "aws_ecr_lifecycle_policy" "member_app_cleanup" {
  # 어떤 창고에 적용할지 이름 지정 (위에서 만든 ECR 이름 참조)
  repository = aws_ecr_repository.member-app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1 # 숫자가 작을수록 먼저 실행됨
        description  = "최근 10개의 이미지만 남기고 모두 삭제 (비용 절감)"
        selection = {
          tagStatus   = "any"                  # 태그가 있든 없든 모든 이미지 대상
          countType   = "imageCountMoreThan"   # 기준: 이미지 개수가 다음 숫자보다 많을 때
          countNumber = 10                     # 남길 개수: 10개
        }
        action = {
          type = "expire"                      # 액션: 폐기(삭제)
        }
      }
    ]
  })
}