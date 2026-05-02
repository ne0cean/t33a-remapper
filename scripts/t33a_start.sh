#!/data/data/com.termux/files/usr/bin/bash
# T33A 위젯 — 원터치 재시작
# Fast path: cmd 파일 쓰고 1.5초 대기 → relay가 소비했으면 완료
# Slow path: relay 죽음 → ADB(USB 우선/WiFi 차선)로 relay 재기동

RELAY_PID_FILE=/sdcard/Download/t33a_relay.pid
RELAY_SCRIPT=/sdcard/Download/t33a_relay.sh
CMD=/sdcard/Download/t33a.cmd
LOG=/sdcard/Download/t33a_boot.log
ADB=/data/data/com.termux/files/usr/bin/adb

echo "" >> "$LOG"
echo "$(date): === widget tap ===" >> "$LOG"

# ── Fast path ──────────────────────────────────────────────────
echo restart > "$CMD"
sleep 1.5
if [ ! -f "$CMD" ]; then
    echo "$(date): fast path — relay alive, cmd consumed" >> "$LOG"
    timeout 3 termux-toast "T33A 재시작 중"
    exit 0
fi

# ── Slow path: relay 죽음 ──────────────────────────────────────
rm -f "$CMD"
echo "$(date): slow path — relay dead, restarting via ADB" >> "$LOG"
timeout 3 termux-toast "T33A: 초기화 중..."

ADB_TARGET=""

# USB ADB 우선 (항상 가능, USB 연결 중)
if "$ADB" devices 2>/dev/null | grep -qE '^[A-Za-z0-9]+.*device$'; then
    USB_DEV=$("$ADB" devices 2>/dev/null | grep -E '^[A-Za-z0-9]+.*device$' | grep -v localhost | awk '{print $1}' | head -1)
    if [ -n "$USB_DEV" ] && "$ADB" -s "$USB_DEV" shell echo ok > /dev/null 2>&1; then
        ADB_TARGET="$USB_DEV"
        echo "$(date): USB ADB ($USB_DEV)" >> "$LOG"
    fi
fi

# WiFi ADB (USB 없을 때)
if [ -z "$ADB_TARGET" ]; then
    PORT=$(getprop service.adb.tls.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=$(getprop service.adb.tcp.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=5555

    for i in 1 2 3; do
        result=$("$ADB" connect "localhost:$PORT" 2>&1)
        echo "$(date): WiFi ADB attempt $i (port=$PORT): $result" >> "$LOG"
        if echo "$result" | grep -q "connected" && "$ADB" -s "localhost:$PORT" shell echo ok > /dev/null 2>&1; then
            ADB_TARGET="localhost:$PORT"
            break
        fi
        sleep 1
    done
fi

if [ -z "$ADB_TARGET" ]; then
    echo "$(date): FAILED — no ADB, notifying user" >> "$LOG"
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification \
            --id t33a_adb \
            --title "T33A: 무선 디버깅 토글 필요" \
            --content "개발자 옵션 → 무선 디버깅 OFF→ON (탭하면 이동)" \
            --priority high \
            --action "am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS" \
            2>/dev/null || true
    else
        timeout 3 termux-toast "T33A: 무선 디버깅 OFF→ON 1회 필요"
    fi
    exit 1
fi

# relay 재시작 (shell 유저, PPID=1)
RPID=$(cat "$RELAY_PID_FILE" 2>/dev/null)
[ -n "$RPID" ] && "$ADB" -s "$ADB_TARGET" shell "kill $RPID 2>/dev/null; sleep 1; kill -9 $RPID 2>/dev/null"
rm -f "$RELAY_PID_FILE"

"$ADB" -s "$ADB_TARGET" shell \
    "setsid /system/bin/sh '$RELAY_SCRIPT' < /dev/null > /dev/null 2>&1 &"
sleep 3

# 알림 정리
command -v termux-notification-remove >/dev/null 2>&1 && termux-notification-remove t33a_adb 2>/dev/null || true

RPID=$(cat "$RELAY_PID_FILE" 2>/dev/null)
if [ -n "$RPID" ] && [ -d "/proc/$RPID" ]; then
    echo "$(date): relay restarted (PID $RPID)" >> "$LOG"
    timeout 3 termux-toast "T33A 재시작됨"
else
    echo "$(date): relay start uncertain" >> "$LOG"
    timeout 3 termux-toast "T33A 재시작됨 (확인 필요)"
fi
