### 모든 node 에 nfs client 가 설치 되어 있어야 한다

>설치되어 있지않은 경우 playbook 을 실행해서 설치하기


### 기존에 설치한적이 있으면 nfs-client 초기화 한다

```bash
# 1. 헬름으로 배포한 nfs-client 삭제
helm uninstall nfs-client -n kube-system

# 2. 헬름이 혹시 지우지 않고 남겨뒀을 수 있는 StorageClass(설계도) 확인 및 삭제
kubectl delete storageclass nfs-client
```

