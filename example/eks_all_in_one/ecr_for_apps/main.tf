# eks_all_in_one/ecr_for_apps/main.tf

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

# ecr 을 생성하기 위한 app 의 이름을 배열에 미리 준비하기
variable "app_names" {
  description = "ECR 에 생성할 app 이름 목록"
  # 문자열 배열 
  type = list(string)
  # 기본값
  default = [ "fortune", "greet" ]
}

# 리스트로 정의된 app 목록을 이용해서 한번에 여러개의 ECR 창고 생성하기
resource "aws_ecr_repository" "hello_apps" {
  # 반복적으로 실행하기 위해
  for_each = toset(var.app_names)
  # fortune, greet, ... 등의 이름으로 만들어 지도록 한다
  name = "${each.key}"
  image_tag_mutability = "MUTABLE"
  # terraform destroy 했을때 이미지가 존재하더라도 지워 지도록 한다 (테스트 이기 때문에 상관 없음)
  force_delete = true
    image_scanning_configuration {
      scan_on_push = true
    }
}

# ECR 레포지토리 URL 출력
output "ecr_repository_urls" {
  description = "생성된 각 애플리케이션별 ECR 레포지토리 URL"
  # aws_ecr_repository.hello_apps 안의 데이터를 순회하며 "앱이름" = "ECR주소" 형태로 매핑
  value = {
    for app_name, repo in aws_ecr_repository.hello_apps : app_name => repo.repository_url
  }
}