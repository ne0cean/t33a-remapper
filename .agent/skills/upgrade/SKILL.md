---
name: Toolkit Upgrade
description: 현재 프로젝트의 vibe-toolkit 인프라를 최신 버전으로 업데이트합니다.
---

# Toolkit Upgrade Skill

이 스킬은 현재 프로젝트에 설치된 `.agent/`, `scripts/` 등 시스템 파일을 최신 버전의 `vibe-toolkit`으로 교체합니다.

## 사용 방법
에이전트에게 다음과 같이 요청하세요:
- "툴킷을 최신 버전으로 업그레이드해줘"
- "vibe-toolkit 업데이트 진행해"

## 동작 원리
에이전트는 내부적으로 다음 명령을 실행합니다:
```bash
curl -sSL https://raw.githubusercontent.com/ne0cean/vibe-toolkit/main/upgrade.sh | bash
```

## 주의 사항
- 업그레이드 시 `.agent/rules` 및 `workflows`는 최신 표준으로 덮어씌워집니다.
- 프로젝트 고유의 컨텍스트(`.context/`)는 안전하게 보존됩니다.
