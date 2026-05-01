#!/data/data/com.termux/files/usr/bin/bash
# T33A — Termux:Boot 자동 시작
# 구조: Termux(u0_a533)가 relay를 직접 실행. ADB 불필요.
# relay(shell 스크립트)가 데몬 watchdog + 위젯 cmd 처리.
# termux-wake-lock으로 Termux foreground service 유지 → Samsung kill 방지.

LOG=/sdcard/Download/t33a_boot.log
RELAY=/data/local/tmp/t33a_relay.sh
RELAY_PID=/sdcard/Download/t33a_relay.pid
SRC=/data/local/tmp/t33a_boot.sh
BOOT_DIR="$HOME/.termux/boot"
SHORTCUT_DIR="$HOME/.shortcuts"
WRAPPER=/sdcard/Download/T33A_wrapper

# ── 자체 설치/업데이트 ─────────────────────────────────────────
mkdir -p "$BOOT_DIR" "$SHORTCUT_DIR" 2>/dev/null
if [ "$SRC" != "$BOOT_DIR/t33a_boot.sh" ] && [ -f "$SRC" ]; then
    cp "$SRC" "$BOOT_DIR/t33a_boot.sh" && chmod +x "$BOOT_DIR/t33a_boot.sh"
fi
if [ -f "$WRAPPER" ]; then
    cp "$WRAPPER" "$SHORTCUT_DIR/T33A" && chmod +x "$SHORTCUT_DIR/T33A"
fi

echo "$(date): boot started" > "$LOG"

# Termux를 foreground service로 (Samsung kill 방지 핵심)
termux-wake-lock
echo "$(date): wake lock acquired" >> "$LOG"

# ── relay 직접 기동 ─────────────────────────────────────────────
# Termux(u0_a533)에서 relay.sh 직접 실행.
# relay.sh는 #!/system/bin/sh — shell 유저로 실행됨 (t33a_remap 바이너리 실행 권한 있음).
# nohup + setsid로 boot.sh 종료 후에도 생존.
launch_relay() {
    # 기존 relay 정리
    OLD=$(cat "$RELAY_PID" 2>/dev/null)
    [ -n "$OLD" ] && kill "$OLD" 2>/dev/null
    rm -f "$RELAY_PID"
    # 이중 fork: (setsid sh relay & ) — PPID=1에 reparent, Termux 종료에도 생존
    (setsid /system/bin/sh "$RELAY" < /dev/null > /dev/null 2>&1 &)
    sleep 3
}

launch_relay
echo "$(date): relay launched" >> "$LOG"

# ── Termux 상주 watchdog ───────────────────────────────────────
# wake-lock으로 Termux는 foreground → Samsung이 못 죽임.
# relay가 죽으면 직접 재시작. ADB 불필요.
echo "$(date): watchdog loop started" >> "$LOG"

while true; do
    sleep 30

    RPID=$(cat "$RELAY_PID" 2>/dev/null)
    if [ -z "$RPID" ] || ! kill -0 "$RPID" 2>/dev/null; then
        echo "$(date): relay dead — restarting" >> "$LOG"
        launch_relay
    fi
done
