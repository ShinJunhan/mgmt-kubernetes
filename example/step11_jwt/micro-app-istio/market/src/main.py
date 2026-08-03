# main.py (for fastapi-market)
from fastapi import FastAPI

app = FastAPI()

# 인그레스가 /market으로 트래픽을 토스하므로 백엔드도 /market 엔드포인트가 열려있어야 합니다!
@app.get("/market")
def read_market():
    return {
        "service": " MSA Pod 2: Market Service",
        "image": "myoli999/fastapi-market:1.0",
        "status": "success",
        "path": "/market",
        "message": "인그레스 사령탑이 마켓 전용 독립 컨테이너로 트래픽을 정확히 배달했습니다.",
        "products": [
            {"id": 1, "name": "MSA 격리용 청정 컨테이너", "price": "품절"},
            {"id": 2, "name": "L7 주소창 교통정리 장부", "price": "0원"}
        ]
    }