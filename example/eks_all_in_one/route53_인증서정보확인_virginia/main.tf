# Route 53 도메인 장부 정보 읽어오기
data "aws_route53_zone" "selected" {
  name = "${var.domain_name}."
  private_zone = false
}

# 미리 만들어서 준비된 인증서 가져오기 
data "aws_acm_certificate" "issued_cert" {
  domain = "*.${var.domain_name}"
  statuses = ["ISSUED"]
  most_recent = true
}

# 테스트용으로 인증서의 arn 출력해 보기
output "certificate_arn" {
  value = data.aws_acm_certificate.issued_cert.arn
}

# variables.tf 에 domain_name 변수 추가 
variable "domain_name" {
  default = "cloud-study.site"
}