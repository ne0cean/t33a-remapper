---
status: in_progress
task: 다른 맥에 T33A 자동 복구 에이전트 설치
created: 2026-10-11
origin: 1109386 계정 맥 (설치·검증 완료, 커밋 0deeb72~9080e98)
---

# RESUME — 다른 맥에서 자동 복구 설정

> 이 파일을 `/pickup`이 읽으면 아래 순서대로 진행한다. **맥마다 1회.** 모든 맥이 끝나면 `status: completed`.

## 0. 이미 설치된 맥인지 먼저 확인 (설치돼 있으면 1~4 스킵)
```bash
launchctl list | grep t33a          # com.ateam.t33a-adb-server + com.ateam.t33a-tcpip 둘 다 PID 있으면 설치됨
tail -3 /tmp/t33a-tcpip.log         # "정상 (... OK=1)" 이면 끝
```
- 설치 완료 맥: **1109386 계정 맥(2026-10-11)**.
- ⚠️ **같은 맥의 다른 계정**(예: `noir`)에는 설치하지 말 것 — adb 서버 포트 5037·`/tmp` 락을 계정끼리 공유해 충돌한다. 다른 *물리* 맥만 대상.

## 1. 레포 최신화
```bash
cd ~/Projects/t33a-remapper && git pull --ff-only     # 없으면: cd ~/Projects && gh repo clone ne0cean/t33a-remapper
```

## 2. adb 확인 (Apple Silicon 전제 — 스크립트가 `/opt/homebrew/bin/adb` 하드코딩)
```bash
ls /opt/homebrew/bin/adb || brew install --cask android-platform-tools
```

## 3. 설치 (launchd 에이전트 2종 등록·기동·검증, 판정 1줄 출력)
```bash
bash scripts/install-mac-agents.sh
```
- 세션 가드가 launchd 쓰기를 막으면 의장이 프롬프트에 `! bash ~/Projects/t33a-remapper/scripts/install-mac-agents.sh`.
- `⚠️ 폰 연결 미확인`이 떠도 정상일 수 있다: 이 맥의 adb 키가 처음이라 폰이 아직 승인 전. → 4번.

## 4. 폰 승인 + 검증
1. 폰에 "USB/무선 디버깅 허용?" 창 → **"이 컴퓨터에서 항상 허용" 체크** 후 허용 (안 하면 폰 재부팅 후 이 맥이 못 붙음).
2. 창이 안 뜨면 `/opt/homebrew/bin/adb connect 192.168.0.18:5555` 1회 실행해 띄운다.
3. `No route to host`면: 시스템 설정 → 개인정보 보호 및 보안 → 로컬 네트워크 → adb/bash 허용.
4. 검증 — 약 1분 내 아래가 찍히면 완료:
   ```bash
   tail -3 /tmp/t33a-tcpip.log      # "[192.168.0.18:5555] 정상 (... OK=1)"
   ```
5. (선택) 자력 재연결 확인: `adb disconnect 192.168.0.18:5555` → 15s 내 `adb devices`에 다시 `device`.

## 5. 기록
- 위 "설치 완료 맥" 목록에 이 맥 추가, CURRENT Next -5 ②에 체크.
- 맥이 더 없으면 이 파일 `status: completed`.

## 참고
- 폰 IP가 다르면 `scripts/com.ateam.t33a-tcpip.plist`에 `EnvironmentVariables` → `T33A_IP` 후 재설치(셸 export 무효).
- 맥 여러 대 동시 사용 OK(relay pid 락으로 중복 복구 방지). 상세: README "Mac 자동 복구 에이전트" 절.
- 미검증(별건, Next -5 ①): 폰 재부팅 후 신규 키로 복구.
