# Current Status

## ✅ REALITY 재정정 (2026-07-10) — WADB Keeper로 "재부팅 후 PC 없이 자동 복구" 달성
2026-06-27 "구조적 불가능" 판정의 전제(Termux가 무선 디버깅 못 켬)가 깨짐. `helper-apk/` **WADB Keeper**(자체 빌드 3.9KB APK, WRITE_SECURE_SETTINGS)가 BOOT_COMPLETED에서 `adb_wifi_enabled=1` → boot.sh loopback 복구 체인 정상 작동. 실기기 e2e PASS(강제 OFF→자동 재활성화). 재부팅 후 사용자 액션 = **잠금해제 1회뿐**. Mac launchd USB 경로는 백업으로 유지. 상세: `helper-apk/README.md`, CLAUDE.md REALITY 섹션.
**🔴 2026-08-01 실제 재부팅에서 실패 확정** — 그 "e2e PASS"는 mDNS `_adb-tls-connect` 재등장만 봤지 **실제 loopback `adb connect`+shell을 한 번도 검증 안 함**. 실재부팅(12:50) 후 무선ADB loopback 미기동 → boot.sh가 relay 못 띄움 → **데몬 7h 사망 → 리모컨 키 인터셉트 안 됨(원래 기능 통과)**. 19:45 무선디버깅 수동 토글로 겨우 복구. 근본원인 3중: ①WADB Keeper는 TLS 플래그만 세팅(boot.sh가 기대하는 classic 5555 아님, TLS는 페어링 필수) ②재부팅 시 adb 인증 리셋('허용' 탭 전 loopback 거부) ③복구 backoff 300s 지연. → **수리 커밋 `daadaed`** (아래 Recent Activity), 폰 배포·실검증 대기.

## 📌 프로젝트 1줄
T33A BLE 리모컨 → 말해보카 앱 키 리매퍼. **standalone + 재부팅 자동 복구(잠금해제 1회)**.

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
- **스픽 앱 탭 매핑** — KEY_VOLUMEDOWN(114) → tap(533, 2032), 작동 확인
- **KEY_VOLUMEUP(115) → tap(555, 769) 매핑 추가** (2026-06-05)
- **boot.sh + start.sh /proc 버그 수정** — watchdog + start_relay() 모두 heartbeat age 기반으로 교체 (Termux→shell /proc 불가 문제)
- **CLAUDE.md 이슈 트리거 테이블 추가** — 상황별 즉시 참조 레슨 + pre-flight 체크리스트
- **standalone 구조 복구 + 워치독 강화** (2026-06-06): relay 항상 TCP loopback(emulator-5554) 경유 시작 확인, relay_hb 추가, boot.sh 워치독 35s 이내 복구, start.sh 위젯에서 boot.sh 자동 설치, persist.adb.tcp.port=5555 확인
- **FINAL_SNIPER 위젯 완전 복구** (2026-06-06)
  - 원인: T33A_wrapper의 cleanup 코드가 매 부팅 시 FINAL_SNIPER 삭제
  - 원인2: t33a_start.sh가 /data/local/tmp/에 없어서 위젯 탭으로 복구 불가
  - 수정: boot.sh cleanup 루프에 FINAL_SNIPER 보존, 부팅 시 재생성 코드 추가
  - 수정: T33A_wrapper를 단순 실행 버전으로 교체 (cleanup 코드 제거)
  - 수정: t33a_start.sh를 /data/local/tmp/ + /sdcard/Download/ 양쪽 배포
