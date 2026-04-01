#!/data/data/com.termux/files/usr/bin/bash
# T33A Watchdog — 상주 프로세스 (매 60초 체크)
# Usage: bash t33a_watchdog.sh        (포그라운드)
#        bash t33a_watchdog.sh daemon  (백그라운드)

BIN="/data/local/tmp/t33a_remap"
STATUS_FILE="/data/local/tmp/t33a.status"
LOG="/sdcard/Download/t33a.log"
NOTIF_ID="t33a"
WATCHDOG_PID="/data/local/tmp/t33a_watchdog.pid"

# Daemon mode
if [ "${1:-}" = "daemon" ]; then
    nohup "$0" > /dev/null 2>&1 &
    echo "Watchdog started (PID $!)"
    echo "$!" > "$WATCHDOG_PID"
    exit 0
fi

# Prevent duplicate
if [ -f "$WATCHDOG_PID" ]; then
    OLD=$(cat "$WATCHDOG_PID")
    if kill -0 "$OLD" 2>/dev/null; then
        echo "Watchdog already running (PID $OLD)"
        exit 0
    fi
fi
echo "$$" > "$WATCHDOG_PID"

update_notif() {
    local status=$(cat "$STATUS_FILE" 2>/dev/null || echo "stopped")
    case "$status" in
        active)     local title="T33A Active" content="Remapping" ;;
        waiting)    local title="T33A Waiting" content="BLE disconnected" ;;
        restarting) local title="T33A Restarting" content="Auto-recovery" ;;
        stopped)    local title="T33A Stopped" content="Daemon not running" ;;
        *)          local title="T33A" content="$status" ;;
    esac
    termux-notification --id "$NOTIF_ID" --title "$title" --content "$content" --ongoing --priority low 2>/dev/null
}

while true; do
    PID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
    if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') watchdog: daemon dead — restarting" >> "$LOG"
        adb shell "$BIN" >> "$LOG" 2>&1 || "$BIN" >> "$LOG" 2>&1
        sleep 2
    fi
    update_notif
    sleep 60
done
