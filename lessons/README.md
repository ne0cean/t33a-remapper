# 🧠 프로젝트 교훈 (Lessons Learned)

여러 프로젝트를 운영하며 발견한 구조적 결함과 해결 패턴을 정리한 문서입니다.

**핵심 원칙**: 새 레슨이 기존 레슨을 대체하면, 기존 파일을 업데이트한다. 같은 주제의 파일을 추가로 생성하지 않는다.

---

## 자동 열람 규칙 (에이전트 필독)

**새 기능 설계 전**, **버그 픽싱 전**, **세션 시작 시** 아래 흐름을 따른다:

1. 이 README의 **태스크 매핑** 섹션에서 현재 작업 유형을 찾는다
2. 해당 레슨 파일을 열람한다
3. 체크리스트를 적용 계획에 반영한다

---

## 문서 목록

| # | 파일 | 주제 | 핵심 교훈 | 최종 업데이트 |
|---|---|---|---|---|
| 1 | [01-data-resilience.md](01-data-resilience.md) | 외부 API 의존성과 데이터 회복력 | 실패는 기본값이 아니라 마지막 성공값으로 대응하라 | AI Bubble Dashboard |
| 2 | [02-deployment-verification.md](02-deployment-verification.md) | 배포 후 검증 자동화 | 배포했으면 증명하라 — /api/health 패턴 | AI Bubble Dashboard |
| 3 | [03-browser-defense.md](03-browser-defense.md) | 브라우저 확장 프로그램 방어 | 다크 테마 앱은 Dark Reader와 싸운다 | AI Bubble Dashboard |
| 4 | [04-dynamic-infrastructure.md](04-dynamic-infrastructure.md) | 동적 인프라와 URL 동기화 | 주소가 바뀌면 모든 소비자에게 알려야 한다 | AI Bubble Dashboard |
| 5 | [05-multi-agent-handoff.md](05-multi-agent-handoff.md) | 멀티 에이전트 협업 구조 | 다른 AI가 이어받을 수 있는 프로젝트를 만들어라 | 2026-03-15 (Antigravity 패턴 추가) |
| 6 | [06-sse-pipeline.md](06-sse-pipeline.md) | SSE 기반 멀티스텝 파이프라인 | 장시간 AI 작업은 SSE 스트리밍으로 우아하게 처리하라 | AI Bubble Dashboard |
| 7 | [07-provider-state-machine.md](07-provider-state-machine.md) | Provider 추상화 & 상태 머신 | 외부 API 교체와 예외적 흐름을 안전하게 디자인하라 | AI Bubble Dashboard |
| 8 | [08-claude-code-agent-layer.md](08-claude-code-agent-layer.md) | Claude Code AI 에이전트 레이어 | memory/, hooks, 슬래시 명령어, Research Mode를 조합하라 | 2026-03-15 (connectome) |
| 9 | [09-component-discipline.md](09-component-discipline.md) | 컴포넌트 규율 | 파일 크기·import 위치·저장소 위생을 지켜라 | 2026-03-15 (connectome) |
| 10 | [10-mobile-touch-ux.md](10-mobile-touch-ux.md) | 모바일 터치 UX | onMouseLeave 함정, 44px 터치 타겟, 핀치 줌 충돌 방어 | 2026-03-16 (connectome) |
| 11 | [11-realtime-websocket-architecture.md](11-realtime-websocket-architecture.md) | 실시간 WebSocket + In-Memory | IP룸, 퍼센트 좌표, 이벤트 설계, 보안, 확장성 한계 | 2026-03-16 (connectome) |
| 15 | [15-multi-agent-orchestration.md](15-multi-agent-orchestration.md) | 멀티 에이전트 오케스트레이션 | TAO루프, Supervisor/Swarm/Hierarchical, 입출력 스키마, 운영 전략 3종 | 2026-03-20 (A-Team) |
| 16 | [16-android-ble-input-remapping.md](16-android-ble-input-remapping.md) | Android BLE 입력 디바이스 리매핑 | EVIOCGRAB 독점, evdev→uinput 파이프라인, ADB WiFi 불안정성, 비루팅 한계 | 2026-03-28 (remote-H) |

---

## 태스크 매핑 (작업 전 읽을 레슨)

### 새 기능 설계 / PRD 작성 전
- **05** — 멀티 에이전트 협업 (팀이 있거나 AI가 교대로 작업하는 경우)
- **15** — 멀티 에이전트 오케스트레이션 (에이전트 2명 이상 병렬 투입 시)
- **09** — 컴포넌트 규율 (새 컴포넌트 추가 시)
- **07** — Provider 상태 머신 (외부 API 연동 기능인 경우)

### 버그 픽싱 전
- **01** — 외부 API 실패 관련이면 Persistent Cache 패턴 확인
- **03** — 스타일/렌더링 이상이면 브라우저 확장 방어 확인
- **04** — URL/환경변수 관련이면 동적 인프라 동기화 확인
- **09** — 파일이 너무 커서 이해하기 어렵다면 컴포넌트 분리 먼저

### 배포 전
- **02** — 배포 검증 자동화 (/health 엔드포인트 + CI 체크)
- **09** — 저장소 위생 점검 (.gitignore, 실험 파일 정리)

### Claude Code 프로젝트 초기 설정 시
- **08** — Claude Code 에이전트 레이어 (memory, hooks, 슬래시 명령어)
- **05** — 멀티 에이전트 핸드오프 구조

### 실시간/WebSocket 기능 개발 시
- **11** — WebSocket + In-Memory 아키텍처 (이벤트 설계, 보안, 확장성 한계)
- **06** — SSE 파이프라인 (단방향 스트리밍이면)
- **10** — 모바일 터치 UX (실시간 앱은 모바일 지원 가능성 높음)
- **01** — 연결 끊김 시 Fallback 전략

### 모바일 지원 기능 개발 시
- **10** — 터치 UX (onMouseLeave 함정, 터치 타겟, 핀치 줌)

### Android 디바이스 제어 / 입력 리매핑 시
- **16** — BLE 입력 리매핑 (EVIOCGRAB, evdev→uinput, ADB WiFi, 비루팅 우회)

---

## 레슨 업데이트 기준

새 프로젝트에서 동일한 주제를 다시 겪었을 때:
- **같은 결론** → 기존 파일에 "적용 사례" 추가
- **더 나은 해법 발견** → 기존 파일 업데이트 + `최종 업데이트` 날짜 갱신
- **완전히 다른 도메인** → 새 번호로 파일 추가 + 이 README 업데이트

**절대 하지 말 것**: 같은 주제의 파일을 `10-data-resilience-v2.md` 식으로 중복 생성.

---

## 대상 프로젝트 유형
- FastAPI / Express 백엔드 + React 프론트엔드
- 외부 API(주식, 날씨, LLM 등) 의존 대시보드
- 실시간 WebSocket/SSE 통신 앱
- Claude Code CLI를 사용하는 AI-assisted 개발 프로젝트
- 여러 AI 에이전트가 교대로 작업하는 프로젝트
