# T33A Remote Key Remapper

T33A BLE 리모컨 버튼을 Android에서 커널 레벨로 리매핑하는 데몬.

> ⚠️ **현실(REALITY) — 2026-06-27 정정**: 비루팅 Samsung(Android 14+)에서 **"PC 없이 영구 standalone"은 구조적으로 불가능**하다. 평상시(폰 안 끔)엔 standalone 동작하지만, **재부팅/OS업데이트 후엔 PC에 1회 꽂아야 복구**된다. 이유: 데몬이 `/dev/input`(shell uid=2000) 접근에 폰 adbd의 TCP loopback이 필요한데, `adb tcpip 5555`가 재부팅 후 살아남지 않고, 이를 다시 켜는 유일한 주체가 PC 연결 시 도는 Mac launchd(`com.ateam.t33a-tcpip`)다. 위젯은 Termux 유저라 adbd 모드를 못 바꾼다. 진짜 영구 standalone은 **별도 루팅 기기**에서만 가능. 상세: `~/.claude/.../memory/lesson_t33a_adb_bootstrap_impossible.md`

## 문제

T33A 리모컨의 버튼이 `KEY_POWER`, `KEY_HOMEPAGE`, `KEY_ENTER` 시스템 키로 인식됨. `KEY_POWER`는 화면 꺼버리고, AccessibilityService로는 가로채기 불가.

## 해결

`EVIOCGRAB`으로 입력 디바이스 독점 점유, `uinput`으로 리매핑된 키 주입.

### 키 매핑 (기본값, `t33a.conf`)
```
172 2 dbl       # KEY_HOMEPAGE → KEY_1 더블클릭
28 11           # KEY_ENTER → KEY_0
116 tap 1050 1330  # KEY_POWER → 화면 좌표 탭 (H 기능 대체)
```

## 아키텍처

```
[재부팅]
   ↓
Termux:Boot → ~/.termux/boot/t33a_boot.sh (Termux 유저)
   ↓ termux-wake-lock (Samsung kill 방지)
   ↓ ADB loopback (localhost)
   ↓ shell 유저 컨텍스트 획득
   ↓
t33a_relay.sh (shell 유저, PPID=1)
   ├─ 데몬 watchdog (5초)
   ├─ 위젯 cmd 파일 감시 (1초)
   └─ t33a_remap (supervisor+worker)
         ├─ /dev/input/event* (EVIOCGRAB)
         └─ /dev/uinput (주입)

[사용자 위젯 탭 — 백업 복구]
   ↓
~/.shortcuts/T33A → /data/local/tmp/t33a_start.sh
   ↓ cmd 파일 쓰기 → relay가 1초 내 데몬 재시작 (fast path)
```

## 프로젝트 구조

```
src/t33a_remap.c              # 데몬 C 소스
scripts/t33a_boot.sh          # Termux:Boot 자동 시작 스크립트
scripts/t33a_relay.sh         # 데몬 watchdog + 위젯 cmd 처리
scripts/t33a_start.sh         # 위젯 탭 시 실행
scripts/t33a_widget_reset.sh  # 위젯 원샷 복구 (Termux에서 실행)
t33a.conf                     # 키 매핑 설정
t33a.sh                       # Mac 전용 배포 스크립트
CLAUDE.md                     # Claude 작업 진입점 (경로표, 진단 순서)
lessons/16-*.md               # 레거시 교훈 누적
```

## 빌드 & 배포

### Windows (Zig cross-compile)
```bash
C:\Users\SKTelecom\tools\zig-windows-x86_64-0.14.0\zig.exe cc \
  -target aarch64-linux-musl -static -o build/t33a_remap src/t33a_remap.c

adb push build/t33a_remap /data/local/tmp/
adb push t33a.conf /data/local/tmp/
adb push scripts/*.sh /data/local/tmp/
adb shell chmod +x /data/local/tmp/t33a_remap /data/local/tmp/*.sh
```

### Mac
```bash
./t33a.sh deploy    # 원클릭 빌드+배포
```

