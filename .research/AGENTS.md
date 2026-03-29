
## 반복 1 교훈 (2026-03-29)

### RunCommandService는 권한이 필요하다
`am startservice -n com.termux/.app.RunCommandService`는 `com.termux.permission.RUN_COMMAND` 권한 없이는 실행 불가.
Termux에서 `allow-external-apps=true` 설정 후 권한 부여가 선행되어야 한다.

### 빌드 대안 경로
1. **수동**: Termux에서 `bash /sdcard/Download/t33a_build.sh` 직접 실행
2. **자동화**: `~/.termux/termux.properties`에 `allow-external-apps=true` 추가 후 권한 부여

### 이번 수정 핵심
- EV_ABS (ABS_X/Y/PRESSURE) → Android GAMEPAD 분류 원인 → 제거
- MSC_SCAN 패스스루 → 앱이 remapped key 대신 원본 scan code 인식 → 필터링
