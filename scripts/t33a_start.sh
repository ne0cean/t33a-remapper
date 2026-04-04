#!/data/data/com.termux/files/usr/bin/bash
# T33A 위젯 — 원터치 재시작
# Fast path:  relay 살아있음 → cmd 파일 쓰기 → ~1초
# Slow path:  relay 죽음    → ADB loopback → relay + 데몬 재시작

RELAY_PID_FILE=/data/local/tmp/t33a_relay.pid
RELAY=/data/local/tmp/t33a_relay.sh
CMD=/data/local/tmp/t33a.cmd
LOG=/sdcard/Download/t33a_boot.log
PORT=5555

echo "" >> "$LOG"
echo "$(date): === widget tap ===" >> "$LOG"

# ── Fast path ──────────────────────────────────────────────
RPID=$(cat "$RELAY_PID_FILE" 2>/dev/null)
if [ -n "$RPID" ] && kill -0 "$RPID" 2>/dev/null; then
    echo restart > "$CMD"
    echo "$(date): fast path — relay PID $RPID" >> "$LOG"
    termux-toast "T33A 재시작 중"
    exit 0
fi

# ── Slow path: relay 죽음, ADB로 재시작 ───────────────────
echo "$(date): slow path — relay dead" >> "$LOG"
termux-toast "T33A: 초기화 중... (15초)"

/system/bin/settings put global adb_wifi_enabled 1 2>/dev/null
sleep 3

adb kill-server >> "$LOG" 2>&1
sleep 1
adb start-server >> "$LOG" 2>&1
sleep 2

connected=false
for i in $(seq 1 15); do
    result=$(adb connect localhost:$PORT 2>&1)
    echo "$(date): connect #$i: $result" >> "$LOG"
    if echo "$result" | grep -q "connected"; then
        connected=true
        break
    fi
    sleep 2
done

if ! $connected; then
    termux-toast "T33A: ADB 연결 실패"
    echo "$(date): FAILED" >> "$LOG"
    exit 1
fi

# relay 시작 (relay가 데몬까지 기동)
adb -s localhost:$PORT shell \
    "setsid nohup $RELAY < /dev/null > /dev/null 2>&1 &"
echo "$(date): relay started via ADB" >> "$LOG"
sleep 5

termux-toast "T33A 재시작됨"
echo "$(date): done" >> "$LOG"
