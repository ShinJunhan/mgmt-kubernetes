# step04_vmware_argocd_terraform/main.tf

terraform {
  required_providers {
    # ArgoCD 전용 프로바이더 선언
    argocd = {
      source  = "oboukili/argocd"
      version = "6.1.1" # 최신 안정화 버전
    }
    # terraform 으로 k8s 자원들을 provision 할수 있도록 provider 추가 
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30" 
    }
    # terraform 으로 helm chart 를 직접 배포 가능하도록 하는 provider 추가
    helm = {
      source = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}
# 클러스터 접속 정보 (local k8s 를 바라보도록 context 가 변경되어 있어야 한다)
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# helm provider 가 동작하려면 config 파일 정보를 전달해야 한다
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# helm provider 가 동작할 준비가 되어 있으면 "helm_release 를 사용할 수 있다"
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  # helm 저장소의 위치
  repository       = "https://kubernetes.github.io/ingress-nginx"
  # chart 의 이름
  chart            = "ingress-nginx"
  # chart 버전
  version          = "4.11.0"
  # namespace 설정
  namespace        = "ingress-nginx"
  create_namespace = true
}

# 테스트로 local 폴더에 있는 ingress rule yaml 파일을 terraform 으로 직접 배포하기
resource "kubernetes_manifest" "ingress_from_file" {
  # 주의! yaml 파일에는 한 종류의 deploy 또는 svc 등이 있어야 한다
  # --- 으로 구분해서 여러 종류의 배포는 되지 않는다
  # namespace 도 반드시 명시해야 한다
  manifest = yamldecode(file("${path.module}/ingress-rule/rule.yaml"))
}

# 1. K8s 안에서 ArgoCD Service 리소스를 검색해서 가져옴
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server" # 헬름이 생성한 서비스 이름
    namespace = "argocd"
  }
}

provider "argocd" {
  # 방금 뚫어놓은 도메인을 그대로 사용합니다!
  # cluster_ip (vpn 에 연결된 eks 에서 사용할 예정)
  # server_addr = "${data.kubernetes_service.argocd_server.spec[0].cluster_ip}:80" 
  # external_ip
  server_addr = "${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip}:80"
  
  # 초기 로그인 계정 정보
  username    = "admin"
  password    = "inXBq-fhLLWhBMb0"

  # 우리가 --insecure 로 HTTPS를 껐기 때문에 아래 옵션이 반드시 필요합니다!
  plain_text = true
  insecure   = true 
}

# 배포할 app 구성하기
resource "argocd_application" "member_app"{
    # 배포할 app 의 이름과 namespace 를 명시한다
    metadata {
      name = "member-app"
      # argocd 가 거주하고 있는 namespace 를 적어줘야 한다
      namespace = "argocd"
    }
    spec {
        project = "default"
        source {
            # helm repository 주소 또는 github 주소도 가능
            repo_url = "https://oli999.github.io/chart_test/"
            # 설치할 chart 의 이름
            chart = "member-app"
            # 버전 
            target_revision = "0.1.1"
            # (선택) values.yaml 값을 덮어쓰고 싶을 때 사용
            # helm {
            #   value_files = ["values.yaml"]
            #   parameter {
            #     name  = "replicaCount"
            #     value = "3"
            #   }
            # }
        }
        destination {
            # 정해진 이름 
            server = "https://kubernetes.default.svc"
            namespace = "default" # 배포할 namespace 지정 
        }
        # 동기화 정책
        sync_policy {
            automated {
                prune       = true
                self_heal   = true
            }
            # namespace 가 없는경우 자동으로 만들어 지도록   
            sync_options = ["CreateNamespace=true"]
        }
    }  
}

# 배포할 app 구성하기
resource "argocd_application" "microservice_app"{
    # 배포할 app 의 이름과 namespace 를 명시한다
    metadata {
      name = "microservice-app"
      namespace = "argocd"
    }
    spec {
        project = "default"
        source {
            # helm repository 주소 또는 github 주소도 가능
            repo_url = "https://oli999.github.io/helm-microservice/"
            # 설치할 chart 의 이름
            chart = "msa-platform"
            # 버전 
            target_revision = "0.1.0"
            # (선택) values.yaml 값을 덮어쓰고 싶을 때 사용
            # helm {
            #   value_files = ["values.yaml"]
            #   parameter {
            #     name  = "replicaCount"
            #     value = "3"
            #   }
            # }
        }
        destination {
            # 정해진 이름 
            server = "https://kubernetes.default.svc"
            namespace = "default" # 배포할 namespace 지정 
        }
        # 동기화 정책
        sync_policy {
            automated {
                prune       = true
                self_heal   = true
            }
            # namespace 가 없는경우 자동으로 만들어 지도록   
            sync_options = ["CreateNamespace=true"]
        }
    }  
}

# prometheus stack argocd application 으로 배포
resource "argocd_application" "prometheus_stack"{
    # 배포할 app 의 이름과 namespace 를 명시한다
    metadata {
      name = "prometheus-stack"
      namespace = "argocd"
    }
    spec {
        project = "default"
        source {
            # helm repository 주소 또는 github 주소도 가능
            repo_url = "https://prometheus-community.github.io/helm-charts"
            # 설치할 chart 의 이름
            chart = "kube-prometheus-stack"
            # 버전 
            target_revision = "87.10.1"
            # chart 를 설치할 때 custom 변수 전달하기
            helm {
              values = file("${path.module}/prometheus/my-values.yaml")
            }
        }
        destination {
            # 정해진 이름 
            server = "https://kubernetes.default.svc"
            namespace = "default" # 배포할 namespace 지정 
        }
        # 동기화 정책
        sync_policy {
            automated {
                prune       = true
                self_heal   = true
            }
            # 크기가 크고 무거운 chart 는 ServerSideApply=true 옵션을 같이 전달한다
            # argocd 는 용량 제한이 있기 때문에 k8s 에 직접 던져서 실행이 되도록   
            sync_options = ["CreateNamespace=true", "ServerSideApply=true"]
        }
    }  
}

# external_ip 가 잘 얻어내지는지 확인
output "argocd_server_ip" {
  description = "argocd ip"
  value = "${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip}:80"
}