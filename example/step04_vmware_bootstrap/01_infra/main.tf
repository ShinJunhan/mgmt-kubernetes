# 01_infra/main.tf

# terraform 을 이용해서 argocd helm 설치, nginx-ingress-controller helm 설치

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

# helm provider 가 동작할 준비가 되어 있으면 "helm_release" 를 사용할수 있다.
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
    # ingress nginx 가 설치된 이후에 실행되도록
    depends_on = [helm_release.ingress_nginx]
    # 주의!  yaml 파일에는 한종류의 deploy, svc 등이 있어야 한다
    # --- 로 구분해서 여러 종류의 배포는 되지 않는다
    # namespace 도 반드시 명시해야한다 
    manifest = yamldecode(file("${path.module}/ingress-rule/rule.yaml"))
}

# helm provider 가 동작할 준비가 되어 있으면 "helm_release" 를 사용할수 있다.
resource "helm_release" "argocd" {
  name             = "argocd"
  # helm 저장소의 위치
  repository       = "https://argoproj.github.io/argo-helm"
  # chart 의 이름
  chart            = "argo-cd"
  # chart 버전
  version          = "3.35.4"
  # namespace 설정 
  namespace        = "argocd"
  create_namespace = true
  # my-values.yaml 파일을 읽어서 설치 하도록 한다 
  values = [ file("${path.module}/argocd/my-values.yaml") ]
  
}
