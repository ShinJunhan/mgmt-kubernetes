# main.tf

# =====================================================================
# 1. 프론트엔드 정적 웹 호스팅을 위한 S3 버킷 생성
# =====================================================================
resource "aws_s3_bucket" "frontend_bucket" {
  # 버킷 이름은 전 세계 AWS 인프라 내에서 고유(Unique)해야 합니다.
  bucket = "my-microservice-frontend-bucket-20260714-xyz" 
}

# [보안 핵심] S3 버킷의 모든 퍼블릭(인터넷) 접근을 원천 차단합니다.
# 사용자는 S3로 직접 접속할 수 없고, 반드시 CloudFront(CDN)를 거쳐야만 파일을 볼 수 있습니다.
resource "aws_s3_bucket_public_access_block" "frontend_block" {
  bucket                  = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = true # 새로운 퍼블릭 ACL 설정 차단
  block_public_policy     = true # 새로운 퍼블릭 버킷 정책 설정 차단
  ignore_public_acls      = true # 기존에 있던 퍼블릭 ACL 무시
  restrict_public_buckets = true # 퍼블릭 정책이 있는 버킷에 대한 외부 접근 차단
}

# =====================================================================
# 2. CloudFront OAC (Origin Access Control) 설정
# =====================================================================
# 구형 OAI 방식을 대체하는 최신 보안 기능입니다.
# CloudFront가 원본 서버(S3)에 접근할 때 사용할 인증/서명 방식을 정의합니다.
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "frontend-oac"
  origin_access_control_origin_type = "s3"     # 접근 대상이 S3임을 명시
  signing_behavior                  = "always" # 항상 요청에 서명(Sign)하여 보안 강화
  signing_protocol                  = "sigv4"  # AWS 최신 서명 프로토콜(SigV4) 사용
}

# =====================================================================
# 3. CloudFront 배포 (CDN 생성)
# =====================================================================
resource "aws_cloudfront_distribution" "frontend_cdn" {
  enabled             = true         # 생성 즉시 CDN을 활성화하여 트래픽을 받을 준비를 합니다.
  default_root_object = "index.html" # 도메인 루트(예: /)로 접속 시 기본으로 반환할 파일 (React, Vue 등 SPA 배포 시 필수)

  # [Origin] CDN이 원본 데이터를 가져올 출처(S3) 설정
  origin {
    domain_name              = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name # S3 버킷의 리전별 정확한 주소
    origin_id                = aws_s3_bucket.frontend_bucket.id                          # 해당 Origin을 식별하기 위한 고유 ID
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id               # 위에서 생성한 OAC를 연결하여 안전한 접근 권한 획득
  }

  # [Cache Behavior] 클라이언트의 접속 요청을 어떻게 캐싱하고 처리할지 설정
  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.frontend_bucket.id
    viewer_protocol_policy = "redirect-to-https" # 보안을 위해 HTTP 접속을 HTTPS로 강제 리다이렉트
    allowed_methods        = ["GET", "HEAD"]     # 프론트엔드 정적 파일 조회용이므로 GET, HEAD 요청만 허용
    cached_methods         = ["GET", "HEAD"]     # CloudFront 엣지 로케이션에 캐싱할 HTTP 메서드
    
    # 쿼리스트링이나 쿠키는 HTML/이미지 같은 정적 파일 조회에 필요 없으므로 
    # CDN에서 무시하도록 설정하여 캐시 적중률(Hit Rate)을 극대화합니다.
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  # [Restrictions] 특정 국가에서의 접속을 차단하거나 허용하는 지리적 제한 설정
  restrictions {
    geo_restriction { restriction_type = "none" } # 현재는 제한 없이 전 세계 오픈
  }

  # [Viewer Certificate] SSL/TLS 인증서 설정
  viewer_certificate {
    cloudfront_default_certificate = true # CloudFront가 기본으로 제공하는 도메인(*.cloudfront.net)과 자체 HTTPS 인증서 사용
  }
}

# =====================================================================
# 4. S3 버킷 정책 (Bucket Policy)
# =====================================================================
# "오직 내가 허락한 CloudFront 배포판만이 내 S3 버킷 안의 객체(파일)를 읽어갈 수 있다"는 강력한 출입 통제 규칙입니다.
resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"                                   # 동작을 허용한다
        Principal = { Service = "cloudfront.amazonaws.com" }  # 접근 주체: CloudFront 서비스 자체
        Action    = "s3:GetObject"                            # 수행 허용 동작: S3 객체(파일) 읽기
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"  # 대상 리소스: S3 버킷 내부에 있는 모든 하위 경로(/*)
        Condition = {
          # [보안 핵심] 아무 CloudFront나 접근하면 안 되므로, 
          # 정확히 '위에서 생성한 특정 CloudFront 배포(ARN)'의 요청일 때만 허용조건을 성립시킵니다.
          StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.frontend_cdn.arn }
        }
      }
    ]
  })
}

# =====================================================================
# 5. 테라폼 출력 값 (Outputs)
# =====================================================================
# 테라폼 배포(apply)가 완료된 후 터미널 화면에 띄워줄 결과값들입니다.

# 사용자가 웹 브라우저에 입력하고 접속할 실제 CDN 주소 (예: d12345abcdef.cloudfront.net)
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.frontend_cdn.domain_name
}

# 나중에 프론트엔드 코드를 업데이트(CI/CD)할 때, 
# 기존 캐시를 강제로 삭제(Invalidation)하는 명령어를 실행하기 위해 필요한 고유 ID
output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID"
  value       = aws_cloudfront_distribution.frontend_cdn.id
}