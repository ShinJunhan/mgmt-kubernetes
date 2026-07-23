

### 모든 worker node 의  /etc/docker/daemon.json 파일 수정하기 

```bash
# harbor(172.16.8.40) 에서  이미지를 pull 할때  https 가 아닌 http 로 동작 가능하도록 설정 수정하는 playbook
ansible-playbook -i inventory.ini update-docker.yml
```