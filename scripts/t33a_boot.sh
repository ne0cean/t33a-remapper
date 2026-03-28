#!/data/data/com.termux/files/usr/bin/bash
# T33A Remapper — auto-start on boot
# Termux has WRITE_SECURE_SETTINGS → can enable wireless debugging itself

LOG="/sdcard/Download/t33a_boot.log"
BIN="/data/local/tmp/t33a_remap"
echo "$(date): boot script started" > "$LOG"

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
        exit 0
    fi
    sleep 5
done

echo "$(date): failed after 10 attempts" >> "$LOG"
