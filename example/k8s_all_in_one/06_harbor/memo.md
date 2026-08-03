
### 재설치시 기존의 harbor 삭제후에 pvc 도 삭제

```bash
# pvc 확인
kubectl get pvc -n harbor-system
# pvc 삭제
kubectl delete pvc --all -n harbor-system
```



