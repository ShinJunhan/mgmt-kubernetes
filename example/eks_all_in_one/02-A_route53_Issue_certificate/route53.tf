# 02-A_route53_Issue_certificate/route53.tf
# =========================================================
# 1. 기존 도메인(Route 53) 정보 조회
# =========================================================
data "aws_route53_zone" "selected" {
  name         = "${var.domain_name}." # 예: cloud-study.in.
  private_zone = false
}

# =========================================================
# 2. ACM 인증서 발급 신청
# =========================================================
resource "aws_acm_certificate" "cert" {
  domain_name       = "*.${var.domain_name}" # 서브도메인용 (*.cloud-study.in)
  validation_method = "DNS"
  
  # 루트 도메인(cloud-study.in)도 함께 보호
  subject_alternative_names = [var.domain_name]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "lecture-certificate"
  }
}

# =========================================================
# 3. DNS 검증용 레코드 자동 생성 (Route 53에 숙제 제출)
# =========================================================
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selected.zone_id
}

# =========================================================
# 4. 인증서 검증 대기 및 완료 (최종 상태 확인)
# =========================================================
# 이 리소스가 성공적으로 완료되면 콘솔에서 '발급됨(Issued)' 상태를 볼 수 있습니다.
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# [출력] 나중에 리스너에 붙일 때 필요한 ARN 값을 미리 확인합니다.
output "certificate_arn" {
  value = aws_acm_certificate_validation.cert.certificate_arn
}