# fastapi-index / src/main.py
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
import os

app = FastAPI()

# 루트 경로 요청 시 index.html 파일을 읽어서 사출하는 스마트 아키텍처
@app.get("/", response_class=HTMLResponse)
def read_root():
    # 현재 파일(main.py)과 같은 폴더에 있는 index.html 장부 경로 조준
    current_dir = os.path.dirname(os.path.abspath(__file__))
    html_file_path = os.path.join(current_dir, "index.html")
    
    # 파일을 열어서 날것 그대로 리턴!
    with open(html_file_path, "r", encoding="utf-8") as f:
        html_content = f.read()
        
    return html_content