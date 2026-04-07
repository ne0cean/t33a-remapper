# T33A Remote Key Remapper

BLE 리모컨(T33A)의 키를 Android에서 커널 레벨로 리매핑하는 데몬.

## 문제

T33A 리모컨의 버튼이 `KEY_POWER`, `KEY_HOMEPAGE`, `KEY_ENTER` 등 시스템 키로 인식되어, Key Mapper 같은 앱(AccessibilityService 기반)으로는 가로채기 불가능. 특히 `KEY_POWER`는 화면을 꺼버림.

## 해결

`EVIOCGRAB`으로 입력 디바이스를 독점 점유하고, `uinput` 가상 디바이스로 리매핑된 키를 주입.

### 키 매핑 (기본값)

| 리모컨 버튼 | Linux 원본 | 리매핑 결과 |
|------------|-----------|-----------|
| 버튼 1 | `KEY_HOMEPAGE` | `KEY_1` (더블클릭) |
| 버튼 2 | `KEY_ENTER` | `KEY_0` |
| 버튼 3 | `KEY_POWER` | `KEY_H` |

`t33a.conf`에서 커스터마이즈 가능:
```
# Format: <원본 keycode> <리매핑 keycode> [dbl] [wakeup]
172 2 dbl      # KEY_HOMEPAGE → KEY_1, 더블클릭
28 11          # KEY_ENTER → KEY_0
116 35 wakeup  # KEY_POWER → KEY_H, KEY_WAKEUP 선방출 (화면켜기)
```

## 구조

```
src/t33a_remap.c      # 커널 레벨 키 리매핑 데몬 (EVIOCGRAB + uinput)
scripts/t33a_relay.sh # 상주 릴레이 — 데몬 watchdog + 위젯 명령 수신
scripts/t33a_boot.sh  # Termux:Boot 자동 시작 (relay → termux-wake-lock)
t33a.conf             # 키 리매핑 설정 파일
t33a.sh               # Mac/PC에서 원클릭 빌드+배포 (WiFi ADB)
```

### 프로세스 구조

```
t33a_relay.sh (상주, shell)
  └─ t33a_remap (supervisor)
       └─ t33a_remap (worker, evdev_read)
```

- **relay**: 5초 헬스체크로 데몬 감시 + Termux:Widget 명령 처리
- **supervisor**: worker 크래시 시 자동 재시작
- **worker**: T33A BLE 연결 감시 → EVIOCGRAB → 키 리매핑 → uinput 주입

## 빌드 및 배포 (Mac)

```bash
# 원클릭 빌드 + 배포 + 재시작 (zig cc, aarch64-linux-musl)
./t33a.sh deploy

# 상태 확인
./t33a.sh status

# 기타
./t33a.sh start / stop
```

> `zig` 바이너리는 `~/tools/zig-macos-aarch64-0.14.0/zig`에 위치.

## 설치 (최초 1회)

### 1. Mac에서 ADB 배포
```bash
./t33a.sh deploy
```

### 2. Termux:Boot 설정 (재부팅 자동 시작)
```bash
# Termux에서 실행
cp /data/local/tmp/t33a_boot.sh ~/.termux/boot/t33a_boot.sh
chmod +x ~/.termux/boot/t33a_boot.sh
```

### 3. Termux:Widget 설정 (홈 화면 원탭 시작)
```bash
# Termux에서 실행 (Android 14+ ADB 격리 우회)
cp /sdcard/Download/T33A_wrapper ~/.shortcuts/T33A
chmod +x ~/.shortcuts/T33A
```

### 4. 필요 권한 (1회)
```bash
adb shell pm grant com.termux android.permission.WRITE_SECURE_SETTINGS
adb shell dumpsys deviceidle whitelist +com.termux
adb shell dumpsys deviceidle whitelist +com.termux.boot
```

## 상시 실행 안정화 (Samsung Galaxy)

**배터리 최적화 해제** (필수)
- `설정 > 앱 > Termux > 배터리 > 제한 없음`
- `설정 > 앱 > Termux:Boot > 배터리 > 제한 없음`

**termux-wake-lock** (Samsung kill 방지)
- `t33a_boot.sh`가 부팅 시 자동으로 `termux-wake-lock` 실행
- 수동: Termux 알림창 > `Acquire wakelock`

## 요구사항

- Android 11+ (Samsung Galaxy 테스트됨)
- T33A BLE 리모컨
- Termux + Termux:Boot + Termux:Widget
- ADB 디버깅 활성화 (WiFi)
- Mac: `~/tools/zig-macos-aarch64-0.14.0/zig`

## 동작 원리

1. `/dev/input/`에서 `T33A` 디바이스를 이름으로 검색
2. `EVIOCGRAB` ioctl로 디바이스 독점 점유 (시스템이 원본 키 못 받음)
3. `uinput`으로 가상 키보드 디바이스(`T33A-H`) 생성
4. 키 이벤트 읽기 → MSC_SCAN 제거 → 리매핑 → 가상 디바이스로 주입
5. BLE 연결 끊김/재연결 자동 처리 (relay가 데몬 재시작)
