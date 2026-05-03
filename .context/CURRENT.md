# Current Status

## 📌 프로젝트 1줄
T33A BLE 리모컨 → 말해보카 앱 키 리매퍼. **PC 없이 standalone 영구 동작 목표**.

→ 상세/경로표/진단순서: [CLAUDE.md](../CLAUDE.md) 필독
→ 함정 금지목록: [lessons/16](../lessons/16-android-ble-input-remapping.md) 교훈 6~9

## 🎯 완료
- 데몬 (EVIOCGRAB + uinput, supervisor+worker, PPID=1 생존)
- relay (데몬 watchdog 5s + cmd 감시 1s + heartbeat staleness 감지 + postmortem 캡처)
- boot.sh (Termux:Boot 자동 시작 + ADB loopback + 자체 설치 + deeplink 알림)
- start.sh (위젯 invoke, fast path 1초 + heartbeat 검증 + deeplink 알림)
- 위젯 원샷 리셋 스크립트 (`scripts/t33a_widget_reset.sh`)
- CRLF 트랩 방지 (`.gitattributes eol=lf`)
- **무선 배포 파이프라인** (USB 없이 git push → 폰 5분 내 자동 반영)
  - `t33a_auto_pull.sh`: 5분마다 GitHub fetch, 새 커밋 시 자동 update
  - `t33a_update.sh`: git pull → src변경 시 clang빌드, scripts변경 시 /sdcard갱신
  - `t33a_setup_phone.sh`: 폰 최초 설치 원클릭 (git clone + clang + 위젯 + 초기빌드)
- 이중 fork 생존 패턴 (ADB 분리에도 생존)
- **진단 인프라**: 60초 heartbeat (worker select 기반), find_device 실패 명시 로깅, postmortem 캡처(logcat/dmesg/메모리/input devices), start.sh 응답 검증

## 🛠 Working On
- 없음 — 정상 동작 중. 3버튼 모두 확인 (1번/Enter/H)

## ⏩ Next Tasks
1. **[필수] 폰 최초 설정** — 아직 `~/t33a-remapper` 클론이 없음. Termux에서:
   ```
   bash /sdcard/Download/t33a_setup_phone.sh
   ```
   이 스크립트가 git clone + clang 설치 + 위젯 숏컷 + 초기 빌드까지 자동 처리.
2. **[자동] 이후 배포 방법** — Mac/폰 Claude Remote에서 코드 수정 → `git push` → 폰 auto_pull이 5분 내 감지 → `t33a_update.sh` 자동 실행. 즉시 반영하려면 `T33A_Update` 위젯 탭.
3. **배터리 50% 이하 테스트** — 충전 없이 배터리 낮춘 후 화면 꺼짐 상태에서 버튼 동작 확인. t33a.log에서 `low_power=1` 전환 시점과 BLE 끊김 타임스탬프 대조
4. **재부팅 실시험** — Termux:Boot → boot.sh → ADB localhost:5555 → relay → daemon 자동 복구 체인 검증. Samsung 무선 디버깅 토글 1회 필요 (deeplink 알림이 안내)
5. **boot.sh 구버전 교체** — 현재 PID 21579 (구버전, ADB 의존 watchdog) 실행 중. 다음 재부팅 시 자동 교체됨. 즉시 교체하려면 폰 Termux에서 `kill 21579; setsid bash /sdcard/Download/t33a_boot.sh &`

## 🚧 Blockers
- `~/.termux/boot/` 및 `~/.shortcuts/` 접근/수정은 **Android 14+ 데이터 격리로 ADB 완전 차단**. Termux 내부 실행 필수.
- **Samsung 절전 모드 (Power Save)**: 배터리 50% 미만 시 블루투스/백그라운드 입력 제한 가능성. `low_power=0` 설정 및 배터리 최적화 해제 필수.
- **USB 세션 종속성**: PC에서 `adb shell`로 띄운 프로세스는 선 뽑으면 죽음. **반드시 폰 내부(Termux/Widget)에서 띄워야 독립 생존 가능**.

## 🎓 이번 세션에서 확정된 판단 (다시 안 돌아갈 것)

