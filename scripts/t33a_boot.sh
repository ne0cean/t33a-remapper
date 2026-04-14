#!/data/data/com.termux/files/usr/bin/bash
# T33A — Termux:Boot 자동 시작 + 자체 설치
# termux-wake-lock으로 Termux를 foreground service화 → Samsung kill 방지
# Termux가 ADB loopback으로 relay+데몬을 shell 유저로 기동

LOG=/sdcard/Download/t33a_boot.log
RELAY=/data/local/tmp/t33a_relay.sh
SRC=/data/local/tmp/t33a_boot.sh
BOOT_DIR="$HOME/.termux/boot"
SHORTCUT_DIR="$HOME/.shortcuts"
WRAPPER=/sdcard/Download/T33A_wrapper

# ── 자체 설치/업데이트 (매 실행마다 동기화) ──────────────────
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

# WiFi ADB 활성화 (OS 업데이트/재부팅이 리셋할 수 있음)
/system/bin/settings put global adb_wifi_enabled 1 2>/dev/null
echo "$(date): adb_wifi_enabled set to 1" >> "$LOG"

sleep 25

# ADB 서버 + 연결
adb kill-server >> "$LOG" 2>&1; sleep 1
adb start-server >> "$LOG" 2>&1; sleep 2

connect_adb() {
    connected=false
    for i in $(seq 1 20); do
        PORT=$(getprop service.adb.tls.port 2>/dev/null)
        [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=$(getprop service.adb.tcp.port 2>/dev/null)
        [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=5555
        result=$(adb connect localhost:$PORT 2>&1)
        echo "$(date): connect #$i (port=$PORT): $result" >> "$LOG"
        if echo "$result" | grep -q "connected"; then
            if adb -s localhost:$PORT shell echo ok > /dev/null 2>&1; then
                connected=true
                break
            fi
        fi
        sleep 5
    done
    $connected
}

# 초기 연결 시도
if ! connect_adb; then
    # FATAL 대신: wake-lock 유지하면서 주기적 재시도
    # Samsung이 재부팅마다 adb_wifi_enabled=0으로 리셋 → settings put 실패 → ADB 연결 실패 가능
    # 이때 boot.sh가 죽으면 재부팅 후 아무것도 자동 복구 안 됨. 그래서 retry loop로 바꿈
    # 사용자가 위젯 탭, USB 연결, 또는 WiFi ADB 페어링 시 자동 복구
    echo "$(date): ADB connect failed — entering retry loop (wake-lock 유지)" >> "$LOG"
    termux-toast "T33A: WiFi ADB 대기 중 (위젯 탭 권장)" 2>/dev/null || true
    while true; do
        sleep 60
        /system/bin/settings put global adb_wifi_enabled 1 2>/dev/null
        if connect_adb; then
            echo "$(date): ADB recovered — proceeding" >> "$LOG"
            termux-toast "T33A: WiFi ADB 복구됨" 2>/dev/null || true
            break
        fi
    done
fi

# relay 기동 — 이중 fork로 init(PID 1)에 reparent (ADB 세션 종료에도 생존)
adb -s localhost:$PORT shell \
    "OLD=\$(cat /data/local/tmp/t33a_relay.pid 2>/dev/null); [ -n \"\$OLD\" ] && kill \$OLD 2>/dev/null; rm -f /data/local/tmp/t33a_relay.pid; (setsid /system/bin/sh $RELAY < /dev/null > /dev/null 2>&1 &)"
echo "$(date): relay launched (double-fork)" >> "$LOG"
sleep 5

# ── Termux 상주 watchdog ──────────────────────────────────
# wake lock 덕에 Termux는 foreground service → Samsung이 못 죽임
# relay/데몬 죽으면 ADB로 복구
echo "$(date): watchdog loop started" >> "$LOG"

while true; do
    DPID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
    RPID=$(cat /data/local/tmp/t33a_relay.pid 2>/dev/null)

    DAEMON_DEAD=false
    RELAY_DEAD=false

    [ -z "$DPID" ] || ! adb -s localhost:$PORT shell "kill -0 $DPID" > /dev/null 2>&1 \
        && DAEMON_DEAD=true
    [ -z "$RPID" ] || ! adb -s localhost:$PORT shell "kill -0 $RPID" > /dev/null 2>&1 \
        && RELAY_DEAD=true

    if $RELAY_DEAD; then
        echo "$(date): relay dead — restarting" >> "$LOG"
        adb -s localhost:$PORT shell \
            "OLD=\$(cat /data/local/tmp/t33a_relay.pid 2>/dev/null); [ -n \"\$OLD\" ] && kill \$OLD 2>/dev/null; rm -f /data/local/tmp/t33a_relay.pid; (setsid /system/bin/sh $RELAY < /dev/null > /dev/null 2>&1 &)"
        sleep 5
    elif $DAEMON_DEAD; then
        echo "$(date): daemon dead — restarting via relay" >> "$LOG"
        adb -s localhost:$PORT shell "echo restart > /data/local/tmp/t33a.cmd"
    fi

    sleep 30
done
