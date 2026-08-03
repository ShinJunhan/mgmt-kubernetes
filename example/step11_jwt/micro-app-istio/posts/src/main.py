# main.py (for fastapi-posts)
from fastapi import FastAPI

app = FastAPI()

# 💡 인그레스가 /posts로 트래픽을 토스하므로 백엔드도 /posts 엔드포인트가 열려있어야 합니다!
@app.get("/posts")
def read_posts():
    return {
        "service": "⚙️ MSA Pod 3: Posts Service",
        "image": "myoli999/fastapi-posts:1.0",
        "status": "success",
        "path": "/posts",
        "message": "인그레스 사령탑이 포스트 전용 독립 컨테이너로 트래픽을 정확히 배달했습니다.",
        "articles": [
            {"post_id": 77, "title": "감격) 컨테이너 3개 찢어서 인그레스 분기 성공했다!!", "author": "수강생B"},
            {"post_id": 78, "title": "질문) 진짜로 프로젝트가 완전히 분리된 거였네요?", "author": "주니어"}
        ]
    }