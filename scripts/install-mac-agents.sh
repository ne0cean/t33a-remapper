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
[ -L ~/bin/t33a-auto-tcpip.sh ] || ln -sfn "$REPO/scripts/t33a-auto-tcpip.sh" ~/bin/t33a-auto-tcpip.sh
cp "$REPO/scripts/com.ateam.t33a-adb-server.plist" "$LA/"

launchctl bootout gui/$U/com.ateam.t33a-adb-server 2>/dev/null
"$ADB" kill-server 2>/dev/null
sleep 1
launchctl bootstrap gui/$U "$LA/com.ateam.t33a-adb-server.plist"
sleep 2
launchctl kickstart -k gui/$U/com.ateam.t33a-tcpip

APID=$(launchctl list com.ateam.t33a-adb-server | sed -n 's/.*"PID" = \([0-9]*\);/\1/p')
OK=0
for i in $(seq 1 12); do
    sleep 5
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
