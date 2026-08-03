# 07_gitea/main.tf

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
      version = "~> 2.14"
    }
  }
}
# 클러스터 접속정보 (local k8s 를 바라 보도록 context 가 변경되어 있어야 한다)
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# helm provider 가 동작하려면 config 파일 정보를 전달해야 한다. 
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}


resource "helm_release" "my_gitea" {
  # helm install my-gitea
  name             = "my-gitea"

  # helm repo add gitea-charts https://dl.gitea.com/charts/
  repository       = "https://dl.gitea.com/charts/"
  chart            = "gitea"

  version        = "12.6.0"
  # -n gitea
  namespace        = "gitea"

  # kubectl create namespace gitea 역할
  create_namespace = true

  # -f gitea-values.yaml
  values = [
    file("${path.module}/gitea-values.yaml")
  ]
}