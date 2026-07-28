# 06_argocd_deploy/hello-app-deploy.tf

# argocd provider 를 활용한 app 배포할때는  resource "argocd_appliction" 을 사용하면 된다  
resource "argocd_application" "hello_app" {
  # 배포할 app 의 이름과 namespace 를 명시
  metadata {
    name = "hello-app"
    namespace = "argocd" # argocd 의 namespace 를 의미한다 
  }
  spec {
    project = "default"
    source {
      # git 저장소
      repo_url = "https://github.com/oli999/argocd_deploy_repo3.git"
      # 바라볼 branch 명
      target_revision = "master"
      # 폴더 경로 (Chart.yaml 파일이 있는 경로를 지정합니다)
      path = "hello"
    }
    destination {
        server = "https://kubernetes.default.svc" # 이미 정해진 이름 
        namespace = "default" # 배포할 namespace 지정 
    }
    sync_policy {
        automated {
          prune = true
          self_heal = true
        }
        sync_options = ["CreateNamespace=true"]
    }
  }
}