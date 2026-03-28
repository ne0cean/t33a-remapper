---
description: [Turbo] 세션 시작 및 자율 모드 활성화 (One-Stop Start)
---

# 🚀 Vibe Global Start (Autonomous Mode)

이 워크플로우는 세션 시작(`session-start`)과 자율 모드(`turbo-rules`)를 한 번에 실행합니다.

// turbo-all
1. **Context Loading**: `.context/CURRENT.md` 및 `.context/DECISIONS.md`를 정독하여 즉시 맥락을 탑재합니다.
2. **State Analysis**: `git status`와 로그를 분석하여 마지막 중단 지점을 정확히 파악합니다.
3. **Autonomous Activation**: `turbo-auto.md` 규칙을 활성화하여 사용자의 중단 없는 개입 없이 다음 태스크를 즉시 수행합니다.
4. **Immediate Action**: 브리핑을 생략하거나 극도로 축약하고, `CURRENT.md`의 최우선 과제를 바로 실행합니다.
