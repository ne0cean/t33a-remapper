#!/data/data/com.termux/files/usr/bin/bash
# T33A — Termux:Boot 자동 시작
# Termux 유저(u0_a533)로 실행 → termux-wake-lock으로 Samsung kill 방지
#
# 구조:
#   boot.sh (Termux 유저, 영구 상주) → ADB → relay.sh (shell 유저, PPID=1 영구 생존)
#   relay.sh가 t33a_remap watchdog (shell 유저 → /dev/input + /dev/uinput 접근 가능)
#
# relay가 PPID=1이면 USB/ADB 종료 후에도 살아있음 (실증 확인됨).
# boot.sh의 ADB는 relay 최초 시작 + 재시작 시에만 필요.
# WiFi ADB 없을 때: deeplink 알림으로 사용자에게 무선 디버깅 토글 1회 안내.

LOG=/sdcard/Download/t33a_boot.log
RELAY_SCRIPT=/sdcard/Download/t33a_relay.sh
RELAY_PID=/sdcard/Download/t33a_relay.pid   # /sdcard: boot.sh(Termux)가 /proc 없이도 읽기 가능
BIN_SRC=/sdcard/Download/t33a_remap
BIN_DST=/data/local/tmp/t33a_remap
SRC=/sdcard/Download/t33a_boot.sh
BOOT_DIR="$HOME/.termux/boot"
SHORTCUT_DIR="$HOME/.shortcuts"
WRAPPER=/sdcard/Download/T33A_wrapper
ADB=/data/data/com.termux/files/usr/bin/adb
NOTIFY_FLAG=/sdcard/Download/t33a_notify_ts
AUTO_PULL="$HOME/t33a-remapper/scripts/t33a_auto_pull.sh"

# ── 자체 설치/업데이트 ─────────────────────────────────────────
mkdir -p "$BOOT_DIR" "$SHORTCUT_DIR" 2>/dev/null
[ -f "$SRC" ] && cp "$SRC" "$BOOT_DIR/t33a_boot.sh" && chmod +x "$BOOT_DIR/t33a_boot.sh"
# 바이너리 복사는 relay(shell 유저)가 담당 — Termux 유저가 직접 하면 "text file busy"
# BIN_SRC가 있으면 relay가 다음 watchdog 사이클에 자동 교체
[ -f "$RELAY_SCRIPT" ] && chmod +x "$RELAY_SCRIPT"
# 불필요한 위젯 정리 후 T33A 1개만 설치
if [ -f "$WRAPPER" ]; then
    ls "$SHORTCUT_DIR/" 2>/dev/null | while read f; do
        [ "$f" = "T33A" ] && continue
        [ "$f" = "FINAL_SNIPER" ] && continue  # HSC 위젯 보존
        rm -f "$SHORTCUT_DIR/$f"
        echo "$(date): removed shortcut: $f" >> "$LOG"
    done
    cp "$WRAPPER" "$SHORTCUT_DIR/T33A" && chmod +x "$SHORTCUT_DIR/T33A"
fi

# FINAL_SNIPER 항상 보장 (HSC 프로젝트 위젯 — 부팅 시 삭제 방지)
_SNIPER="$SHORTCUT_DIR/FINAL_SNIPER"
if [ ! -f "$_SNIPER" ]; then
    cat > "$_SNIPER" << 'SNIPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~
export RISH_APPLICATION_ID="com.termux"
python hsc_master.py
SNIPER_EOF
    chmod +x "$_SNIPER"
    echo "$(date): restored FINAL_SNIPER" >> "$LOG"
fi
unset _SNIPER

echo "$(date): boot started (PID $$)" > "$LOG"
termux-wake-lock
echo "$(date): wake lock acquired" >> "$LOG"

# ── auto_pull 백그라운드 시작 (GitHub 변경 감지 → 자동 업데이트) ────────
if [ -f "$AUTO_PULL" ]; then
    # 이미 실행 중이면 skip
    if ! pgrep -f "t33a_auto_pull" > /dev/null 2>&1; then
        bash "$AUTO_PULL" &
        echo "$(date): auto_pull started (PID $!)" >> "$LOG"
    fi
fi

# ── ADB 연결 (USB 우선, WiFi 차선) ────────────────────────────
ADB_TARGET=""

