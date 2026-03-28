# 🏗️ 아키텍처 가이드 (Vibe-Toolkit Trinity)

이 문서는 툴킷, MCP, Skill의 명확한 역할 정의와 협업 모델을 정의합니다. MD(Markdown)의 정적인 지능과 실질적인 실행 능력을 결합하는 것이 핵심입니다.

## 🧩 에이전트 역량 엔진 (Trinity Model)

에이전트는 단순히 문서를 읽는 것을 넘어, 아래 세 가지 축의 조화를 통해 작업을 완수합니다.

| 축 (Axis) | 역할 (Role) | 구성 요소 | 주요 기능 (Function) |
| :--- | :--- | :--- | :--- |
| **Vibe Toolkit** | **지능 & 거버넌스 (Brain)** | Rules, Workflows, Context | 에이전트의 판단 기준, 사고 방식, 작업 연속성 보장 |
| **MCP** | **확장 역량 (Sensors)** | TestSprite, Context7 등 | 웹 검색, 전문 테스트, 최신 문서 조회 등 외부 정보 연결 |
| **Skills** | **실행 기술 (Muscles)** | .agent/skills/*.sh, Prompts | 반복적인 복합 작업(API 추가, 고도화된 배포 등)의 자동화 |

## 🧠 에이전트 협업 원칙
1. **Intelligence (Rules/Workflows)**: "무엇을(What)"과 "왜(Why)"를 결정합니다. 복잡한 명령어를 MD에 나열하지 마십시오.
2. **Capability (Skills)**: "어떻게(How)"를 실행합니다. 반복되거나 복합적인 명령어 셋은 반드시 Skill로 캡슐화하여 호출하십시오.
3. **Expertise (MCP)**: 로컬 파일 시스템을 벗어난 "전문 지식"이나 "외부 연동"이 필요할 때 도구(Tool)로서 활용하십시오.

---

## 📂 주요 디렉토리 구조 (General Template)
```
/
├── .agent/
│   ├── rules/         ← 에이전트 사고 방식 (Brain)
│   ├── workflows/     ← 표준 작업 절차 (Instruction)
│   └── skills/        ← 실행 가능한 행동 (Muscle)
├── .context/          ← 에이전트 장기 기억 (Memory)
├── scripts/           ← 시스템 지원 자동화 도구
└── src/               ← 프로젝트 소스 코드
```
