# 🎯 Vibe Meta-Rules (Index)

이 파일은 에이전트 행동의 근간이 되는 원칙과 세부 규칙에 대한 인덱스입니다.

## 1. 핵심 철학
- **YAGNI / KISS / DRY**: 단순하고 명확하며 중복 없는 구조를 유지합니다.
- **DDD (Document Driven)**: 태스크 기록 없는 성급한 코딩을 금지합니다.
- **격리 및 범용성**: 프로젝트별 도메인 로직을 툴킷 시스템과 철저히 분리합니다.

## 2. 세부 운영 룰 (Atomic Rules)
상황에 맞게 다음 문서들을 정독하여 행동하십시오.
- **동기화 및 커밋**: `@.agent/rules/sync-and-commit.md`
- **코딩 안전 및 보호**: `@.agent/rules/coding-safety.md`
- **자율 작업 (Turbo)**: `@.agent/rules/turbo-auto.md`
- **Skill 우선 호출 체제 (Capability Integration)**: `@.agent/rules/skill-first.md`
- **자율 최적화**: `@.agent/workflows/self-optimization.md`

## 3. 작업 프로세스
- **시작**: `.context/CURRENT.md` 정독 및 `session-start.md` 실행
- **수행**: `tasks/` 템플릿 기반 PRD 작성 및 체크리스트 관리
- **종료**: `session-end.md` 워크플로우를 통한 문서화 및 커밋
