
```bash
# argo cd 배포 확인해 보기
kubectl get svc -n argocd 

NAME                               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
argocd-applicationset-controller   ClusterIP   172.20.46.30     <none>        7000/TCP            101s
argocd-dex-server                  ClusterIP   172.20.225.28    <none>        5556/TCP,5557/TCP   101s
argocd-redis                       ClusterIP   172.20.251.102   <none>        6379/TCP            101s
argocd-repo-server                 ClusterIP   172.20.70.195    <none>        8081/TCP            101s
argocd-server                      ClusterIP   172.20.62.95     <none>        80/TCP,443/TCP      101s

```