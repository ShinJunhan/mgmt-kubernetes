
![alt text](image.png)










# 좀비 없애기
kubectl patch app prometheus-stack -n argocd -p '{"metadata": {"finalizers": null}}' --type merge