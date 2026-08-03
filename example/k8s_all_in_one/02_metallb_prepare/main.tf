# 02_metallb_prepare/main.tf

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
      source  = "hashicorp/helm"
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

# MetalLB Helm Chart 배포
resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  
  # 원하시는 버전(예: 0.13.10 또는 최신 버전에 해당하는 차트 버전) 지정
  version          = "0.13.10"

  namespace        = "metallb-system"
  create_namespace = true
}

# Helm 배포 후 CRD(YAML) 파일을 로컬 스크립트로 적용/삭제
resource "null_resource" "apply_metallb_crd" {
  depends_on = [helm_release.metallb]

  # [Apply 시 실행] 30초 대기 후 yaml 파일 적용
  provisioner "local-exec" {
    command = <<EOT
      echo "Waiting 30 seconds for MetalLB Webhooks to be ready..."
      sleep 30
      kubectl apply -f ${path.module}/metallb-crd.yaml
    EOT
  }

  # [Destroy 시 실행] 헬름 차트 삭제 전 yaml 자원 먼저 삭제
  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete --ignore-not-found=true -f ${path.module}/metallb-crd.yaml"
  }
}