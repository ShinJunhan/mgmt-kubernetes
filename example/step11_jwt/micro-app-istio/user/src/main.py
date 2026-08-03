
# authlib 필요함 
from fastapi import FastAPI, Body
from datetime import datetime, timedelta, timezone
from authlib.jose import jwt, JsonWebKey

app = FastAPI()
KEY_ID = "k8s-prime-key-id"

# ---------------------------------------------------------
# [1] 비밀키 로드 (단순 바이트 읽기)
# ---------------------------------------------------------
with open("private_key.pem", "rb") as f:
    private_key = f.read()

# ---------------------------------------------------------
# [2] 공개키 로드 및 JWKS 자동 변환 (Authlib의 마법)
# 복잡한 n, e 추출이나 Base64 인코딩 함수가 전혀 필요 없습니다!
# ---------------------------------------------------------
with open("public_key.pem", "rb") as f:
    # PEM 파일을 읽자마자 웹 표준 JWK 딕셔너리로 한 방에 변환합니다.
    jwk_obj = JsonWebKey.import_key(
        f.read(), 
        {'kty': 'RSA', 'kid': KEY_ID, 'use': 'sig'}
    )
    public_jwk = jwk_obj.as_dict()

# ---------------------------------------------------------
# JWKS 엔드포인트
# ---------------------------------------------------------
@app.get("/user/.well-known/jwks.json")
def get_jwks():
    return {"keys": [public_jwk]}

# ---------------------------------------------------------
# 로그인 (JWT 발급)
# ---------------------------------------------------------
@app.post("/user/login")
def generate_user_token(data: dict = Body(...)):
    username = data.get("userName", "Unknown")
    
    header = {'alg': 'RS256', 'kid': KEY_ID}
    
    # 토큰에 담을 정보를 구성한다
    # sub : 주체 (client 의 id, username)
    # exp : 유효기간
    # iss : 발급 주체
    # role : 역할, 권한 (role 에 따라서 사용할 수 있는 서비스의 종류가 다르다, 서비스 내에서의 권한도 다르다)
    payload = {
        "sub": username,
        "exp": int((datetime.now(timezone.utc) + timedelta(hours=24)).timestamp()),
        "iss": "http://svc-fastapi-user:8000/user/login", 
        "role": "수강생"
    }
    
    # 토큰 서명 후 문자열(utf-8)로 디코딩
    token = jwt.encode(header, payload, private_key).decode('utf-8')
    
    return {
        "status": "200 OK",
        "access_token": token,
        "token_type": "bearer"
    }