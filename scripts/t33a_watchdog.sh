#!/data/data/com.termux/files/usr/bin/bash
# T33A Watchdog — 상주 프로세스
# 1. 데몬 크래시 감시 및 자동 재기동
# 2. Termux 상단 바 실시간 상태 알림 (Ongoing)

BIN="/data/local/tmp/t33a_remap"
STATUS_FILE="/data/local/tmp/t33a.status"
PID_FILE="/data/local/tmp/t33a.pid"
LOG="/sdcard/Download/t33a.log"
NOTIF_ID="t33a"
WATCHDOG_PID="/data/local/tmp/t33a_watchdog.pid"

# Daemonize watchdog itself
if [ "${1:-}" = "daemon" ]; then
    nohup "$0" run > /dev/null 2>&1 &
    exit 0
fi

# Prevent multi-instance
if [ -f "$WATCHDOG_PID" ]; then
    OLD=$(cat "$WATCHDOG_PID")
    kill -0 "$OLD" 2>/dev/null && exit 0
fi
echo "$$" > "$WATCHDOG_PID"

update_notif() {
    # Check if termux-api exists
    command -v termux-notification >/dev/null 2>&1 || return

    local status=$(cat "$STATUS_FILE" 2>/dev/null || echo "stopped")
    case "$status" in
        active)     local title="T33A: Active"    content="BLE connected & remapping" ;;
        waiting)    local title="T33A: Waiting"   content="Waiting for BLE connection..." ;;
        restarting) local title="T33A: Recovering" content="Daemon died, restarting..." ;;
        stopped)    local title="T33A: Stopped"    content="Daemon is not running" ;;
        *)          local title="T33A"            content="Status: $status" ;;
    esac

    termux-notification --id "$NOTIF_ID" \
                        --title "$title" \
                        --content "$content" \
                        --ongoing \
                        --priority low \
                        --icon keyboard 2>/dev/null
}

while true; do
    # 1. Daemon Health Check
    DPID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -z "$DPID" ] || ! kill -0 "$DPID" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] daemon dead, restarting..." >> "$LOG"
        "$BIN" 2>>"$LOG"
        sleep 2
    fi

    # 2. Update Notification
    update_notif

    sleep 30
done
