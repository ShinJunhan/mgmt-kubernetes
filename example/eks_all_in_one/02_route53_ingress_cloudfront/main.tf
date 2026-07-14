# 02_route53_ingress_cloudfront

variable "domain_name" {
  type        = string
  default     = "cloud-study.site"
  description = "실습 및 서비스에 사용할 메인 도메인 이름"
}

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

# ---------------------------------------------------------
# 외부 리소스 데이터 호출 (Data Sources)
# ---------------------------------------------------------
data "aws_route53_zone" "selected" {
  name         = "${var.domain_name}."
  private_zone = false
}

# hosting 영역에 등록한 domain 에 대해서 미리 발급받아놓았던 인증서 정보 얻어내기 
data "aws_acm_certificate" "issued_cert" {
  domain      = "*.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

#data "aws_elb_hosted_zone_id" "current_region" {}
# NLB 전용 Zone ID를 가져옵니다!
data "aws_lb_hosted_zone_id" "nlb" {
  load_balancer_type = "network"
}

resource "helm_release" "ingress_nginx" {

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.0"
  namespace        = "ingress-nginx"
  create_namespace = true

  # 가독성을 위해 복잡한 set 문법 대신 YAML 구조형태로 대문(NLB)에 ACM 인증서 넣어주기
  values = [
    <<-EOT
    controller:
      service:
        type: LoadBalancer
        targetPorts:
          https: http
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "${data.aws_acm_certificate.issued_cert.arn}"
          service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
          service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
          service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    EOT
  ]
  
}

# Route 53에 주소를 넘겨주기 위해, 헬름이 만든 서비스의 상태창 장부를 실시간으로 읽어옵니다.
data "kubernetes_service_v1" "ingress_nginx_svc" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}


# 와일드카드 도메인(*.cloud-study.site)도 추가 매핑
resource "aws_route53_record" "wildcard" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.kubernetes_service_v1.ingress_nginx_svc.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = data.aws_lb_hosted_zone_id.nlb.id
    evaluate_target_health = true
  }
}

# Output
# output "ingress_controller_elb_url" {
#   value = data.kubernetes_service_v1.ingress_nginx_svc.status[0].load_balancer[0].ingress[0].hostname
# }