- ✅ **Shizuku 의존 제거 + standalone 실증 완료** (2026-06-15) — iOS→갤럭시 마이그레이션 후 삼성 보안이 Shizuku를 악성코드 오진·삭제 → standalone 생존 엔진(rish) 소실 → USB cgroup fallback만 남아 "USB 붙어야만 동작". **진짜 원인 2개**: ①relay_hb를 Termux 유저가 `/data/local/tmp`(0771 shell:shell)에서 rm 불가 → stale → 무한 재시작 ②USB cgroup 선점. **수정**: boot.sh/start.sh에서 rish 경로 전면 제거, relay 정리/hb삭제/기동을 전부 `adb shell`(shell유저)로 이관, connect_adb 루프백 우선. **검증**: USB 분리+BLE 버튼 물리 동작 O, relay_pid(11506) 불변 + relay_hb 연속 갱신(끊김 0) + boot.log "relay dead" 0건. adbd 단일데몬이라 루프백 relay는 USB 분리 생존 확정.
- **`/debrief` 스킬 글로벌 등록** (2026-06-06) — `~/.claude/commands/debrief.md`. 복잡한 세션 후 Orient→Extract→Commit→Gate 4단계 자동 정리. `/end` Step 6.74에 트리거 연동.
- **레슨 2개 MEMORY.md 추가** (2026-06-06): relay_hb stale 첫 재시작 실패 버그, 공유 디렉토리 수정 전 ls 필수
- **WADB Keeper APK — 재부팅 후 무선 디버깅 자동 ON** (2026-07-10): Termux CLI는 SELinux 무음 차단(WRITE_SECURE_SETTINGS 있어도 불가) → smali+apktool 자체 빌드 APK가 앱 컨텍스트로 해결. 실기기 e2e PASS. boot.sh enable_wireless_adb 프로브 + update.sh 즉시 watchdog 재설치([3.5])도 추가. 커밋 `1f78ce7`, `51e52a5`

## 🛠 Working On
(없음)

## ✅ 2026-06-20 fix
- **relay 재시작 시 daemon 보존** — relay가 죽고 새로 뜰 때 daemon PID 살아있으면 kill/restart 생략 → BLE 연결 유지 → 30초 딜레이 소멸
- **USB 해제 OK 확인** — TCP loopback relay는 USB cgroup 밖. CLAUDE.md "절대 안 됨" 경고 삭제
- 원인: relay 25초 주기 사망 시 daemon도 같이 죽었던 구조 → 픽스로 해소

