# Pre-Landing 리뷰: mac agent bootstrap (0deeb72 + 53a9e11)

티어: LOW — 로컬 launchd 설치 스크립트와 plist 템플릿만 변경. 인증·결제·시크릿 경로 없음. diff 46줄(+44/-2)이라 적대적 리뷰 대상 아님(<50줄). 단, 데몬 기동 순서 레이스는 직접 코드로 검토함.
불변식 위반: 없음
범위: CLEAN (요약과 diff 일치: plist 신설, install 스크립트 8줄, CURRENT.md 5줄)
판정: APPROVE (LOW 3, 블로커 없음)

## 실행한 검증
- `bash -n scripts/install-mac-agents.sh` -> rc=0 (BASHOK)
- `plutil -lint scripts/com.ateam.t33a-tcpip.plist` -> OK
- `launchctl list | grep t33a` -> 72179 adb-server, 72193 tcpip 둘 다 로드 (PID 있음, exit 0)
- `ls -la ~/bin/t33a-auto-tcpip.sh` -> 레포 scripts/t33a-auto-tcpip.sh 로의 심링크
- Semgrep: 이번 호출에서는 미실행(셸/plist 한정 소규모 diff). 필요하면 `pip install semgrep` 후 별도 실행.
- sed 치환 실험(4종 HOME), 아래 LOW-1 참조.

## 검토 포인트별 결론

1. bootout 순서 / heal 상호작용 — 문제 없음.
   install-mac-agents.sh:25-26 에서 tcpip 을 먼저 bootout, 그다음 adb-server bootout, `kill-server`, `bootstrap adb-server`, `sleep 2`, `bootstrap tcpip`.
   tcpip 데몬이 먼저 내려가므로, adb-server 부재 구간에 데몬이 adb 를 호출해 막힌 서버를 스폰할 경로가 없다.
   재기동 후 첫 사이클은 `sleep 15` 뒤 `ensure_device` 라(t33a-auto-tcpip.sh 메인 루프 상단), adb-server 가 이미 5037 을 잡은 뒤다.
   데몬 쪽에도 이중 방어가 있다: `heal_adb_server` 는 `agent_pid` 실패(에이전트 미로드)면 교체를 보류한다(`:185-189`).
   bootstrap 순서(adb-server 먼저, tcpip 나중)도 올바르다.
2. 재실행 멱등성 — 양호. bootout 은 `2>/dev/null` 로 미로드 상태를 허용하고, plist 는 매번 덮어쓰며, 심링크는 `-ef` 로 이미 맞으면 건너뛴다. `mkdir -p` 도 멱등. 실측: 이미 설치된 계정(위 launchctl list)에서 상태 일관.
3. 데몬 종료 — t33a-auto-tcpip.sh:77 의 `trap ... EXIT INT TERM` 으로 bootout(SIGTERM) 시 락 PID 파일이 정리된다.
4. 로그 — 데몬과 install 모두 /tmp/t33a-tcpip.log 를 쓴다(install 이 tail -5). 의도대로.

## 소견

[LOW] scripts/install-mac-agents.sh:23 — `sed "s|__HOME__|$HOME|g"` 는 $HOME 에 `|` 나 `&` 가 있으면 깨진다.
  근거(실측): `HOME='/Users/a|b'` -> `sed: bad flag in substitute command: 'b'`; `HOME='/Users/a&b'` -> 결과 `/Users/a__HOME__b/bin/...`(`&` 가 매치 문자열로 확장); `HOME='/Users/a\b'` -> `/Users/ab`(역슬래시 소실). 공백은 정상(`/Users/a b`).
  또한 `>` 리다이렉트가 먼저 파일을 잘라서, sed 가 실패하면 빈 plist 가 LaunchAgents 에 남고 bootstrap 이 실패한다(원자성 없음).
  영향: macOS 사용자 홈에 해당 문자가 들어가는 일은 사실상 없고(계정명 규칙), 실패해도 로그에 남는 설치 실패일 뿐 보안 영향은 없다. 이번 머지의 블로커 아님.
  제안(선택): 템플릿 치환을 `python3 -c`/`perl` 로 하거나 `PlistBuddy -c "Set :ProgramArguments:1 $HOME/bin/..."` 로 바꾸고, 임시 파일에 쓴 뒤 `mv` 로 교체.

[LOW] scripts/install-mac-agents.sh:19-20 — `mkdir -p` 가 `# 실행본은 ... -ef` 설명 주석과 그것이 설명하는 심링크 줄 사이에 끼어, 주석 대상이 어긋나 읽힌다. 기능 영향 없음, 주석/줄 순서만 정리하면 된다.

[LOW] scripts/install-mac-agents.sh:27-31 — 두 번째 bootstrap 호출(tcpip)은 실패를 검사하지 않는다(`set -u` 만, `-e` 없음).
  이미 다른 경로로 로드된 라벨 등으로 실패하면 출력이 /tmp/t33a-install.log 에만 남고, 이후 12회 폴링(`:35-`)이 폰 연결 여부만 판정한다.
  폴링 결과가 최종 판정을 주므로 "조용한 거짓 성공"은 아니고 실패 안내 메시지가 로컬 네트워크 권한을 언급한다. 다만 bootstrap rc 를 로그에 남기면 진단이 쉬워진다.

## 테스트 커버리지 감사
```
[install-mac-agents.sh]
  +-- 신규 계정 부트스트랩        V 라이브 실측(보고됨), 자동 테스트 X
  +-- 재실행 멱등성               V 코드 경로 확인, 자동 테스트 X
  +-- $HOME 특수문자              X 위 LOW-1 실험으로만 확인
  +-- 장애주입(adb disconnect)    V 라이브 15s 재연결(보고됨)
```
설치 스크립트는 launchd 의존이라 단위 테스트가 어렵다. 회귀 테스트 추가는 요구하지 않는다.

## 문서 staleness
.context/CURRENT.md 갱신됨. plist 헤더 주석이 install 치환을 설명하고 있어 별도 .md 불일치 없음. doc-sync 불필요.

## AUTO-FIX
없음(요청에 따라 코드 수정 금지).

완료: DONE_WITH_CONCERNS (LOW 3건만, 푸시 가능)