### Mac 자동 복구 에이전트 (맥·계정마다 1회)
폰이 이 맥과 같은 LAN 에 들어오면 약 1분 내(감시 15s + 부재 대기 60s, 실측 75s · 연속 실패 누적 시 최대 5분) 붙어서 relay/remap 을 되살리는 launchd 에이전트 2종.
```bash
bash scripts/install-mac-agents.sh   # com.ateam.t33a-adb-server + com.ateam.t33a-tcpip 설치·재기동·검증
tail -f /tmp/t33a-tcpip.log          # 판정 로그
```
- 새 맥/계정의 adb 키는 폰에서 **"이 컴퓨터에서 항상 허용"** 체크 필수(재부팅 후 재연결).
- 맥 여러 대는 OK, **한 맥의 여러 계정 동시 설치는 금지**(5037 포트 충돌).
- 한계: 맥 잠자기·로그아웃·폰 외부망이면 복구 불가. Apple Silicon 전제(`/opt/homebrew/bin/adb` 하드코딩), 폰 IP 기본 192.168.0.18. 다르면 `scripts/com.ateam.t33a-tcpip.plist`에 `EnvironmentVariables` → `T33A_IP` 를 넣고 재설치(셸 `export`는 launchd 데몬에 전달 안 됨). IP 가 바뀌어도 무선 디버깅 ON 이면 mDNS 로 찾은 기기를 시리얼 대조해 따라간다. 단 v7(2026-10-14)부터 5555 가 열려 있는 평상시엔 무선 디버깅을 새로 켜지 않는다(공유기마다 뜨는 허용 창 방지. 이미 켜져 있으면 그대로 둔다) — 그래서 **폰 IP 가 바뀌고 Tailscale 도 없으면 따라가지 못한다**. 폰 IP 는 공유기 DHCP 예약으로 고정하고 Tailscale 을 켜 둘 것.

## 최초 설치 (1회)

### 1. ADB 권한 부여
```bash
adb shell pm grant com.termux android.permission.WRITE_SECURE_SETTINGS
adb shell dumpsys deviceidle whitelist +com.termux
adb shell dumpsys deviceidle whitelist +com.termux.boot
```

### 2. Termux 내부 설치 (Termux 앱에서 직접 실행, ADB 불가)
```bash
# 재부팅 자동 시작용
mkdir -p ~/.termux/boot
cp /data/local/tmp/t33a_boot.sh ~/.termux/boot/t33a_boot.sh
chmod +x ~/.termux/boot/t33a_boot.sh

# 위젯 원샷 리셋 + 위젯 shortcut 설치
bash /data/local/tmp/t33a_widget_reset.sh   # 또는 아래 수동
# mkdir -p ~/.shortcuts
# cp /sdcard/Download/T33A_wrapper ~/.shortcuts/T33A
# chmod +x ~/.shortcuts/T33A
```

### 3. Samsung 배터리 최적화 해제 (필수)
- 설정 → 앱 → Termux → 배터리 → **제한 없음**
- 설정 → 앱 → Termux:Boot → 배터리 → **제한 없음**

### 4. Termux:Boot 앱 한 번 열기
Samsung은 "사용된 적 없는 앱"의 BOOT_COMPLETED를 차단. 설치 후 앱을 한 번 열어야 함.

## 복구 절차 (자동화 깨졌을 때)

### 위젯이 안 먹힘
Termux 앱에서:
```bash
bash /data/local/tmp/t33a_widget_reset.sh
```
→ 홈 화면 위젯 탭 → 1초 내 토스트 확인

### 재부팅 후 데몬 자동 시작 안 됨
Termux 앱에서 확인:
```bash
ls ~/.termux/boot/t33a_boot.sh
```
없으면:
```bash
cp /data/local/tmp/t33a_boot.sh ~/.termux/boot/t33a_boot.sh && chmod +x ~/.termux/boot/t33a_boot.sh
```

## 요구사항

- Android 11+ (Samsung Galaxy 테스트)
- T33A BLE 리모컨
- Termux + Termux:Boot + Termux:Widget
- 최초 설치 시 ADB (USB/WiFi)
- 빌드: Windows/Mac의 zig 0.14.0 (aarch64-linux-musl)
