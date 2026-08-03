# 09_argocd_deploy/hello-app-deploy.tf

# main.tf 에서 argocd 를 사용할 준비를 했기 때문에 여기서는 배포할 app 구성하면 된다
resource "argocd_application" "hello_app"{
    # 배포할 app 의 이름과 namespace 를 명시 한다 
    metadata {
      name = "hello-app"
      namespace = "argocd"
    }
    spec {
        project = "default"
        source {
            # gitea
            repo_url = "http://172.16.8.42/admin/argocd_deploy_repo2.git"
            # 바라볼 브랜치 (master 또는 main)
            target_revision = "master"
            
            # 핵심: Chart.yaml이 위치한 폴더 경로를 지정합니다.
            path            = "hello"
            
            # (옵션) Helm 특정 설정이 필요할 때
            # helm {
            #     value_files = ["values.yaml"]
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