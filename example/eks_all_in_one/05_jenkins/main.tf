# 05_jenkins/main.tf

# main.tf 파일
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

# helm install 로 설치 했던 jenkins 을 terraform 으로 설치하기 
resource "helm_release" "my_jenkins" {
  # helm install my-jenkins 를 아래의 코드가 대신한다  
  name             = "my-jenkins" # jenkins 서비스 이름이 된다 

  # helm repo add jenkins https://charts.jenkins.io  를 아래의 코드가 대신한다 
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"

  version        = "5.9.34"

  # -n jenkins
  namespace        = "jenkins"

  # kubectl create namespace jenkins 역할
  create_namespace = true

  # -f jenkins-values.yaml
  values = [
    file("${path.module}/jenkins-values.yaml")
  ]
}