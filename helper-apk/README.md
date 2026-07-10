# WADB Keeper — 재부팅 후 무선 디버깅 자동 재활성화

Android는 재부팅마다 wireless debugging을 끈다 → loopback ADB 불가 → relay 복구 실패.
Termux(앱 uid)는 SELinux가 system CLI(`settings`/`cmd`) 실행을 무음 차단해서 직접 못 켠다
(2026-07-10 실측: WRITE_SECURE_SETTINGS 부여돼도 CLI 5경로 전부 빈 출력 실패).

이 초소형 APK(3.9KB)가 앱 컨텍스트(ContentResolver)로 해결한다:

- `BootReceiver`: BOOT_COMPLETED(첫 잠금해제 후 발화) → `Settings.Global.putInt("adb_wifi_enabled", 1)`
- `Main`(런처 아이콘): 수동 재활성화 + 설치 직후 stopped state 해제

## 빌드 (Mac, Android Studio 불필요)

```bash
export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"   # brew install openjdk@17 apktool
cd helper-apk
apktool b src -o wadbkeeper-unsigned.apk
cp wadbkeeper-unsigned.apk wadbkeeper.apk
jarsigner -keystore wadb.keystore -storepass wadbkeeper \
  -sigalg SHA256withRSA -digestalg SHA-256 wadbkeeper.apk wadb
```

- 소스는 smali 직접 작성 (`src/smali/`) — javac/android.jar 불필요
- targetSdk 28 → v1(jarsigner) 서명만으로 설치 가능 (v2 강제는 targetSdk 30+)
- `wadb.keystore` 재사용 필수 (서명 바뀌면 `-r` 재설치 불가)

## 설치 (1회)

```bash
adb install -r helper-apk/wadbkeeper.apk
adb shell pm grant --user 0 com.ateam.wadbkeeper android.permission.WRITE_SECURE_SETTINGS
adb shell am start --user 0 -n com.ateam.wadbkeeper/.Main   # stopped state 해제 (필수)
```

## 검증 (2026-07-10 실기기 SM-S921N / Android 16 PASS)

```bash
# 무선 디버깅 강제 OFF → 리시버가 되켜는지 (adb 끊기므로 지연 브로드캐스트 선심기)
adb shell "setsid sh -c 'sleep 8; am broadcast --user 0 -n com.ateam.wadbkeeper/.BootReceiver -a test' &"
adb shell settings put global adb_wifi_enabled 0
sleep 20; adb mdns services        # _adb-tls-connect 재등장 = PASS
adb shell logcat -d -s WADBKeeper  # "boot: adb_wifi_enabled=1 set OK"
```

## 재부팅 복구 체인

```
재부팅 → 사용자 첫 잠금해제 → BOOT_COMPLETED → WADB Keeper가 무선 디버깅 ON
       → Termux:Boot boot.sh가 loopback ADB 연결(6회×10s 재시도) → relay 기동 → 데몬 복구
```
사용자 액션: **잠금해제 1회뿐** (기존: 개발자옵션 토글 또는 PC USB 연결).
