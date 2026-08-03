#!/bin/bash

# 오류 발생 시 스크립트 실행 중단 설정
set -e

# 도커 허브 ID 정의
DOCKER_USER="junhanshin"

echo "============================================="
echo "🚀 마이크로서비스 이미지 빌드 및 푸시 시작"
echo "============================================="

# 1. micro-index:1.0 빌드 및 푸시
echo "📦 [1/4] micro-index 빌드 중..."
docker build -t $DOCKER_USER/micro-index:1.0 ./micro-app-istio/index
docker push $DOCKER_USER/micro-index:1.0

# 2. micro-user:1.0 빌드 및 푸시
echo "📦 [2/4] micro-user 빌드 중..."
docker build -t $DOCKER_USER/micro-user:1.0 ./micro-app-istio/user
docker push $DOCKER_USER/micro-user:1.0

# 3. micro-market:1.0 빌드 및 푸시
echo "📦 [3/4] micro-market 빌드 중..."
docker build -t $DOCKER_USER/micro-market:1.0 ./micro-app-istio/market
docker push $DOCKER_USER/micro-market:1.0

# 4. micro-post:1.0 빌드 및 푸시
echo "📦 [4/4] micro-post 빌드 중..."
docker build -t $DOCKER_USER/micro-post:1.0 ./micro-app-istio/posts
docker push $DOCKER_USER/micro-post:1.0

echo "============================================="
echo "✅ 모든 이미지의 빌드 및 푸시가 완료되었습니다!"
echo "============================================="
