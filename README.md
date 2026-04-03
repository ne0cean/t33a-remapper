# T33A Remote Key Remapper

BLE 리모컨(T33A)의 키를 Android에서 커널 레벨로 리매핑하는 데몬.

## 문제

T33A 리모컨의 버튼이 `KEY_POWER`, `KEY_HOMEPAGE`, `KEY_ENTER` 등 시스템 키로 인식되어, Key Mapper 같은 앱(AccessibilityService 기반)으로는 가로채기 불가능. 특히 `KEY_POWER`는 화면을 꺼버림.

## 해결

`EVIOCGRAB`으로 입력 디바이스를 독점 점유하고, `uinput` 가상 디바이스로 리매핑된 키를 주입.

### 키 매핑

| 리모컨 버튼 | Linux 원본 | 리매핑 결과 |
|------------|-----------|-----------|
| 버튼 1 | `KEY_HOMEPAGE` | `KEY_1` |
| 버튼 2 | `KEY_ENTER` | `KEY_0` |
| 버튼 3 | `KEY_POWER` | `KEY_H` |

## 구조

```
src/t33a_remap.c     # 커널 레벨 키 리매핑 데몬 (EVIOCGRAB + uinput)
scripts/t33a_boot.sh  # Termux:Boot 자동 시작 스크립트
scripts/t33a_start.sh # Termux:Widget 1탭 시작 숏컷
t33a.sh               # Mac에서 원격 제어 (WiFi ADB)
```

## 설치

### 1. 빌드 (Termux에서)
```bash
pkg install clang
clang -o ~/t33a_remap src/t33a_remap.c
```

### 2. 배포
```bash
# ADB로 바이너리 배포
adb push t33a_remap /data/local/tmp/
adb shell chmod +x /data/local/tmp/t33a_remap
```

### 3. 실행
```bash
# ADB에서 데몬 시작 (USB 분리 후에도 유지)
adb shell /data/local/tmp/t33a_remap

# 상태 확인
adb shell /data/local/tmp/t33a_remap status

# 정지
adb shell /data/local/tmp/t33a_remap stop
```

### 4. 재부팅 후 자동 시작 (선택)

**Termux:Boot** — `scripts/t33a_boot.sh`를 `~/.termux/boot/`에 복사

**Termux:Widget** — `scripts/t33a_start.sh`를 `~/.shortcuts/T33A`에 복사

필요 권한:
```bash
# Termux에 무선 디버깅 제어 권한 (1회)
adb shell pm grant com.termux android.permission.WRITE_SECURE_SETTINGS

# 배터리 최적화 해제
adb shell dumpsys deviceidle whitelist +com.termux
adb shell dumpsys deviceidle whitelist +com.termux.boot
```

## 상시 실행 및 안정화 (Always-On)
 
데몬은 리모컨 연결을 상시 감시하며, 비정상 종료 시 슈퍼바이저가 자동 재시작합니다. 더 안정적인 구동을 위해 Samsung 갤럭시 등에서 아래 설정이 필요합니다:

**1. 배터리 최적화 완전 해제** (필수)
- `설정 > 애플리케이션 > Termux > 배터리 > 제한 없음`
- `설정 > 애플리케이션 > Termux:Boot > 배터리 > 제한 없음`

**2. 백그라운드 상시 수행 보장**
- Termux 알림창에서 `Acquire wakelock` 버튼을 클릭하여 잠자기 모드 방지.
- `t33a_boot.sh`에 포함된 Watchdog이 주기적으로 상태를 체크하고 알림바를 업데이트합니다.

## 요구사항

- Android 11+ (Samsung Galaxy 테스트됨)
- T33A BLE 리모컨 (vendor: 05AC, product: 022C)
- Termux + Termux:Boot + Termux:Widget
- ADB 디버깅 활성화

## 동작 원리

1. `/dev/input/`에서 T33A 디바이스를 이름으로 검색
2. `EVIOCGRAB` ioctl로 디바이스 독점 점유 (시스템이 원본 키 못 받음)
3. `uinput`으로 가상 디바이스 생성
4. 키 이벤트 읽기 → 리매핑 → 가상 디바이스로 주입
5. BLE 연결 끊김/재연결 자동 처리
