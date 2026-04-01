#!/data/data/com.termux/files/usr/bin/bash
# T33A Remapper — auto-start on boot + watchdog
# Termux has WRITE_SECURE_SETTINGS → can enable wireless debugging itself

LOG="/sdcard/Download/t33a_boot.log"
BIN="/data/local/tmp/t33a_remap"
STATUS_FILE="/data/local/tmp/t33a.status"
NOTIF_ID="t33a"
echo "$(date): boot script started" > "$LOG"

# ── Notification helper ──
update_notif() {
    local status=$(cat "$STATUS_FILE" 2>/dev/null || echo "unknown")
    case "$status" in
        active)    local title="T33A Active" content="Remapping" ;;
        waiting)   local title="T33A Waiting" content="BLE disconnected" ;;
        restarting) local title="T33A Restarting" content="Auto-recovery" ;;
        *)         local title="T33A" content="Status: $status" ;;
    esac
    termux-notification --id "$NOTIF_ID" --title "$title" --content "$content" --ongoing --priority low 2>/dev/null
}

# ── Watchdog: check daemon, restart if dead, update notification ──
run_watchdog() {
    while true; do
        local pid=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
        if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
            echo "$(date): watchdog: daemon dead — restarting" >> "$LOG"
            adb shell "$BIN" >> "$LOG" 2>&1
            sleep 2
        fi
        update_notif
        sleep 60
    done
}

# Wait for system to settle
sleep 15

# Step 1: Enable wireless debugging from Termux
echo "$(date): enabling wireless debugging..." >> "$LOG"
/system/bin/settings put global adb_wifi_enabled 1 >> "$LOG" 2>&1
sleep 10

# Step 2: Find ADB port and connect
for attempt in $(seq 1 10); do
    PORT=$(getprop service.adb.tls.port 2>/dev/null)
    [ -z "$PORT" ] && PORT=$(getprop service.adb.tcp.port 2>/dev/null)
    [ -z "$PORT" ] && PORT=5555

    echo "$(date): attempt $attempt, port=$PORT" >> "$LOG"
    adb connect localhost:$PORT >> "$LOG" 2>&1
    sleep 3

    if adb shell echo ok >> "$LOG" 2>&1; then
        echo "$(date): connected, starting remapper" >> "$LOG"
        adb shell "$BIN" >> "$LOG" 2>&1
        echo "$(date): remapper started" >> "$LOG"

        # Start watchdog in background (survives boot script exit)
        run_watchdog &
        echo "$(date): watchdog started (PID $!)" >> "$LOG"
        exit 0
    fi
    sleep 5
done

echo "$(date): failed after 10 attempts" >> "$LOG"
