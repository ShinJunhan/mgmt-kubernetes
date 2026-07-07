## 프로메테우스, 그라파나 스텍 설치

```bash
# 1. 프로메테우스 커뮤니티 헬름 레포지토리 등록
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# 2. 메뉴판 최신화 (아까  명령어!)
helm repo update

# 3. 모니터링 전용 방(Namespace) 생성
kubectl create namespace monitoring

# 4. 커스텀 변수(my-values.yaml)를 적용해서 설치!
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f my-values.yaml

helm ls -n monitoring
kubectl get pod,svc -n monitoring

```



### grafana 를 service type LoadBalancer 로 변경하고 다시 적용해 보기

```yaml
# my-values.yaml
grafana:
  adminPassword: "admin" # 비밀번호를 쉽게 고정
  service:
    type: LoadBalancer
```   
```bash
# 만일 my-values.yaml 파일을 수정하고 다시 적용하고 싶으면 helm upgrade 로 실행하면 된다.
helm upgrade my-kube-prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f my-values.yaml

# metallb 로 부터 부여받은 ip 확인해서 접속해 보기 
kubectl get pod,svc -n monitoring
```

