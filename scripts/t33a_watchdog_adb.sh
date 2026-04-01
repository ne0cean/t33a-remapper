#!/system/bin/sh
# T33A Watchdog — ADB shell에서 직접 실행 (Termux 불필요)
# 데몬 감시 + termux-notification은 termux-am으로 호출

BIN="/data/local/tmp/t33a_remap"
STATUS_FILE="/data/local/tmp/t33a.status"
LOG="/sdcard/Download/t33a.log"
PID_FILE="/data/local/tmp/t33a_watchdog.pid"

# Prevent duplicate
if [ -f "$PID_FILE" ]; then
    OLD=$(cat "$PID_FILE")
    if kill -0 "$OLD" 2>/dev/null; then
        echo "Watchdog already running (PID $OLD)"
        exit 0
    fi
fi

# Daemonize
echo "$$" > "$PID_FILE"

while true; do
    PID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
    if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') watchdog: daemon dead — restarting" >> "$LOG"
        "$BIN" >> "$LOG" 2>&1
        sleep 2
    fi
    sleep 60
done
