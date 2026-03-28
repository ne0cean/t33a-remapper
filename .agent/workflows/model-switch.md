---
description: 모델 사용량 소진 시 다른 AI 모델로 맥락 유실 없이 교체 (자동화 버전)
---

# 🔄 Model Switch (One-Click Handoff)

이 워크플로우는 현재 모델의 한도가 다 되었을 때 터미널 명령어 한 줄로 모든 맥락을 새 AI로 옮깁니다.

## 1. 지휘 및 실행 (One-Click)
에이전트에게 다음을 실행하도록 지시하거나 직접 터미널에서 실행하세요:
// turbo
```bash
./scripts/model-exit.sh
```

**자동 실행 내용:**
1. 현재 작업 내용 최종 Git 커밋
2. 최신 맥락 압축 (`HANDOFF_PROMPT.txt` 생성)
3. **새 AI용 프롬프트 클립보드 자동 복사**
4. macOS 알림 발송

## 2. 새 AI에서 재개
1. 새로운 AI(Claude, GPT, CLI 등)를 켭니다.
2. 대화창에 **Cmd+V (붙여넣기)** 하고 전송합니다.
3. 새 AI가 이전 맥락을 이어받아 작업을 즉시 재개합니다.
