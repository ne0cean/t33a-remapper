#!/data/data/com.termux/files/usr/bin/bash
# T33A — Termux:Boot 자동 시작
# Termux 유저(u0_a533)로 실행 → ADB 연결/해제와 완전히 독립
# 바이너리: ~/t33a_remap (Termux 홈, Termux 유저 실행 가능)
# ADB 코드 없음.

LOG=/sdcard/Download/t33a_boot.log
BIN=~/t33a_remap
BIN_SRC=/sdcard/Download/t33a_remap
CMD=/sdcard/Download/t33a.cmd
RELAY_PID=/sdcard/Download/t33a_relay.pid
SRC=/sdcard/Download/t33a_boot.sh
BOOT_DIR="$HOME/.termux/boot"
SHORTCUT_DIR="$HOME/.shortcuts"
WRAPPER=/sdcard/Download/T33A_wrapper

# ── 자체 설치/업데이트 ─────────────────────────────────────────
mkdir -p "$BOOT_DIR" "$SHORTCUT_DIR" 2>/dev/null
[ -f "$SRC" ] && cp "$SRC" "$BOOT_DIR/t33a_boot.sh" && chmod +x "$BOOT_DIR/t33a_boot.sh"
[ -f "$BIN_SRC" ] && cp "$BIN_SRC" "$BIN" && chmod +x "$BIN"
[ -f "$WRAPPER" ] && cp "$WRAPPER" "$SHORTCUT_DIR/T33A" && chmod +x "$SHORTCUT_DIR/T33A"

echo "$(date): boot started" > "$LOG"
termux-wake-lock
echo "$(date): wake lock acquired" >> "$LOG"

# 자신의 PID 기록 (start.sh가 살아있는지 확인)
echo "$$" > "$RELAY_PID"

restart_daemon() {
    pkill -x t33a_remap 2>/dev/null
    sleep 1
    pkill -9 -x t33a_remap 2>/dev/null
    sleep 1
    rm -f /data/local/tmp/t33a.pid
    "$BIN"
    sleep 2
}

echo "$(date): starting daemon" >> "$LOG"
restart_daemon

echo "$(date): watchdog loop started" >> "$LOG"

tick=0
while true; do
    if [ -f "$CMD" ]; then
        rm -f "$CMD"
        echo "$(date): widget cmd — restarting daemon" >> "$LOG"
        restart_daemon
        tick=0
        continue
    fi

    if [ "$tick" -ge 5 ]; then
        PID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
        if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
            echo "$(date): daemon dead — restarting" >> "$LOG"
            restart_daemon
        fi
        tick=0
    fi

    sleep 1
    tick=$((tick + 1))
done
