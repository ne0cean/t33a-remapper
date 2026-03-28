# Claude Code Specific Rules
# Claude Code(CLI) 환경에 최적화된 거버넌스 레이어
# 이 파일은 vibe-toolkit의 Claude Code 확장 실험 파일입니다.
# 검증된 패턴은 toolkit-improvements/에 기록 후 vibe-toolkit으로 역업로드됩니다.

## 1. Memory System (Claude Code 전용)
- 프로젝트 메모리: `memory/MEMORY.md` (매 대화 자동 로드)
- 상세 레퍼런스: `memory/` 하위 토픽별 파일
- 세션 간 컨텍스트 보존은 `.context/CURRENT.md` + `memory/MEMORY.md` 이중 관리
- 신규 패턴 발견 시 즉시 memory 업데이트, 나중에 몰아서 하지 않기

## 2. Context Management
- Claude Code는 대화 압축이 발생함 → 핵심 상태는 항상 CURRENT.md에 외부화
- 긴 탐색 작업은 Explore 서브에이전트 위임 (메인 컨텍스트 보호)
- 독립 작업은 병렬 툴 호출로 처리 (속도 최적화)

## 3. Tool Usage Priority
우선순위 (높음 → 낮음):
1. 전용 도구: Read, Edit, Write, Glob, Grep
2. Agent (서브에이전트): 복잡한 탐색/멀티스텝
3. Bash: 전용 도구로 불가능한 시스템 명령만

## 4. 서브에이전트 활용 패턴
- `Explore` 에이전트: 코드베이스 탐색, 키워드 검색
- `Plan` 에이전트: 구현 전략 설계
- `general-purpose` 에이전트: 복합 멀티스텝 작업
- 에이전트 결과는 메인 컨텍스트로 요약해서 가져오기

## 5. Commit Convention (Claude Code 환경)
- HEREDOC 방식으로 커밋 메시지 작성 (줄바꿈 안전)
- Co-Authored-By 태그 항상 포함
- --no-verify, --force는 사용자 명시 요청 시에만

## 6. 개선사항 발견 시
- `toolkit-improvements/` 에 즉시 기록
- 형식: 문제 상황 → 발견한 패턴 → 적용 결과
- 충분히 검증된 패턴은 vibe-toolkit에 PR/업로드 제안
