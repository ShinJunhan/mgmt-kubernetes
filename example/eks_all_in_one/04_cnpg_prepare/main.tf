# 04_cnpg_prepare/main.tf
terraform {
  required_providers {
    # terraform 으로 k8s 자원들을 provision 할수 있도록 provider 추가 
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30" 
    }
    # terraform 으로 helm chart 를 직접 배포 가능하도록 하는 provider 추가
    helm = {
      source = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}
# 클러스터 접속정보 (eks 를 바라 보도록 context 가 변경되어 있어야 한다)
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# helm provider 가 동작하려면 config 파일 정보를 전달해야 한다. 
provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}


# helm provider 가 동작할 준비가 되어 있으면 "helm_release" 를 사용할수 있다.
resource "helm_release" "cnpg" {
  name             = "cnpg"
  # helm 저장소의 위치
  repository       = "https://cloudnative-pg.github.io/charts"
  # chart 의 이름
  chart            = "cloudnative-pg"
  # chart 버전
  version          = "0.29.0"
  # namespace 설정 
  namespace        = "cnpg"
  create_namespace = true
}

# 이파일을 실행하면 cnpg 기반의  postgres DB 를 만들 준비가 된것이다
# DB 는 argocd_deploy 에서 생성할 예정 