# Current Status (remote-H)

## 📌 One-Line Summary
T33A BLE 리모컨 키 리매퍼 완성 — EVIOCGRAB 커널 데몬 + Termux:Boot/Widget 자동 시작

## 🎯 Current Goals
- [x] Initialize `.agent/` structure <!-- id: 0 -->
- [x] Initialize `.context/` structure <!-- id: 1 -->
- [x] Initialize `tasks/` and `lessons/` <!-- id: 2 -->
- [x] Set up `CLAUDE.md` entry point <!-- id: 3 -->
- [x] T33A 리모컨 키 매핑 문제 분석 (KEY_POWER→화면 끄기) <!-- id: 5 -->
- [x] EVIOCGRAB + uinput C 데몬 작성 및 배포 <!-- id: 6 -->
- [x] 데몬 v2: daemonize + BLE 자동 재연결 <!-- id: 7 -->
- [x] Termux:Boot/Widget 자동 시작 스크립트 <!-- id: 8 -->
- [x] GitHub 레포 생성 및 푸시 <!-- id: 9 -->

## 🛠 Working On
- (없음)

## ⏩ Next Actions
- [ ] watchdog 알림(termux-notification) 연동 완성 — Termux에서 cron 또는 상주 프로세스로 실행 필요 <!-- id: 13 -->
- [ ] Termux:Boot boot 스크립트에 watchdog 루프 통합 테스트 (재부팅 후) <!-- id: 14 -->
- [ ] 리매핑 테이블 커스터마이즈 기능 (config 파일 방식) <!-- id: 11 -->

## 📝 Recent Activity
- **2026-04-01**: Supervisor 패턴 도입 (worker 크래시 자동 재시작), SIGHUP/SIGPIPE 무시, 상태 로깅 (t33a.status + t33a.log), 반응 속도 개선 (sleep 2s→0.5s/0.2s), show_ime_with_hard_keyboard=1 설정으로 키보드 복구, watchdog 스크립트 작성 (알림 미완)
- **2026-03-29**: uinput 디바이스 분류 수정 (GAMEPAD→KEYBOARD|TOUCH|EXTERNAL). IME 복원 (MoAKey→Honeyboard). zig cc 크로스 컴파일 도입. 말해보카 앱에서 3개 키 정상 동작 확인.
- **2026-03-28**: T33A 리매퍼 전체 구현 완료. EVIOCGRAB C 데몬, Termux:Boot/Widget 스크립트, GitHub 레포 (ne0cean/t33a-remapper) 생성.
