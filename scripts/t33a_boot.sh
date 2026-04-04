#!/data/data/com.termux/files/usr/bin/bash
# T33A — Termux:Boot 자동 시작
# termux-wake-lock으로 Termux를 foreground service화 → Samsung kill 방지
# Termux가 ADB loopback으로 relay+데몬 복구 담당

LOG=/sdcard/Download/t33a_boot.log
RELAY=/data/local/tmp/t33a_relay.sh
BIN=/data/local/tmp/t33a_remap
PORT=5555

echo "$(date): boot started" > "$LOG"

# Termux를 foreground service로 (Samsung kill 방지 핵심)
termux-wake-lock
echo "$(date): wake lock acquired" >> "$LOG"

sleep 20

# ADB 서버 + 연결
adb kill-server >> "$LOG" 2>&1; sleep 1
adb start-server >> "$LOG" 2>&1; sleep 2

for i in $(seq 1 15); do
    PORT=$(getprop service.adb.tls.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=$(getprop service.adb.tcp.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=5555
    result=$(adb connect localhost:$PORT 2>&1)
    echo "$(date): connect #$i (port=$PORT): $result" >> "$LOG"
    echo "$result" | grep -q "connected" && break
    sleep 5
done

adb -s localhost:$PORT shell echo ok >> "$LOG" 2>&1 || {
    echo "$(date): FATAL — ADB failed" >> "$LOG"
    exit 1
}

# relay 기동 (relay가 데몬+watchdog 담당)
adb -s localhost:$PORT shell \
    "rm -f /data/local/tmp/t33a_relay.pid; setsid nohup $RELAY < /dev/null > /dev/null 2>&1 &"
echo "$(date): relay launched" >> "$LOG"
sleep 5

# ── Termux 상주 watchdog ──────────────────────────────────
# wake lock 덕에 Termux는 foreground service → Samsung이 못 죽임
# relay/데몬 죽으면 ADB로 복구
echo "$(date): watchdog loop started" >> "$LOG"

while true; do
    DPID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
    RPID=$(cat /data/local/tmp/t33a_relay.pid 2>/dev/null)

    DAEMON_DEAD=false
    RELAY_DEAD=false

    [ -z "$DPID" ] || ! adb -s localhost:$PORT shell "kill -0 $DPID" > /dev/null 2>&1 \
        && DAEMON_DEAD=true
    [ -z "$RPID" ] || ! adb -s localhost:$PORT shell "kill -0 $RPID" > /dev/null 2>&1 \
        && RELAY_DEAD=true

    if $RELAY_DEAD; then
        echo "$(date): relay dead — restarting" >> "$LOG"
        adb -s localhost:$PORT shell \
            "rm -f /data/local/tmp/t33a_relay.pid; setsid nohup $RELAY < /dev/null > /dev/null 2>&1 &"
        sleep 5
    elif $DAEMON_DEAD; then
        echo "$(date): daemon dead — restarting via relay" >> "$LOG"
        adb -s localhost:$PORT shell "echo restart > /data/local/tmp/t33a.cmd"
    fi

    sleep 30
done
