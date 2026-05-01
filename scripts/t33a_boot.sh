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

# 주의: settings put global adb_wifi_enabled 는 Termux 유저(u0_a533) 권한으로 실패함.
# WRITE_SECURE_SETTINGS / INTERACT_ACROSS_USERS 가 필요. 코드에서 시도 자체를 제거 (lessons/16 교훈 16).
# Samsung은 재부팅마다 무선 디버깅 listener를 죽이므로 사용자 토글 1회가 유일한 해결.

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

# 사용자에게 ADB 토글 1회 요청 — deeplink 포함 알림 (한 번만 발사 후 60초 쿨다운)
notify_adb_toggle() {
    NOTIFY_FLAG=/data/data/com.termux/files/home/.t33a_notify_ts
    NOW=$(date +%s)
    LAST=$(cat "$NOTIFY_FLAG" 2>/dev/null || echo 0)
    [ $((NOW - LAST)) -lt 60 ] && return  # 60초 안에 또 알리지 않음
    echo "$NOW" > "$NOTIFY_FLAG"
    # termux-notification 우선, 없으면 toast
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification \
            --id t33a_adb \
            --title "T33A: 무선 디버깅 토글 필요" \
            --content "설정→개발자 옵션→무선 디버깅 OFF→ON (탭하면 이동)" \
            --priority high \
            --action "am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS" \
            2>/dev/null || true
    else
        timeout 3 termux-toast "T33A: 무선 디버깅 OFF→ON 1회 필요" 2>/dev/null || true
    fi
}

clear_adb_notification() {
    if command -v termux-notification-remove >/dev/null 2>&1; then
        termux-notification-remove t33a_adb 2>/dev/null || true
    fi
    rm -f /data/data/com.termux/files/home/.t33a_notify_ts
}

# 초기 연결 시도
if ! connect_adb; then
    # ADB listener가 안 떠있음 — Samsung 재부팅 한계 (lessons/16 교훈 14, 16).
    # boot.sh는 죽지 않고 retry loop 유지. 사용자가 토글 OFF→ON 하면 다음 60초 안에 자동 복구.
    echo "$(date): ADB connect failed — notifying user, entering retry loop" >> "$LOG"
    notify_adb_toggle
    while true; do
        sleep 60
        if connect_adb; then
            echo "$(date): ADB recovered — proceeding" >> "$LOG"
            clear_adb_notification
            timeout 3 termux-toast "T33A: 자동 복구됨" 2>/dev/null || true
            break
        fi
        notify_adb_toggle  # 60초마다 알림 갱신 (쿨다운 내부에서 dedupe)
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