## ⏩ Next Tasks
-2. **🚀 배포+검증 대기 — 2026-08-01 수리 커밋 `daadaed`** (리모컨/폰 있을 때): ①새 `scripts/t33a_boot.sh`를 폰에 배포(규칙 #3: 검증하며) ②`adb reboot` → 잠금해제 → boot.log에서 `WADB Keeper 앱 broadcast` + loopback 연결 확인(Termux uid서 am broadcast 통하는지가 핵심 미검증) ③**adb "이 컴퓨터에서 항상 허용" 1회 체크**(근본원인 #2, 재부팅 인증 리셋 방어). broadcast 메커니즘 자체는 shell uid서 검증됨(result=0, logcat OK).
-1. ~~WADB Keeper 실제 재부팅 테스트~~ → **🔴 실패 확정** (위 REALITY 참조). 위 -2로 대체.
0. **🔬 검증 대기 — 재부팅 콜드패스 풀체인** (2026-06-27): `t33a-auto-tcpip.sh` 신버전(복구폴링 포함)이 *실제 재부팅*에서 안 돌아봄. 다음 재부팅 시 `/tmp/t33a-tcpip.log` 확인 → 성공=`✅ 복구 확인(status=active)` + macOS 알림. **주의: 재부팅 8분 내 PC 꽂으면** Termux:Boot 지연으로 `⚠️ 위젯 1회 탭` 뜸(버그 아님, graceful degrade). 8분 후 꽂으면 풀체인 정상. tcpip 자동활성/이미-tcp 복구알림 경로는 검증됨(19:25·19:57 로그).
1. ~~**재부팅 후 자동 복구 실측**~~ ✅ **완료 (2026-06-20)** — 재부팅 후 위젯 탭으로 복구 확인. tcpip 5555 재부팅 생존 확인. USB 불필요.
2. **컨틴전시 설계** — 진짜 위험은 "폰 쪽"(이번 고장 전부 폰). 여분 BLE 리모컨은 공짜 보험이나 약한 고리(리모컨 물리고장만 커버). 폰 컨틴전시 = 여분 기기 필요(이상적으론 루팅한 별도 기기 = 본체 안 건드림 + 삼성OS 독립 고장 + 견고). **단 같은 폰 루팅은 와이프되므로 불가, 반드시 별도 기기.** 여분 리모컨은 같은 모델이면 지금 페어링만, 다른 모델이면 키코드 추출+config 매핑(`lesson_t33a_key_mapping_oneshot`)
3. **배터리 50% 이하 테스트** — low_power=1 전환 시 BLE 끊김 여부 확인
4. **새 매핑 작업 시 pre-flight 필수**: `adb shell getprop service.adb.tcp.port` → 5555 확인, daemon=active 확인

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
- **2026-08-01**: **재부팅 후 키 미동작 인시던트 근본수리** (커밋 `daadaed`). 진단: 리모컨 부재 상태 라이브 프로브로 오판("BLE 고장")했다가, boot.log/heartbeat mtime/tcpip log로 정정 — 실재부팅(12:50) 후 무선ADB loopback 미기동 → 데몬 7h 사망 → 키 통과. 수리 `scripts/t33a_boot.sh` 3건: ①`enable_wireless_adb`가 CLI(SELinux 차단) 실패 시 **WADB Keeper 앱 broadcast로 강제 ON**(60s 스로틀, watchdog 매 틱=꺼지면 무조건 켬 — broadcast는 shell uid서 result=0+logcat 검증) ②connect_adb 실패 원인 로깅(unauthorized/offline/refused) ③backoff 300→120s. + Mac `~/bin/t33a-auto-tcpip.sh` 복구 폴링 30s→140s(폰 backoff 상한 맞춤, launchd 재기동 반영). 멘토 레슨 #13 저장(과거/부재-트리거 인시던트는 라이브 프로브 전 로그부터). **폰 배포·실재부팅 e2e는 리모컨 있을 때(Next -2).**
- **2026-06-27**: **세션 복구 + REALITY 정정 커밋**. 리셋(컨텍스트 종료)으로 끊긴 세션 복구 — 작업물 손실 0(전부 디스크). 이전 세션 산출물 = "PC 연결만으로 즉시 자동복구" 대안(`~/bin/t33a-auto-tcpip.sh` 풀체인 + launchd `com.ateam.t33a-tcpip`)이 미커밋이던 것을 커밋(`4c22a15` 정정 + `58f9426` 검증마커). 라이브 점검: tcp:5555·status=active·relay_hb age 1s 정상. 콜드패스 풀체인만 다음 재부팅 시 `/tmp/t33a-tcpip.log` 자기검증 대기(Next Tasks #0).
- **2026-06-06 (2차)**: **`/debrief` 스킬 구현** — 복잡한 세션 후 학습 추출/정리/Pre-flight Gate 자동화. GitHub 리서치(session-retrospective, dream-skill, clean-up) + 오늘 T33A 교훈 반영. `~/.claude/commands/debrief.md` 글로벌 등록. `/end` Step 6.74 트리거 연동. 레슨 2개 추가: relay_hb stale, 공유 디렉토리 ls.
- **2026-06-06**: **standalone 구조 복구 + 워치독 강화** (2026-06-06)
  - 원인: 이전 세션에서 Mac에서 USB ADB로 relay 직접 시작 → adbd USB cgroup → USB 분리 시 죽음
  - 수정: relay가 항상 emulator-5554(TCP loopback) 경유로 시작됨 확인. boot.sh connect_adb()가 TCP loopback을 "USB device"로 인식하는 구조 파악
  - 수정: relay.sh에 relay_hb(매초 갱신) 추가 → boot.sh 워치독 응답 시간 150s→35s
  - 수정: boot.sh 워치독 tick 60→15, 임계값 90s→20s (relay_hb 기준)
  - 수정: boot.sh에 rish/Shizuku 60초 대기 루프 추가 (primary path)
  - 수정: start.sh에서 위젯 탭 시 ~/.termux/boot/t33a_boot.sh 자동 설치
  - 확인: persist.adb.tcp.port=5555 설정됨 → 재부팅 후에도 TCP ADB 자동 활성화
  - 확인: relay가 ~10분마다 죽지만(Samsung adbd kill) boot.sh 워치독이 즉시 복구
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

- [2026-07-27] 위젯 파괴 인시던트: boot.sh 정리 루프·start.sh FINAL_SNIPER 강제재생성 제거 (타 프로젝트 위젯 소유권 존중). 폰 4경로 배포 완료(SRC·boot·/data/local/tmp·클론)
