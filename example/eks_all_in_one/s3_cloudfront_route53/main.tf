# s3_cloudfront_route53/main.tf

# =========================================================
# 0. 변수 및 테라폼/프로바이더 기본 설정
# =========================================================
variable "domain_name" {
  type        = string
  default     = "cloud-study.site"
  description = "서비스에 사용할 메인 도메인 이름 (예: 사용자가 브라우저에 입력할 주소)"
}

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# [리전 분리 핵심 1] S3 버킷과 Route 53 레코드를 생성할 기본 리전 (서울)
provider "aws" {
  region = "ap-northeast-2"
}

# [리전 분리 핵심 2] CloudFront 인증서를 읽어오기 위한 전용 리전 (버지니아 북부)
# CloudFront는 글로벌 서비스이므로 반드시 us-east-1 리전의 인증서만 사용할 수 있습니다.
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# =========================================================
# 1. 외부 데이터 읽어오기 (Data Sources)
# =========================================================
# 테라폼으로 새로 만들지 않고, AWS에 이미 존재하는 자원의 정보를 검색해서 가져옵니다.

# (1) Route 53 호스팅 영역 정보: 레코드를 추가할 때 필요한 Zone ID를 알아냅니다.
data "aws_route53_zone" "selected" {
  name         = "${var.domain_name}."
  private_zone = false
}

# (2) ACM 인증서 정보: 미국 동부(us-east-1)에 이미 '발급 완료(ISSUED)'된 인증서의 ARN을 찾아옵니다.
data "aws_acm_certificate" "virginia_cert" {
  provider    = aws.virginia       # 위에서 설정한 버지니아 별칭 프로바이더 사용
  domain      = var.domain_name    # 찾을 도메인 이름 (cloud-study.site)
  statuses    = ["ISSUED"]         # 발급이 완료된 정상 인증서만 타겟팅
  most_recent = true               # 여러 개가 있다면 가장 최근 발급된 것 선택
}

# =========================================================
# 2. S3 버킷 세팅 (정적 파일 저장소)
# =========================================================
resource "aws_s3_bucket" "frontend_bucket" {
  # 버킷 이름은 전 세계적으로 유일해야 하므로 도메인 이름을 활용해 겹치지 않게 만듭니다.
  bucket        = "frontend-bucket-${replace(var.domain_name, ".", "-")}"
  
  # [실습 전용 옵션] 인프라 삭제(destroy) 시 버킷 안에 파일이 남아있어도 강제로 싹 지워줍니다. (운영 환경에선 절대 금지!)
  force_destroy = true 
}

# [보안] S3 버킷으로 들어오는 모든 직접적인 인터넷(퍼블릭) 접속을 차단합니다.
resource "aws_s3_bucket_public_access_block" "frontend_block" {
  bucket                  = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =========================================================
# 3. CloudFront 세팅 (CDN 및 라우팅)
# =========================================================
# (1) OAC 설정: CloudFront가 비공개 S3 버킷에 안전하게 접근하기 위한 최신 출입증 역할
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# (2) CloudFront CDN 배포 설정
resource "aws_cloudfront_distribution" "frontend_cdn" {
  enabled             = true
  default_root_object = "index.html" # 도메인으로 접속했을 때 기본으로 보여줄 파일
  aliases             = [var.domain_name] # 내 커스텀 도메인(cloud-study.site)을 CloudFront가 인식하게 만듦!

  # CDN이 바라볼 원본(Origin) 서버 지정 -> 위에서 만든 S3 버킷
  origin {
    domain_name              = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.frontend_bucket.id
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id # OAC 출입증 장착
  }

  # 사용자 요청(캐싱) 처리 방식
  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.frontend_bucket.id
    viewer_protocol_policy = "redirect-to-https" # 보안을 위해 HTTP 통신을 HTTPS로 강제 변환
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  # 사용자에게 보여줄 HTTPS 보안 인증서 장착
  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.virginia_cert.arn # 🌟 Data 소스로 읽어온 버지니아 인증서 꽂기!
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# =========================================================
# 4. 권한 및 도메인 매핑 (S3 정책 + Route53 연결)
# =========================================================
# S3 버킷 정책: "오직 위에서 방금 만든 이 CloudFront(frontend_cdn)만이 내 파일을 읽을 수 있다"
resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
      Condition = { 
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.frontend_cdn.arn } 
      }
    }]
  })
}

# Route 53 DNS 설정: 내 도메인(cloud-study.site)으로 들어온 사용자를 CloudFront 주소로 안내합니다.
resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain_name
  type    = "A" # AWS 리소스 간의 연결이므로 CNAME 대신 Alias(A 레코드) 사용

  alias {
    name                   = aws_cloudfront_distribution.frontend_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.frontend_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# =========================================================
# 5. 출력 (Outputs)
# =========================================================
# 실습 후 터미널 창에 띄워줄 결과값들입니다.

# 사용자가 웹 브라우저에서 바로 클릭해서 접속해 볼 수 있는 최종 URL
output "frontend_url" {
  value = "https://${var.domain_name}"
}

# 프론트엔드 소스가 업데이트(재배포) 되었을 때, 이전 캐시를 지우기 위해 사용하는 ID 값
output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.frontend_cdn.id
  description = "캐시 무효화(Invalidation) 스크립트용 ID"
}