connect_adb() {
    # 1) USB ADB: 재부팅 직후 / USB 연결 중에는 항상 가능
    if "$ADB" devices 2>/dev/null | grep -qE '^[A-Za-z0-9]+.*device$'; then
        USB_DEV=$("$ADB" devices 2>/dev/null | grep -E '^[A-Za-z0-9]+.*device$' | grep -v localhost | awk '{print $1}' | head -1)
        if [ -n "$USB_DEV" ] && "$ADB" -s "$USB_DEV" shell echo ok > /dev/null 2>&1; then
            ADB_TARGET="$USB_DEV"
            echo "$(date): USB ADB ($USB_DEV)" >> "$LOG"
            return 0
        fi
    fi

    # 2) WiFi ADB (loopback)
    PORT=$(getprop service.adb.tls.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=$(getprop service.adb.tcp.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=5555
    "$ADB" connect "localhost:$PORT" > /dev/null 2>&1
    sleep 1
    if "$ADB" -s "localhost:$PORT" shell echo ok > /dev/null 2>&1; then
        ADB_TARGET="localhost:$PORT"
        echo "$(date): WiFi ADB (localhost:$PORT)" >> "$LOG"
        return 0
    fi

    ADB_TARGET=""
    return 1
}

notify_adb_needed() {
    NOW=$(date +%s)
    LAST=$(cat "$NOTIFY_FLAG" 2>/dev/null || echo 0)
    [ $((NOW - LAST)) -lt 60 ] && return
    echo "$NOW" > "$NOTIFY_FLAG"
    echo "$(date): notifying user — WiFi ADB toggle needed" >> "$LOG"
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification \
            --id t33a_adb \
            --title "T33A: 무선 디버깅 켜기 필요" \
            --content "개발자 옵션 → 무선 디버깅 OFF→ON 1회 토글 후 자동 복구" \
            --priority high \
            --action "am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS" \
            2>/dev/null || true
    else
        timeout 3 termux-toast "T33A: 개발자 옵션 → 무선 디버깅 토글 필요" 2>/dev/null || true
    fi
}

# ── relay 시작 (shell 유저, PPID=1) ───────────────────────────
start_relay() {
    [ -z "$ADB_TARGET" ] && return 1

    # 이미 살아있으면 skip (Termux 유저가 shell 유저의 /proc을 볼 수 없으므로 heartbeat 파일로 판정)
    HB_FILE=/data/local/tmp/t33a.heartbeat
    if [ -f "$HB_FILE" ]; then
        MTIME=$(stat -c %Y "$HB_FILE" 2>/dev/null || echo 0)
        NOW=$(date +%s)
        AGE=$((NOW - MTIME))
        if [ "$AGE" -lt 180 ]; then
            echo "$(date): relay alive (heartbeat age ${AGE}s) — skip" >> "$LOG"
            return 0
        fi
    fi

    echo "$(date): starting relay via ADB ($ADB_TARGET)" >> "$LOG"
    rm -f "$RELAY_PID"

    # setsid: 새 세션 → PPID=1로 고아화 → ADB 종료 후에도 생존
    "$ADB" -s "$ADB_TARGET" shell \
        "setsid /system/bin/sh '$RELAY_SCRIPT' < /dev/null > /dev/null 2>&1 &"
    sleep 5

    HB_FILE=/data/local/tmp/t33a.heartbeat
    MTIME=$(stat -c %Y "$HB_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    AGE=$((NOW - MTIME))
    RPID=$(cat "$RELAY_PID" 2>/dev/null)
    if [ "$AGE" -lt 30 ]; then
        echo "$(date): relay started OK (PID $RPID, heartbeat age ${AGE}s)" >> "$LOG"
        rm -f "$NOTIFY_FLAG"
        return 0
    fi

    echo "$(date): relay start failed (PID $RPID, heartbeat age ${AGE}s)" >> "$LOG"
    return 1
}

# ── 초기 시작 ──────────────────────────────────────────────────
# Termux:Boot 후 adbd 준비까지 최대 1분 대기
echo "$(date): connecting ADB..." >> "$LOG"
for i in $(seq 1 6); do
    if connect_adb; then
        break
    fi
    echo "$(date): ADB attempt $i/6 failed, retry in 10s" >> "$LOG"
    sleep 10
done

if [ -n "$ADB_TARGET" ]; then
    start_relay
else
    echo "$(date): ADB unavailable — entering retry loop, notifying user" >> "$LOG"
    notify_adb_needed
fi

# ── Termux 상주 watchdog ────────────────────────────────────────
# relay는 PPID=1이므로 거의 죽지 않음.
# 60초마다 /proc으로 확인 → 죽으면 ADB로 재시작.
echo "$(date): watchdog loop started" >> "$LOG"
tick=0
while true; do
    tick=$((tick + 1))

    if [ "$tick" -ge 60 ]; then
        tick=0
        HB_FILE=/data/local/tmp/t33a.heartbeat
        MTIME=$(stat -c %Y "$HB_FILE" 2>/dev/null || echo 0)
        NOW=$(date +%s)
        AGE=$((NOW - MTIME))
        if [ "$AGE" -lt 90 ]; then
            : # heartbeat fresh — relay alive
        else
            RPID=$(cat "$RELAY_PID" 2>/dev/null)
            echo "$(date): relay dead (heartbeat ${AGE}s, PID $RPID) — restarting" >> "$LOG"
            ADB_TARGET=""
            if connect_adb; then
                start_relay || notify_adb_needed
            else
                notify_adb_needed
            fi
        fi
    fi

    sleep 1
done
