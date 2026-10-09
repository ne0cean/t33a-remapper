#!/bin/bash
# 맥 launchd 에이전트 설치·재기동 (t33a 소유 2종만 건드린다).
#   com.ateam.t33a-adb-server — adb 서버 상시 소유 (nodaemon)
#   com.ateam.t33a-tcpip      — 폰 감시·자동 복구 데몬 (~/bin/t33a-auto-tcpip.sh)
# 결과 원문은 /tmp/t33a-install.log, 화면에는 판정 1줄.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
U=$(id -u)
LA=~/Library/LaunchAgents
OUT=/tmp/t33a-install.log
ADB=/opt/homebrew/bin/adb
exec 3>&1 >"$OUT" 2>&1

# 실행본은 레포 파일 심링크다(배포 드리프트 차단, 09-11). 복사로 덮지 않는다.
# 링크 대상은 메인 체크아웃 — worktree에서 실행해도 지워질 worktree를 가리키지 않게 한다.
MAIN="$(git -C "$REPO" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
TARGET="${MAIN:-$REPO}/scripts/t33a-auto-tcpip.sh"
# -ef = 같은 실파일인지(홈 경로 별칭 /Users/<id>↔/Users/noir 문자열 차이 무시).
{ [ -L ~/bin/t33a-auto-tcpip.sh ] && [ ~/bin/t33a-auto-tcpip.sh -ef "$TARGET" ]; } || ln -sfn "$TARGET" ~/bin/t33a-auto-tcpip.sh
cp "$REPO/scripts/com.ateam.t33a-adb-server.plist" "$LA/"

launchctl bootout gui/$U/com.ateam.t33a-adb-server 2>/dev/null
"$ADB" kill-server 2>/dev/null
sleep 1
launchctl bootstrap gui/$U "$LA/com.ateam.t33a-adb-server.plist"
sleep 2
launchctl kickstart -k gui/$U/com.ateam.t33a-tcpip

OK=0
for i in $(seq 1 12); do
    sleep 5
    # KeepAlive 재기동으로 PID가 바뀔 수 있어 매 회 다시 읽는다.
    APID=$(launchctl print "gui/$U/com.ateam.t33a-adb-server" 2>/dev/null | sed -n 's/^[[:space:]]*pid = \([0-9]*\)$/\1/p' | head -1)
    LPID=$(lsof -nP -iTCP:5037 -sTCP:LISTEN -t 2>/dev/null | head -1)
    DEV=$("$ADB" devices | awk '$2=="device"{print $1}' | head -1)
    echo "t+$((i*5))s listener=$LPID agent=$APID dev=$DEV"
    [ -n "$APID" ] && [ "$LPID" = "$APID" ] && [ -n "$DEV" ] && { OK=1; break; }
done
tail -5 /tmp/t33a-tcpip.log
if [ "$OK" = 1 ]; then
    echo "✅ 설치 완료 — launchd adb 서버($APID)가 폰($DEV)에 연결됨" >&3
else
    echo "⚠️ 설치는 됐으나 폰 연결 미확인 — $OUT 확인" >&3
fi
