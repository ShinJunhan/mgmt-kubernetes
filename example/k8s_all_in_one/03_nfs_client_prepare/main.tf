# main.tf
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

# 클러스터 접속정보 (eks 를 바라 보도록 context 가 변경되어 있어야 한다)
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# helm provider 가 동작하려면 config 파일 정보를 전달해야 한다. 
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# nfs-client helm 설치 
resource "helm_release" "nfs_client" {
  name       = "nfs-client"
  repository = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
  chart      = "nfs-subdir-external-provisioner"
  version    = "4.0.18" 
  namespace  = "kube-system"
  # 설치 옵션은 nfs-values.yaml 파일의 내용대로 지정하겠다
  values = [
    file("${path.module}/nfs-values.yaml")
  ]
}