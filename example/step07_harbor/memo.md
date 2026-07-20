# step07_harbor/memo.md

## Harbor 사용해 보기

### helm chart 를 이용해서 local k8s cluster 에 직접 설치하기

```bash
# 1. Harbor 공식 Helm 저장소 추가 및 업데이트
helm repo add harbor https://helm.goharbor.io
helm repo update

# 2. Harbor 설치 (TLS 비활성화 & NodePort 30002번 개방)
helm install my-harbor harbor/harbor \
  --namespace harbor-system \
  --create-namespace \
  --set expose.type=nodePort \
  --set expose.tls.enabled=false \
  --set expose.nodePort.ports.http.nodePort=30002 \
  --set externalURL=http://172.16.8.10:30002 \
  --set persistence.enabled=false

```

### harbor 서비스 확인

<img src="./assets/image01.png">

### 웹브라우저로 접속  

<img src="./assets/image02.png">

<img src="./assets/image03.png">

### harbor 를 사용하기 위해 local docker 설정을 변경해야 한다 

```bash
# 1. 도커 설정 폴더 생성
sudo mkdir -p /etc/docker

# 2. insecure-registries 예외 목록 추가 (http 가 아닌 https 로 접속해서 사용가능하도록)
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "insecure-registries": ["localhost:30002", "127.0.0.1:30002", "172.16.8.10:30002"]
}
EOF

# 3. 도커 서비스 재시작하여 설정 적용
sudo systemctl restart docker

# 4. 설정이 잘 적용되었는지 확인 (Insecure Registries 항목에 위 주소들이 보이면 성공)
docker info | grep -A 2 'Insecure Registries'
```

### harbor 에 로그인해서 새 프로젝트를 생성한다 

<img src="./assets/image04.png">

<img src="./assets/image05.png">

### harbor 에 docker login 후에 이미지 push 하기 

```bash
# 1. Harbor 서버에 로그인 (설정한 ID/PW 사용)
docker login 172.16.8.10:30002 -u admin -p Harbor12345

# 2. Harbor 에 push 할 이미지 준비
docker tag  member-app:1.0  172.16.8.10:30002/my-test/member-app:v1.0

# 3. Harbor 에 push 하기
docker push 172.16.8.10:30002/my-test/member-app:v1.0
```

### push 된 이미지 확인
<img src="./assets/image06.png">

### harbor 에 저장된 이미지 사용해 보기

```bash
# pull 받는 방법  [Harbor주소/프로젝트명/이미지명:tag]
docker pull 172.16.8.10:30002/my-test/member-app:v1.0

```

### deploy yaml 에서  이미지명만 잘 작성하면 동일하게 동작한다

```yaml
spec:
  containers:
  - name: member-app-ctn
  # 핵심: 여기에 Harbor 주소를 포함한 전체 이미지 경로를 적어줍니다!
  image: 172.16.8.10:30002/my-test/member-app:v1.0
  ports:
  - containerPort: 8000
```

### MetalLB 환경에서 Harbor 설치 (LoadBalancer 고정 IP)

```bash
# 사용할 고정 IP 변수 지정 (MetalLB IP 풀 대역 내의 IP여야 합니다!)
export HARBOR_IP="172.16.8.40"

# Harbor 설치 (type=loadBalancer 및 고정 IP 지정)
helm install my-harbor harbor/harbor \
  --namespace harbor-system \
  --create-namespace \
  --set expose.type=loadBalancer \
  --set expose.tls.enabled=false \
  --set expose.loadBalancer.IP=$HARBOR_IP \
  --set externalURL=http://$HARBOR_IP \
  --set persistence.enabled=false

# 이미 만들었음
#sudo mkdir -p /etc/docker

cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "insecure-registries": ["172.16.8.40", "172.16.8.40:80"]
}
EOF

sudo systemctl restart docker

# 1. Harbor 서버에 로그인 (설정한 ID/PW 사용)
docker login 172.16.8.40 -u admin -p Harbor12345

# 2. Harbor 에 push 할 이미지 준비
docker tag  member-app:1.0  172.16.8.40/my-test/member-app:v1.0

# 3. Harbor 에 push 하기
docker push 172.16.8.40/my-test/member-app:v1.0
```

### nfs 볼륨을 편하게 사용하기 위한 설정

```bash

# 172.16.8.203 nfs 서버에 ./make-nfs.sh local-k8s 를 입력해서 /nfs/shared/local-k8s 공유 폴더를 미리 준비해 둔다 

# 1. NFS 프로비저너 설치 
# 최신 공식 Helm 저장소 추가 및 업데이트
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# 프로비저너 설치 (서버 IP와 경로를 우리 환경에 맞게 주입)
# --set storageClass.defaultClass=true 이 옵션을 주면 앞으로 PVC를 만들 때 storageClassName을 생략해도 K8s가 알아서 이 NFS를 가져다 씁니다.
helm install nfs-client nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace kube-system \
  --set nfs.server=172.16.8.203 \
  --set nfs.path=/nfs/shared/local-k8s \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=true 

# 프로비저너 파드가 잘 떠있는지 확인
kubectl get pods -n kube-system | grep nfs-client

# 스토리지 클래스가 잘 만들어졌고, (default) 마크가 붙어있는지 확인
kubectl get sc

# harbor 의 실행 옵션을 직접 명시 해서 설치하기 
helm install my-harbor harbor/harbor \
  --namespace harbor-system \
  --create-namespace \
  --set expose.type=loadBalancer \
  --set expose.tls.enabled=false \
  --set expose.loadBalancer.IP=$HARBOR_IP \
  --set externalURL=http://$HARBOR_IP \
  --set persistence.enabled=true \
  --set persistence.persistentVolumeClaim.registry.storageClass="nfs-client" \
  --set persistence.persistentVolumeClaim.registry.size="3Gi"

# my-harbor 를 uninstall 한 후에 아래의 명령어를 이용해서 다시 설치하기
helm uninstall my-harbor -n harbor-system

# harbor 의 실행 옵션을 harbor-values.yaml 파일에 작성후에 해당 파일을 이용해서 설치하기
helm install my-harbor harbor/harbor \
  --namespace harbor-system \
  --create-namespace \
  -f harbor-values.yaml

# 이미 만들었음
#sudo mkdir -p /etc/docker

cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "insecure-registries": ["172.16.8.40", "172.16.8.40:80"]
}
EOF

sudo systemctl restart docker

# 1. Harbor 서버에 로그인 (설정한 ID/PW 사용)
docker login 172.16.8.40 -u admin -p Harbor12345

# 2. Harbor 에 push 할 이미지 준비
docker tag  member-app:1.0  172.16.8.40/test/member-app:v1.0

# 3. Harbor 에 push 하기
docker push 172.16.8.40/test/member-app:v1.0

```

### deploy yaml 에서  이미지명만 잘 작성하면 동일하게 동작한다

```yaml
spec:
  containers:
  - name: member-app-ctn
  # 핵심: 여기에 Harbor 주소를 포함한 전체 이미지 경로를 적어줍니다!
  image: 172.16.8.40/test/member-app:v1.0
  ports:
  - containerPort: 8000
```