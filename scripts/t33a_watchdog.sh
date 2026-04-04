#!/system/bin/sh
# T33A Watchdog — ADB shell 독립 데몬 (Termux 죽어도 생존)
# 실행 방법: setsid nohup t33a_watchdog.sh < /dev/null > /dev/null 2>&1 &
# → setsid로 세션 독립 + SIGHUP 무시 → Termux/ADB 세션 종료돼도 유지

BIN="/data/local/tmp/t33a_remap"
LOG="/sdcard/Download/t33a.log"
WATCHDOG_PID="/data/local/tmp/t33a_watchdog.pid"

# --- 중복 실행 방지 ---
if [ -f "$WATCHDOG_PID" ]; then
    OLD=$(cat "$WATCHDOG_PID")
    if kill -0 "$OLD" 2>/dev/null; then
        exit 0
    fi
fi
echo "$$" > "$WATCHDOG_PID"

# --- SIGHUP 무시 (ADB 세션 종료돼도 생존) ---
trap "" HUP

echo "$(date '+%Y-%m-%d %H:%M:%S') watchdog started (PID $$)" >> "$LOG"

update_notif() {
    STATUS=$(cat /data/local/tmp/t33a.status 2>/dev/null || echo "stopped")
    command -v termux-notification >/dev/null 2>&1 || return
    case "$STATUS" in
        active)     TITLE="T33A: Active"    ; BODY="BLE connected & remapping" ;;
        waiting)    TITLE="T33A: Waiting"   ; BODY="Waiting for BLE..." ;;
        restarting) TITLE="T33A: Recovering"; BODY="Restarting daemon..." ;;
        *)          TITLE="T33A: Stopped"   ; BODY="Daemon not running" ;;
    esac
    termux-notification --id t33a --title "$TITLE" --content "$BODY" \
        --ongoing --priority low --icon keyboard 2>/dev/null
}

while true; do
    DPID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
    if [ -z "$DPID" ] || ! kill -0 "$DPID" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') watchdog: daemon dead — restarting" >> "$LOG"
        "$BIN" stop > /dev/null 2>&1
        sleep 1
        "$BIN"
        sleep 3
    fi
    update_notif
    sleep 30
done
