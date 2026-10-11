---
date: 2026-10-11
base_commit: 8f33598
head_commit: 53a9e11
scope: 0deeb72 (tcpip plist 레포 편입 + install 새 계정 부트스트랩) + 53a9e11 (CURRENT 기록) — 1109386 계정 설치
---

| check | 판정 | 근거 |
|---|---|---|
| syntax | PASS | `bash -n` install·데몬 스크립트 exit 0 |
| plist-lint | PASS | `plutil -lint` 두 plist OK |
| plist-sync | PASS | 렌더한 템플릿 = 설치본, adb-server 레포 = 설치본(`cmp`) |
| symlink | PASS | `~/bin/t33a-auto-tcpip.sh` -ef 메인 체크아웃 스크립트 |
| daemon-loaded | PASS | tcpip·adb-server 둘 다 `launchctl print` 로드·running |
| agent-owns-5037 | PASS | agent=72179 = listener=72179 |
| daemon-health | PASS | 로그 `정상 (... RELAY=1 PORT=5555 WIFI=1 OK=1)`, adb device 연결 |
| installer-live | PASS | 이 계정에서 실제 실행(`/tmp/t33a-install.log`): 에이전트 2종 기동. 폰 연결 판정은 ⚠️ — 신규 adb 키 승인 전이었음, 직후 수동 connect 로 device |
| login-persist | PASS | RunAtLoad·KeepAlive true (로그인 시 자동 기동) |
| wiring | PASS | install·데몬 heal 안내·CURRENT 가 plist/설치 스크립트 참조 |
| self-reconnect 장애주입 | PASS | `adb disconnect` 21:37:00 → 21:37:15 데몬 자력 재연결 (세션 tool output, 로그엔 상태 불변이라 미기록) |
| independent review | PASS | review-pr 격리 1패스 APPROVE(LOW 3), 리포트 `.context/reviews/2026-10-11-mac-agent-bootstrap.md`, record-review 기록 |
| 폰 재부팅 후 복구(신규 키) | UNVERIFIED | 재부팅 미실시 — TLS/mDNS 경로가 1109386 adb 키로 통하는지 미확인 |
| cross-vendor landing review | N/A | LOW 티어(셸/plist 2파일, LIVE/SEC/ARCH 신호 없음) |

Docs Sync: SSOT ✓(CURRENT 10-11 블록) · PRD N/A(스코프 불변) · USER_GUIDE ✓(README 맥 에이전트 절 신설) · rules N/A(절차 규칙 변경 없음)
