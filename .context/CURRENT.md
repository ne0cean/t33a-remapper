# Current Status (remote-H)

## 📌 One-Line Summary
T33A BLE 리모컨 키 리매퍼 — Mac zig 크로스 컴파일 + adb 원클릭 배포 + Termux:Widget 원터치 시작

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
- [x] watchdog 알림(termux-notification) 연동 완성 <!-- id: 13 -->
- [x] Termux:Boot boot 스크립트에 watchdog 통합 완료 <!-- id: 14 -->
- [x] 리매핑 테이블 커스터마이즈 기능 (config 파일 방식) <!-- id: 11 -->

## 🛠 Working On
- (없음)

## ⏩ Next Actions
- [ ] 더블클릭 간격 0ms 테스트 (앱 인식 여부 확인) <!-- id: 17 -->
- [ ] README.md 최신화 (zig 크로스 컴파일 + deploy 워크플로우 반영) <!-- id: 16 -->
- [ ] Termux:Boot 부팅 자동 시작 안정화 (Samsung 배터리 최적화) <!-- id: 10 -->
- [ ] SCHED_FIFO root 경로 확인 (Magisk su 위치 파악) <!-- id: 18 -->

## 📝 Recent Activity
- **2026-04-02**: Windows zig 크로스 빌드 환경 구축. KEY_1(홈버튼) 더블클릭 기능 구현 (dbl 플래그, 8ms 간격). 위젯 adb 다중 디바이스 오류 수정 (`-s localhost:$PORT`). SCHED_FIFO 시도 (-O2 빌드). 데몬 상시 구동 확인 및 재시작.
- **2026-04-01**: Mac zig 크로스 컴파일 도입 (brew 우회, 직접 다운로드 ~/tools/). `t33a.sh deploy` 원클릭 빌드+배포+재시작. 폰 Termux:Widget `/sdcard/Download/t33a.sh` 현재 구조 맞게 업데이트 (su 제거, /data/local/tmp 경로). 데몬 정상 확인 (PID 19551).
- **2026-03-29**: uinput 디바이스 분류 수정 (GAMEPAD→KEYBOARD|TOUCH|EXTERNAL). IME 복원 (MoAKey→Honeyboard). zig cc 크로스 컴파일 도입. 말해보카 앱에서 3개 키 정상 동작 확인.
- **2026-03-28**: T33A 리매퍼 전체 구현 완료. EVIOCGRAB C 데몬, Termux:Boot/Widget 스크립트, GitHub 레포 (ne0cean/t33a-remapper) 생성.
