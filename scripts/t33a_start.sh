#!/data/data/com.termux/files/usr/bin/bash
# T33A Remapper — one-tap start (Termux:Widget shortcut)

LOG="/sdcard/Download/t33a_boot.log"
BIN="/data/local/tmp/t33a_remap"
echo "$(date): manual start" > "$LOG"

# Step 1: Enable wireless debugging
/system/bin/settings put global adb_wifi_enabled 1
echo "$(date): wireless debugging enabled" >> "$LOG"
sleep 5

# Step 2: Find port and connect
for i in $(seq 1 5); do
    PORT=$(getprop service.adb.tls.port 2>/dev/null)
    [ -z "$PORT" ] && PORT=$(getprop service.adb.tcp.port 2>/dev/null)
    [ -z "$PORT" ] && PORT=5555

    adb connect localhost:$PORT >> "$LOG" 2>&1
    sleep 2

    if adb shell echo ok >> "$LOG" 2>&1; then
        adb shell "$BIN" >> "$LOG" 2>&1
        echo "$(date): remapper started" >> "$LOG"
        toast "T33A remapper started"
        exit 0
    fi
    sleep 3
done

echo "$(date): failed" >> "$LOG"
toast "T33A start failed - check log"
