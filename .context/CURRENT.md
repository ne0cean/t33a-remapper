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
- [ ] Termux:Boot 부팅 시 자동 시작 안정화 (Samsung 배터리 최적화 이슈) <!-- id: 10 -->
- [ ] 리매핑 테이블 커스터마이즈 기능 (config 파일 방식) <!-- id: 11 -->

## 📝 Recent Activity
- **2026-03-28**: T33A 리매퍼 전체 구현 완료. EVIOCGRAB C 데몬, Termux:Boot/Widget 스크립트, GitHub 레포 (ne0cean/t33a-remapper) 생성.
- **2026-03-28**: Key Mapper IME 키보드 먹통 문제 해결 (Samsung Honeyboard로 복구 + IME 비활성화).
