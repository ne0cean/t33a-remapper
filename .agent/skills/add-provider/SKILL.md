---
name: Add AI Provider
description: 새로운 외부 API/AI 서비스 프로바이더 추가
---

## 🛠 필수 변경 파일
새로운 프로바이더(결제, 외부 API, LLM, TTS 등)를 추가할 때 수정해야 할 체크리스트입니다.

1. `providers/{domain}/{name}_provider.py` — 베이스 추상 클래스 상속 및 구현
2. `config.py` — 새로운 API 키 환경변수(Pydantic Field)와 활성화(available) 조건 추가
3. `.env.example` — 추가한 API 키 환경변수 템플릿 추가
4. `routers/{domain}.py` 또는 프로바이더 팩토리 함수 — `_get_providers()` 딕셔너리에 새 객체 등록
5. `providers/{domain}/__init__.py` — 패키지 export (`__all__` 등록)

## 💻 구현 순서
1. **인터페이스 확인**: `providers/{domain}/base.py` 의 추상 메서드(abstract method) 스펙을 확인합니다.
2. **구현체 작성**: 위 스펙에 맞춰 `generate()`, `is_available()`, `name()` 프로퍼티 등을 가진 구체 프로바이더를 작성합니다.
3. **설정 연동**: `config.py`에 API Key를 Optional로 받고, Key가 없으면 `is_available()`를 `False`로 반환하게 만듭니다.
4. **팩토리 등록**: 라우터의 Provider 맵에 등록합니다.
5. **검증**: `add-provider` 작업 완료 후 해당 엔드포인트를 직접 `cURL`로 찔러 정상 여부를 E2E 검증합니다.

## 🚨 주의사항
- `__init__.py`에 모듈 import를 안 하면 FastAPI 시작 시 라우터가 새로 만든 프로바이더를 인지하지 못하는 오류가 잦습니다. (필수 확인)
- 외부 API 키는 하드코딩하지 않고 철저히 `config.py` (env)를 통과시킵니다.