1. **Termux:Boot은 정상 작동** — Samsung이 8분 지연시킬 뿐. 과거에 "차단됨"으로 잘못 판단하고 시간 낭비했음. [lessons/16 교훈 10](../lessons/16-android-ble-input-remapping.md#교훈-10-samsung-termuxboot은-차단이-아니라-8분-지연-)
2. **WiFi ADB standalone은 Samsung에서 실질적으로 불가** — 페어링해도 TLS listener 지속 안 됨. 파지 말 것. [lessons/16 교훈 14](../lessons/16-android-ble-input-remapping.md#교훈-14-samsung-wifi-adb-tls은-지속-listening-안-함--페어링해도-쓸모-없음)
3. **Termux 유저는 `settings put global` 불가** — INTERACT_ACROSS_USERS 없음. boot.sh에서 값 반영 안 됨을 인정. [lessons/16 교훈 11](../lessons/16-android-ble-input-remapping.md#교훈-11-termuxu0_a533에서-settings-put-global-불가--interact_across_users-필요)
4. **Termux 내부 작업은 A-Team termux-ctrl-agent로** — ADB 직접 시도 절대 금지. [A-Team SKILL](file:///C:/Users/SKTelecom/tools/A-Team/governance/skills/termux-remote/SKILL.md)
5. **완전 standalone 대신 "재부팅 후 위젯 탭 1회"** 전략 채택 — boot.sh retry loop + wake-lock으로 사용자가 위젯 탭하는 순간 자동 복구. [lessons/16 교훈 15](../lessons/16-android-ble-input-remapping.md#교훈-15-bootsh는-절대-fatal-exit-하지-말-것--retry-loop으로-대체)
6. **WiFi ADB listener 부활은 코드로 불가** — 사용자가 무선 디버깅 토글 1회 직접 만져야 함. boot.sh/start.sh가 deeplink 알림으로 이 1회를 안내. [lessons/16 교훈 16](../lessons/16-android-ble-input-remapping.md#교훈-16-wifi-adb-listener-부활은-코드로-불가--deeplink-알림으로-1회-토글-유도)
7. **t33a_remap은 반드시 shell 유저로 실행** — `/dev/input` = `system:input rw-rw----`, `/dev/uinput` = `uhid:uhid rw-rw----`. Termux 유저(u0_a533)는 input/uhid 그룹 미소속. ADB shell(uid=2000)만 가능. **"ADB 의존 제거"는 물리적으로 불가능**.
8. **Termux 유저는 shell 유저의 `/proc/PID`를 볼 수 없음** — `boot.sh` watchdog에서 PID 존재 확인 시 `/proc` 대신 heartbeat 파일(`t33a.heartbeat`)의 수정 시간을 사용해야 함.

## 📝 Recent Activity
- **2026-05-03 (01:30 KST)**: **무선 배포 파이프라인 구축** — 이제부터 USB 없이 배포 가능. (1) `t33a_update.sh` 개선: git pull → 변경된 파일만 빌드/배포, text file busy 방지, heartbeat 상태 출력. (2) `t33a_auto_pull.sh` 신규: 5분마다 GitHub fetch → 새 커밋 감지 시 자동 update. (3) `t33a_boot.sh`에 auto_pull 백그라운드 시작 통합. (4) `t33a_setup_phone.sh` 개선: 패키지 설치+클론+빌드+위젯까지 원클릭. 이제 흐름: Claude Remote에서 코드 수정 → git push → 폰이 5분 내 자동 반영.
- **2026-05-03 (01:00 KST)**: **배터리/절전 상태 로그 셋업 + relay dead 루프 픽스**. (1) relay.sh에 5분마다 배터리%, low_power, heartbeat 상태 기록 추가 — 절전 모드 전환 시점 추적 가능. (2) t33a_remap.c에 BLE 재연결 소요시간 로그 추가 (disconnected→reconnected Ns). (3) relay가 PID를 `/sdcard/Download/`와 `/data/local/tmp/` 두 곳에 기록 — 구버전 boot.sh watchdog이 `/data/local/tmp`만 보던 문제로 36초마다 "relay dead" 루프 발생했던 것 완전 해결. 3버튼 동작 최종 확인 (1번/Enter/H).
- **2026-05-03 (00:20 KST)**: **폰 독립 실행(Standalone) 및 1번 버튼 미작동 해결**.
  - **원인 1**: Samsung 절전 모드(`low_power=1`)가 BLE 입력을 차단함. `low_power=0`으로 해결.
  - **원인 2**: `boot.sh`의 relay 감시 로직 결함. Termux 유저가 shell 유저의 `/proc/PID`를 볼 수 없어 항상 "죽음"으로 오판 → PC 연결 없이는 재기동 실패. heartbeat 파일 나이(`stat -c %Y`) 기반으로 감시 로직 수정.
  - **원인 3**: PC에서 실행한 ADB 세션은 선 뽑으면 함께 종료됨. `setsid`를 폰 내부(Termux `boot.sh`/`start.sh`)에서 호출해야만 선과 무관하게 독립 생존함.
  - **데몬 업데이트**: 디버깅을 위해 모든 키 입력을 `t33a.log`에 남기는 verbose 모드 빌드/배포. 더블클릭 딜레이 100ms → 120ms 상향.
- **2026-05-02 (오전 3차)**: **ADB 의존 제거 리팩토링 롤백**. 다른 에이전트가 수행한 commit 1fea4c4 "ADB 의존 완전 제거"가 근본 원인. t33a_remap을 Termux 유저(u0_a533)로 직접 실행 → /dev/input 권한 없어 find_device() 영원히 실패 → boot.sh watchdog이 10초마다 재시작 → 좀비 30개 누적. 스크립트를 c75e6d6(boot/start) + 61aa481(relay) 버전으로 복원. ADB push로 폰에 직접 배포. shell 유저로 데몬(PID 5615) + relay(PID 5828) 정상 가동 확인.
- **2026-05-02 (오전 2차)**: **진단 인프라 4종 추가** — 사용자 지적("재부팅 안 했는데 미작동")으로 분석 재출발. (1) worker read 루프를 `select()` 60초 타임아웃 기반으로 바꾸고 heartbeat 파일(`/data/local/tmp/t33a.heartbeat`) 매분 갱신 — 데몬 hung 상태 명시 감지 가능. (2) find_device 실패 시 명시 로깅 (5분 throttle) — "T33A 안 보임" 사각지대 제거. (3) relay에 postmortem 캡처 추가 — 데몬 dead/hung/manual 시 logcat·dmesg·메모리·input devices·heartbeat·process tree를 `/sdcard/Download/t33a_postmortem_<TS>_<reason>.log` 별도 파일로 보존. (4) start.sh fast path가 heartbeat mtime + status 파일까지 검증해 위젯 반응 신뢰성 보장. 즉시 검증 결과: postmortem이 BLE peripheral 미가시 + bluetooth pause/resume cycle을 정확히 캡처 → 다음 사건 발생 시 진범 확실 식별 가능.
- **2026-05-02**: 어제 1시10분(13:12 KST) 위젯 5번 탭 무반응 사건 완전 진단 + 픽스. 원인 = 04-30 재부팅 후 Samsung WiFi ADB listener 사망 → boot.sh의 `settings put global adb_wifi_enabled 1` 호출이 Termux 권한 부족으로 silent 실패 → 24h 동안 retry loop이 영원히 connect refused → 위젯도 같은 ADB 의존이라 동일 실패. 픽스: (1) 헛된 `settings put` 호출 boot.sh/start.sh에서 제거 (2) ADB 실패 시 `termux-notification` deeplink 알림으로 사용자 무선 디버깅 토글 OFF→ON 안내 (3) 60초 쿨다운 dedupe (4) 토글 후 retry loop 다음 사이클에 자동 복구. lessons/16 교훈 16 추가, 진단 체크리스트 갱신.
- **2026-04-14 (후반)**: 재부팅 실시험 + A-Team Termux Control Agent 구축 + 함정 6종 영구 박음. (1) Termux:Boot 실제 8분 지연으로 발화 확인 (차단 아님). (2) ~/.termux/boot/ 직접 R/W는 A-Team termux-ctrl-agent IPC 통해 가능해짐 (Android 14+ 격리 우회). (3) WiFi ADB TLS 페어링 시도했으나 Samsung이 listener 지속 안 함 — 시간 낭비 확정. (4) boot.sh FATAL → retry loop 교체. (5) termux-toast timeout 3 래핑 (2시간+ stuck 해결). (6) agent bash `$()` capture block 버그 수정. lessons/16에 교훈 10~15 추가 + 진단 체크리스트 + CLAUDE.md 함정 테이블. 글로벌 메모리 `feedback_android_termux_traps.md` 저장.
- **2026-04-14 (전반)**: 레포 + 폰 대청소. scripts/ 3개만 남김(+widget_reset 신규), `.research/` 삭제, 폰 junk 파일 전부 제거. CLAUDE.md 경로표+진단체크리스트로 재작성. README 간결화. 근본 원인 5종 정리 완료(CRLF/이중fork/SELinux/Termux-write-불가/위젯 shortcut 깨짐). 위젯 원샷 리셋 스크립트 신설.
- **2026-04-13**: fast path 16초→1초 개선 (cmd 소비 판정). CMD 파일 /data/local/tmp → /sdcard. 이중 fork PPID=1. WiFi ADB 자동 활성화. 근본 버그 4종 수정+푸시.
- **2026-04-07**: KEY_H 미동작 해결 — `tap` 매핑 도입.
- **2026-04-05**: relay 구조 도입. termux-wake-lock. 위젯 fast path.
- **2026-03-28**: 초기 구현 완료.
