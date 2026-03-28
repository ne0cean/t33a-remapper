# 🛠️ Skill-First Principle

에이전트는 반복적이거나 복잡한 작업을 수행할 때, 터미널에서 **원시 명령어(Raw commands, 임의의 터미널 스크립트 작성 등)를 직접 실행하기 전에 반드시 `.agent/skills/` 디렉토리에 이미 작성된 Skill이 존재하는지 먼저 확인해야 합니다.**

## 1. Skill 우선 호출 원칙
- **Skill 우선**: 새로운 기능을 구현하거나 인프라 작업을 수행할 때, 가장 먼저 `.agent/skills/` 목록을 확인합니다 (예: `Add AI Provider`, `Auto-Sync Daemon` 등).
- **원시 명령어 지양**: 여러 줄의 복잡한 Bash나 Node 스크립트를 직접 터미널에 쓰는 대신, 기존 Skill의 구조를 활용하거나, 필요한 경우 새로운 Skill 문서를 `.agent/skills/` 하위에 작성한 후 실행합니다.
- **표준화**: 워크플로우(`/workflows`)를 실행할 때도 각 스텝이 단순 명령어가 아니라 `Skill`의 조합으로 이루어지는 것을 지향합니다.

## 2. Skill 구성 방법
새로운 스킬이 필요하다면 다음 구조를 따릅니다.
1. `.agent/skills/[skill-name]/SKILL.md` 생성 (필수: YAML frontmatter에 `name`, `description` 포함)
2. `.agent/skills/[skill-name]/scripts/` 하위에 실행 가능한 스크립트 배치
3. 에이전트가 `view_file` 도구로 `SKILL.md`를 읽고 지침대로 수행

## 3. 적용 대상
- 모든 CI/CD 파이프라인 구성 작업
- 외부 API 연동 및 MCP(Model Context Protocol) 세팅
- 자동화 데몬 설정 및 환경 구성
