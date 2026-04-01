#!/data/data/com.termux/files/usr/bin/bash
# T33A Remapper — Auto-start on boot via Termux:Boot
# Handles wireless debugging activation and daemon initialization.

LOG="/sdcard/Download/t33a_boot.log"
BIN="/data/local/tmp/t33a_remap"
WATCHDOG="/data/data/com.termux/files/home/t33a-remapper/scripts/t33a_watchdog.sh"

echo "$(date '+%Y-%m-%d %H:%M:%S') [boot] script started" > "$LOG"

# Wait for system services to settle
sleep 20

# 1. Self-Enable Wireless Debugging (Requires WRITE_SECURE_SETTINGS)
echo "$(date '+%Y-%m-%d %H:%M:%S') [boot] enabling wireless debugging..." >> "$LOG"
/system/bin/settings put global adb_wifi_enabled 1 >> "$LOG" 2>&1
sleep 15

# 2. Find ADB Port and Connect
PORT=""
for attempt in $(seq 1 10); do
    PORT=$(getprop service.adb.tls.port)
    [ -z "$PORT" ] && PORT=$(getprop service.adb.tcp.port)
    [ -z "$PORT" ] && PORT=5555

    echo "$(date '+%Y-%m-%d %H:%M:%S') [boot] attempt $attempt: connecting to localhost:$PORT" >> "$LOG"
    adb connect "localhost:$PORT" >> "$LOG" 2>&1
    sleep 5

    # Verify connection
    if adb shell echo "ok" >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [boot] adb connected" >> "$LOG"
        
        # Start the Remapper Daemon
        adb shell "$BIN" >> "$LOG" 2>&1
        echo "$(date '+%Y-%m-%d %H:%M:%S') [boot] daemon started" >> "$LOG"

        # Start the Watchdog (standalone daemon mode)
        if [ -f "$WATCHDOG" ]; then
            bash "$WATCHDOG" daemon
            echo "$(date '+%Y-%m-%d %H:%M:%S') [boot] watchdog started" >> "$LOG"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') [boot] ERROR: watchdog script not found at $WATCHDOG" >> "$LOG"
        fi
        
        exit 0
    fi
    sleep 5
done

echo "$(date '+%Y-%m-%d %H:%M:%S') [boot] CRITICAL: adb connection failed after 10 attempts" >> "$LOG"
