# PMI evidence — t33a-remapper 9731035..c700e7f + PMI/리뷰 반영 커밋
| check | 판정 | 근거 |
|---|---|---|
| bash-n-auto-tcpip / bash-n-install | PASS | checks/*.exit=0 |
| plist-lint | PASS | exit 0 |
| launchd-path-tools | PASS (static) | 기본 PATH에 nc·lsof·launchctl |
| heal-wiring | PASS (static) | ensure_device 실패 시에만 호출 |
| heal-unloaded-guard | PASS (live, 인터랙티브 셸) | 에이전트 미설치 → rc=1, 5037 리스너 불변(38418) |
| test-census | N/A(자동 테스트 0개 — 실기기 검증 체계) | count=0 |
| shellcheck | UNVERIFIED | 미설치 |
| live: launchd nodaemon 서버 LAN 도달 | PASS (live) | launchctl submit 서버로 adb connect 성공 20:27 |
| live: 설치 + heal 데몬 문맥 발화 | UNVERIFIED | 설치 미실행(세션 가드) |
| independent review (review-pr, sonnet) | FAIL→수리 | HIGH2·MED2·LOW1 → 미설치 가드·리스너 폴링·주석 정정·심링크 보존 반영. 데몬 문맥 E2E는 잔여 |
| cross-vendor landing review | UNVERIFIED | 미실행 |
| verify-gate-coverage | N/A(a-team 전용) | |
