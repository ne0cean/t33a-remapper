# Current Status (remote-H)

## 📌 프로젝트 목적 (READ FIRST)
T33A BLE 리모컨 키를 말해보카 앱에서 사용하도록 커널 레벨 리매핑.

**설계 원칙 (변경 금지)**:
1. **설치 후 PC 연결 불필요** — Termux:Boot가 재부팅 시 자동으로 데몬 기동. 영구 standalone
2. **위젯은 백업** — 자동화가 깨졌을 때 **폰에서만** 원탭 복구 (홈 화면 Termux:Widget)
3. **PC ADB가 필요한 순간 = 설계 실패 상태** — 이 경우 근본 원인 찾아 재발 방지

**아키텍처 (core)**:
```
[재부팅]
  ↓
Termux:Boot → ~/.termux/boot/t33a_boot.sh (Termux 유저)
  ↓
  termux-wake-lock (Samsung kill 방지)
  ↓
  adb connect localhost:$PORT (WiFi ADB loopback으로 shell 유저 컨텍스트 획득)
  ↓
  adb shell → t33a_relay.sh 이중 fork (PPID=1, shell 유저)
  ↓
  relay → t33a_remap (supervisor + worker, shell 유저)
  ↓
  /dev/input/* EVIOCGRAB + /dev/uinput 주입
```

**왜 ADB loopback이 필요한가**: `/dev/input/*`, `/dev/uinput`은 shell 그룹만 접근 가능. Termux 앱 유저(u0_a533)는 shell 그룹 아님. ADB loopback이 shell 유저 bootstrap의 **유일한 경로** (비루팅 환경). 데몬 한 번 기동되면 PPID=1이라 ADB 없어도 생존.

**위젯 동작**: 탭 → ~/.shortcuts/T33A (wrapper) → /data/local/tmp/t33a_start.sh → CMD 파일(/sdcard/Download/t33a.cmd)에 restart → relay가 1초 안에 감지해서 데몬 재시작 (fast path). relay 죽었으면 ADB loopback으로 재기동 (slow path).

## 🎯 Current Goals
- [x] EVIOCGRAB + uinput C 데몬
- [x] Termux:Boot/Widget 자동 시작 스크립트
- [x] watchdog (relay) + termux-wake-lock + Samsung kill 대응
- [x] 리매핑 테이블 커스터마이즈 (t33a.conf)
- [x] CRLF 트랩 영구 방지 (.gitattributes eol=lf)
- [x] 이중 fork로 PPID=1 (USB/ADB 분리 시에도 생존)
- [x] 위젯 fast path 1초 응답 (cmd 파일 소비 판정)
- [x] CMD 파일 /sdcard로 이동 (Termux가 /data/local/tmp에 write 불가)
- [ ] **자동 부팅 신뢰성 검증 — 현재 깨져있음 (아래 Blockers 참조)**

## 🛠 Working On
(없음)

## ⏩ Next Tasks (우선순위 순)
1. **boot.sh가 ~/.termux/boot/에 실제로 설치되어 있는지 확인** — 오늘 재부팅 후 boot.log에 `boot started` 항목 없음. 미설치일 가능성 ≥ 90%. `ls ~/.termux/boot/` 결과 필요 (Termux 안에서)
2. 미설치면 `cp /data/local/tmp/t33a_boot.sh ~/.termux/boot/t33a_boot.sh && chmod +x ...` (Termux 1회)
3. 재부팅 실시험 — boot.log에 `boot started` 찍히는지, 데몬 자동 기동되는지
4. 반복 테스트 3회 — 매번 정상 부팅되면 진짜 standalone

## 🚧 Blockers (현재 자동화 깨진 이유 분석)
**증상**: 2026-04-14 07:07 재부팅 후 boot.log 새 항목 없음. 데몬/relay 전부 사라짐. 위젯 탭하면 slow path에서 1시간 이상 멈춤.

**가장 유력한 근본 원인**:
- `~/.termux/boot/t33a_boot.sh` 미설치 (또는 설치됐으나 실행 권한 없음)
- Claude가 shell 유저로 ADB를 통해 cp 시도한 건 전부 Permission denied로 실패. Termux 안에서만 설치 가능
- 지난 세션에서 boot.sh에 자체 설치 로직 추가했으나, 사용자가 수동 실행 안 했으면 자체 설치도 안 일어남 (boot.sh가 돌아야 자체 설치 로직도 돌아감 → 닭-달걀)

**확정 불가 (검증 필요)**:
- ~/.termux/boot/ 디렉토리 존재 여부 — ADB로 `ls` 시도 시 Permission denied라 확인 불가
- Termux:Boot 앱 자체의 상태 — 정상 설치됐는지, 배터리 최적화 예외 등록됐는지

**Android 14+ 데이터 격리로 ADB로 진단/수정 모두 불가**. Termux 안에서 사용자가 직접 확인해야 함.

## 📝 Recent Activity
- **2026-04-14**: 자동화 깨짐 발견. 재부팅 후 boot.log 새 항목 없음 — boot.sh 자동 실행 안 됨. 원인은 `~/.termux/boot/` 미설치로 추정. 위젯도 slow path에서 무한 대기. USB ADB로 임시 복구 (relay PID 20210). **영구 해결은 Termux 내 boot.sh 수동 설치 필요**. 프로젝트 목적(설치 후 PC 불필요) 재확인 — Claude가 그동안 "USB로 고치기" 방향을 잃고 있었음을 사용자가 지적.
- **2026-04-13**: 데몬 인프라 4종 근본 버그 수정 (WiFi ADB 자동 활성화, CRLF 방지, 이중 fork PPID=1, /proc 권한 우회). 위젯 fast path 16s→1s 개선 (cmd 파일 소비 판정). CMD 파일 /data/local/tmp→/sdcard 이동 (Termux write 권한 차이). 위젯 wrapper ~/.shortcuts/T33A 정상화 — 사용자가 Termux에서 직접 작성해야 했음. 레슨 16에 위젯 진단 STOP 신호 추가.
- **2026-04-07**: KEY_H 미동작 해결 — `tap` 매핑 도입. T33A 파워키 → 화면 좌표 탭.
- **2026-04-05**: relay 구조 도입, termux-wake-lock, 위젯 fast path 최초 구현.
- **2026-04-02**: Windows zig 크로스 빌드, KEY_1 더블클릭, adb -s localhost:$PORT 수정.
- **2026-04-01**: Mac zig 크로스 컴파일, t33a.sh deploy 원클릭.
- **2026-03-29**: uinput 분류 수정 (GAMEPAD→KEYBOARD|TOUCH|EXTERNAL).
- **2026-03-28**: 전체 구현 완료.
