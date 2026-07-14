# route53_인증서발급_virginia/route53.tf
# =========================================================
# 1. 기존 도메인(Route 53) 정보 조회
# =========================================================
# AWS 계정에 이미 등록되어 있는 Route 53 호스팅 영역(도메인 장부)을 찾아옵니다.
# 나중에 인증서 검증용 CNAME 레코드를 이 장부에 적어넣기 위해 Zone ID가 필요합니다.
data "aws_route53_zone" "selected" {
  name         = "${var.domain_name}." # 끝에 점(.)이 붙는 것은 DNS 절대경로 표기법입니다.
  private_zone = false
}

# =========================================================
# 2. ACM 인증서 발급 신청 (미국 동부 리전)
# =========================================================
# [핵심] CloudFront는 전 세계에 배포되는 글로벌 서비스이므로, 
# 반드시 미국 동부(us-east-1) 리전에서 발급받은 인증서만 연결할 수 있습니다.
resource "aws_acm_certificate" "frontend_cert" {
  provider          = aws.virginia      # 테라폼에게 서울이 아닌 버지니아로 가라고 지시!
  domain_name       = var.domain_name   # 보호할 도메인 이름 (예: cloud-study.site)
  validation_method = "DNS"             # "이 도메인 내 거 맞아요!" 라고 증명할 방식으로 DNS 선택
}

# =========================================================
# 3. DNS 검증용 레코드 자동 생성 (도메인 소유권 증명)
# =========================================================
# AWS가 "진짜 네 도메인이면 우리가 주는 이 복잡한 난수(CNAME)를 네 DNS에 등록해 봐!" 라고 낸 숙제를
# 테라폼이 받아서 Route 53에 자동으로 등록해 주는 과정입니다.
resource "aws_route53_record" "cert_validation" {
  # 인증서에서 요구하는 검증용 도메인 정보들을 하나씩 꺼내서 반복문(for_each)으로 처리합니다.
  for_each = {
    for dvo in aws_acm_certificate.frontend_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  
  zone_id         = data.aws_route53_zone.selected.zone_id # 찾은 Route 53 장부에
  name            = each.value.name                        # AWS가 요구한 이름으로
  type            = each.value.type                        # CNAME 타입을
  records         = [each.value.record]                    # 지정한 목적지로 기록합니다.
  ttl             = 60
  
  # 다른 리전(예: 서울)에서 이미 같은 도메인으로 발급받으면서 
  # 동일한 검증 레코드가 존재할 경우, 에러를 내지 않고 덮어쓰고 넘어가도록 허용합니다.
  allow_overwrite = true
}

# =========================================================
# 4. 인증서 검증 대기 및 완료 (테라폼의 기다림)
# =========================================================
# 테라폼이 Route 53에 숙제(레코드)를 제출한 뒤, AWS가 이를 확인하고 인증서를 '발급됨(ISSUED)' 상태로 
# 바꿔줄 때까지 코드를 멈추고 기다리는 역할을 합니다. (보통 1~3분 소요)
resource "aws_acm_certificate_validation" "cert_val" {
  provider                = aws.virginia
  certificate_arn         = aws_acm_certificate.frontend_cert.arn
  # 위에서 생성한 검증용 레코드들의 이름(fqdn)을 참조하여, 해당 레코드들이 전부 전파될 때까지 대기합니다.
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}