# kubernetes/step01_eks/memo.md

## AWS CLI 를 이용해서 접속 정보 가져오기
```bash

# AWS CLI 를 이용해 접속 정보 가져오기
aws eks update-kubeconfig --region ap-northeast-2 --name hello-eks

# context 목록 얻어오기
kubectl config get-contexts

# 현재 선택된 context 조회
kubectl config current-contexts

kubectl get pod,svc -o wide


# 현재 선택된 context 조회
kubectl config get-contexts

# local k8s 클러스터로 context 변경
 kubectl config use-context kubernetes-admin@kubernetes

# 특정 context 삭제 
 kubectl config delete-context arn:aws:eks:ap-northeast-2:487054650
318:cluster/hello-eks


```