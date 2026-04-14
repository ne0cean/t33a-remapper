# Current Status

## 📌 프로젝트 1줄
T33A BLE 리모컨 → 말해보카 앱 키 리매퍼. **PC 없이 standalone 영구 동작 목표**.

→ 상세/경로표/진단순서: [CLAUDE.md](../CLAUDE.md) 필독
→ 함정 금지목록: [lessons/16](../lessons/16-android-ble-input-remapping.md) 교훈 6~9

## 🎯 완료
- 데몬 (EVIOCGRAB + uinput, supervisor+worker, PPID=1 생존)
- relay (데몬 watchdog 5s + cmd 감시 1s)
- boot.sh (Termux:Boot 자동 시작 + ADB loopback + 자체 설치)
- start.sh (위젯 invoke, fast path 1초)
- 위젯 원샷 리셋 스크립트 (`scripts/t33a_widget_reset.sh`)
- CRLF 트랩 방지 (`.gitattributes eol=lf`)
- 이중 fork 생존 패턴 (ADB 분리에도 생존)

## 🛠 Working On
(없음)

## ⏩ Next Tasks
1. **확정 필요**: `~/.termux/boot/t33a_boot.sh` 설치 여부 (ADB 경로 전부 차단, Termux에서 `ls ~/.termux/boot/`로만 확인 가능)
2. 재부팅 실시험 3회 → 자동 시작 여부 검증
3. (선택) 데몬 장기 생존 모니터링 — 1일 경과 시 Samsung kill 여부

## 🚧 Blockers
- `~/.termux/boot/` 및 `~/.shortcuts/` 접근/수정은 **Android 14+ 데이터 격리로 ADB 완전 차단**. Termux 내부 실행 필수. 이것 때문에 Claude가 ADB로 진단 시도하다가 방향 잃는 패턴 반복 → CLAUDE.md에 영구 박아둠.

## 📝 Recent Activity
- **2026-04-14**: 레포 + 폰 대청소. scripts/ 3개만 남김(+widget_reset 신규), `.research/` 삭제, 폰 junk 파일 전부 제거. CLAUDE.md 경로표+진단체크리스트로 재작성. README 간결화. 근본 원인 5종 정리 완료(CRLF/이중fork/SELinux/Termux-write-불가/위젯 shortcut 깨짐). 위젯 원샷 리셋 스크립트 신설. 여전히 미확정: Termux:Boot 자동 시작 실제 fire 여부.
- **2026-04-13**: fast path 16초→1초 개선 (cmd 소비 판정). CMD 파일 /data/local/tmp → /sdcard. 이중 fork PPID=1. WiFi ADB 자동 활성화. 근본 버그 4종 수정+푸시.
- **2026-04-07**: KEY_H 미동작 해결 — `tap` 매핑 도입.
- **2026-04-05**: relay 구조 도입. termux-wake-lock. 위젯 fast path.
- **2026-03-28**: 초기 구현 완료.
