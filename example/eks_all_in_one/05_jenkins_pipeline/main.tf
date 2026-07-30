# 05_jenkins_pipeline/main.tf

# 0. 변수 선언 (새로 추가)
variable "jenkins_api_token" {
  description = "Jenkins API 토큰"
  type        = string
  sensitive   = true # 화면이나 로그에 노출되지 않도록 암호화 처리
}

terraform {
  required_providers {
    jenkins = {
      source  = "taiidani/jenkins"
      version = "~> 0.10.0"
    }
  }
}

# 1. Jenkins 접속 정보 설정
provider "jenkins" {
  # jenkins 서버의 접속 url 
  server_url = "https://jenkins.cloud-learning.site"
  username   = "admin"
  # terraform.tfvars 파일에 있는 토큰을 이용하게 된다 
  password   = var.jenkins_api_token #  변수 참조
}

# 2. 파이프라인 Job 생성
resource "jenkins_job" "msa_pipeline" {
  # 파이프 라인의 이름이 된다.
  name     = "msa-backend-pipeline"
  template = file("${path.module}/config.xml")
}