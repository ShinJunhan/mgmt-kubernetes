
## cloudflared pod 사용해 보기

<a href="https://docs.google.com/document/d/1xvrG1ID6UX4EHSmgzQNVXwbasBE0yJkPuV84q7-tAc0/edit?tab=t.0">도메인 등록 및 api key 얻어내기 참고</a> 


# 토큰 뽑아내기: (sensitive = true로 가려져 있으므로 -raw 옵션을 줘서 날것 그대로 뽑아냅니다)
terraform output -raw tunnel_real_token