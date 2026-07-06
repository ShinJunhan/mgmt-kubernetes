# step02_local_cloudflared/main.tf

terraform {
  required_providers {
    # cloudflare 를 terraform 에서 사용할 수 있도록 준비
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# --- Provider -----------------------------------------------------------------
provider "cloudflare" {
  # 변수에 있는 api 토큰을 사용한다
  api_token = var.cloudflare_api_token
}

# --- 1. Tunnel Secret 생성 (터널 인증용 무작위 암호) ------------------------
resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

# --- 2. Cloudflare Tunnel 본체 생성 -------------------------------------------
# cloudflare_tunnel -> cloudflare_zero_trust_tunnel_cloudflared로 이름 변경
resource "cloudflare_zero_trust_tunnel_cloudflared" "vmware_tunnel" {
  account_id = var.cloudflare_account_id
  name       = "vmware-local-tunnel"
  secret     = base64encode(random_password.tunnel_secret.result)
}

# --- 3. DNS CNAME 레코드 생성 (내 도메인 -> 클라우드플레어 터널 연결) ---
# cloudflare_record -> cloudflare_dns_record로 이름 변경
resource "cloudflare_dns_record" "vmware_dns" {
  # 1. Zone ID: 어떤 도메인(예: cloud-learning.site)에 레코드를 추가할지 지정합니다. (변수에서 가져옴)
  zone_id = var.cloudflare_zone_id

  # 2. 레코드 이름(Name): "@"는 서브도메인(www 등) 없이 '루트 도메인' 자체로 접속함을 의미합니다.
  name    = "@"

  # 3. 목적지(Content): 도메인으로 들어온 트래픽을 보낼 도착지입니다. 
  # 클라우드플레어가 발급한 "터널의 고유 ://cfargotunnel.com" 주소로 동적 라우팅합니다.
  content = "${cloudflare_zero_trust_tunnel_cloudflared.vmware_tunnel.id}.cfargotunnel.com"

  # 4. 레코드 타입(Type): IP 주소가 아닌 도메인 이름(cfargotunnel.com)으로 연결하므로 'CNAME'을 사용합니다.
  type    = "CNAME"

  # 5. 프록시 활성화 (proxied = true): 클라우드플레어의 핵심 기능입니다. (주황색 구름 아이콘 ON)
  # 이 옵션이 true여야 무료 SSL(HTTPS) 인증서, DDoS 공격 방어, CDN 캐싱 기능이 터널에 적용됩니다.
  proxied = true
}

# --- 4. Tunnel 라우팅 규칙 (리버스 프록시 설정) -------------------------------
# 터널로 들어온 트래픽을 사설망 어디로 보낼지 결정합니다.
# cloudflare_tunnel_config -> cloudflare_zero_trust_tunnel_configuration으로 이름 변경
resource "cloudflare_zero_trust_tunnel_configuration" "vmware_config" {
  # [수정] 공급자 버전에 따른 참조 에러(Unsupported attribute)를 방지하기 위해 변수에서 계정 ID를 직접 참조하도록 변경했습니다.
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.vmware_tunnel.id

  config {
    # 첫 번째 규칙: 지정한 도메인으로 들어오면 vmware 내부 서비스로 전달
    ingress_rule {
      # junhanshin.com 으로 요청이 들어오면 터널과 연결된 아래의 위치로 전달한다
      hostname = var.domain_name
      # 인그래스 컨트롤러로 전달
      service  = "http://cluster.local" 

      # local cluster 의 svc 중에서 default 네임스페이스 있는 nginx-svc 라는 이름의 서비스로 전달
      # service  = "http://cluster.local"
    }
    
    # 마지막 규칙: 매칭되는 도메인이 없으면 404 에러 반환 (필수 설정)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "null_resource" "install_cloudflared_pod" {
    # 1. 터널 라우팅 규칙과 DNS 세팅이 "완벽히 끝난 후"에 앤서블을 실행해라!
    depends_on = [
        cloudflare_zero_trust_tunnel_configuration.vmware_config,
        cloudflare_dns_record.vmware_dns
    ]

    # 2. 터널 토큰이 바뀌면 무조건 앤서블을 다시 실행해라! (항상 실행하려면 timestamp 적용)
    # [수정] 버전간 호환성을 위해 유효한 내장 함수 문자열 보간 형태를 유지하거나, 명확한 고유 ID 매핑 구조로 안전성을 더했습니다.
    triggers = {
        always_run = "${timestamp()}"
    }
    
    # aws 에 프로비저닝을 하는 것이 아닌 local 에서 직접 ansible playbook 을 실행
    # [수정 사항] 참조 이름을 최신 리소스 명칭인 cloudflare_zero_trust_tunnel_cloudflared 로 교정했습니다.
    provisioner "local-exec" {
        command = "ansible-playbook -i localhost, -c local playbook-kubectl.yml --extra-vars 'tunnel_token=${cloudflare_zero_trust_tunnel_cloudflared.vmware_tunnel.tunnel_token}'"
    }

    # terraform destroy 했을 때 deploy 와 secret 도 같이 삭제 되도록 한다
    # [수정 사항] 파일 경로 유실이나 네트워크 단절 시 destroy가 비정상 종료되는 현상을 막기 위해 안전한 단선형 예외 처리 구조로 교정했습니다.
    provisioner "local-exec" {
      when    = destroy
      command = "kubectl delete -f deploy-cloudflared.yaml --ignore-not-found=true || true && kubectl delete secret tunnel-credentials --ignore-not-found=true || true"
    }
}

# [수정 사항] 참조 이름을 최신 리소스 명칭인 cloudflare_zero_trust_tunnel_cloudflared 로 교정했습니다.
output "tunnel_real_token" {
  description = "Cloudflare Tunnel Token"
  value       = cloudflare_zero_trust_tunnel_cloudflared.vmware_tunnel.tunnel_token
  sensitive   = true  
}

# --- Variables ----------------------------------------------------------------
variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID (도메인의 고유 ID)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "domain_name" {
  description = "연결할 외부 도메인 (예: yourdomain.com)"
  type        = string
}
