
### jenkins 서버가 ECR 에 이미지를 push 하기 위해서는 iam 권한이 필요하다


```bash
# secret access key 출력하는 방법 
terraform output -raw jenkins_ecr_secret_access_key
```

### iam user 정보를 jenkins 서버에 등록을 해야 한다 

<img src="./assets/image01.png">