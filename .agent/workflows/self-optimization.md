---
description: 프로젝트 구조 점검 및 안전한 최적화 자동 수행
---

# 🛠️ Self-Optimization (Project Health Check)

이 워크플로우는 프로젝트의 구조적 결함을 찾아내고, 코드 품질을 향상시킬 수 있는 안전한 최적화를 수행합니다.

## 1. 구조 부분 분석 (Scanning)
// turbo
1. 프로젝트의 핵심 파일(`main.py`, `App.js` 등)의 라인 수와 복잡도를 확인합니다.
2. 중복된 코드 패턴이나 비효율적인 import 체인을 식별합니다.
3. `.context/ARCHITECTURE.md`와 실제 코드 구조 사이의 괴리를 찾아냅니다.

## 2. 자율 품질 분석 (MCP Orchestration)
1. 현재 연결된 테스트 전용 MCP 서버(예: `TestSprite` 등)의 기능을 호출할 수 있는지 검토합니다.
2. 가능하다면, MCP의 `generate_code_summary` 혹은 관련 툴을 호출해 코드베이스 취약점을 객관적으로 도출합니다.
3. 테스트 코드가 부족하다면 도출된 분석을 바탕으로 테스트 계획(Test Plan)을 생성하거나 권장 사항으로 기록해둡니다.

## 2. 안전 최적화 (Safe Tuning)
다음 조건에 부합하는 항목만 **에이전트 판단 하에 자율적으로** 수정합니다:
- **Linting & Formatting**: 코드 스타일 통일.
- **Dead Code 제거**: 사용되지 않는 import, 주석 처리된 구식 코드 삭제.
- **Type Hinting**: (Python의 경우) 타입 힌트 추가로 코드 가독성 향상.
- **Small Refactoring**: 100행이 넘는 함수를 의미 있는 단위로 분리 (KISS 원칙).

## 3. 검증 및 확정
// turbo
1. 수정된 코드에 대해 `npm run build` 혹은 정적 분석 도구를 실행하여 무결성을 확인합니다.
2. 검증에 실패할 경우 즉시 변경 사항을 되돌립니다(`git checkout .`).
3. 성공할 경우 최적화 내역을 `.context/SESSIONS.md`에 기록하고 다음 이정표로 삼습니다.
