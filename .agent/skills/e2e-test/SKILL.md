---
name: E2E Pipeline Test
description: API 전 구간 자동 테스트 (Step 1~N)
---

## 실행 조건
- Backend와 Frontend 개발 서버가 모두 실행 중이어야 합니다.
- (예: Backend `localhost:5050`, Frontend `localhost:3000`)

## 🚀 테스트 순서 (예시: 파이프라인 흐름)
해당 프로젝트의 API 명세에 맞게 아래 명령어들을 수정하여 사용하세요.

### Step 1: 프로젝트/작업 생성
```bash
curl -X POST http://localhost:5050/api/project/create \
  -H "Content-Type: application/json" \
  -d '{"title":"테스트 프로젝트"}'
```
> **기대 결과:** HTTP 200, `{"project_id": "생성된_ID"}` 반환. 이후 단계에서는 이 ID를 변수 `$PROJECT_ID`로 사용하세요.

### Step 2: 단위 작업 1 (예: 텍스트 생성)
```bash
curl -X POST http://localhost:5050/api/script/generate \
  -H "Content-Type: application/json" \
  -d '{"project_id":"'"$PROJECT_ID"'","topic":"테스트 대상"}'
```
> **기대 결과:** 성공적인 텍스트 생성 응답 또는 SSE 스트림 송출 완료.

### Step 3: 단위 작업 2 (예: 이미지 생성 등)
```bash
curl -X POST http://localhost:5050/api/image/generate \
  -H "Content-Type: application/json" \
  -d '{"project_id":"'"$PROJECT_ID"'","provider":"pollinations"}'
```
> **기대 결과:** 로컬 디스크의 특정 폴더(`images/`)에 정상적으로 바이너리가 저장됨.

## 🧐 최종 검증 항목
- 모든 테스트 단계에서 HTTP 상태 코드가 `500 Internal Server Error`가 아님을 확인
- 백엔드 터미널에 에러 트레이스가 찍히지 않음
- 데이터 생성, 상태 전이, 파일 생성 등이 명세대로 정확히 떨어짐
