
### s3 버킷에 index.html 파일 올리기

```bash
# html 폴더에서 terminal 을 열록 아래의 명령어로 s3 버킷에 파일을 업로드 한다
aws s3 cp index.html s3://frontend-bucket-cloud-study-site/index.html
```

### terraform destroy 할때는  s3 버킷이 비어 있지 않아도 main.tf 에 지우는 설정이 되어 있다.

```bash
# terraform 으로 삭제 한다
terraform destroy --auto-approve
```