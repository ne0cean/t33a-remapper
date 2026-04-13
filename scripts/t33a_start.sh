#!/data/data/com.termux/files/usr/bin/bash
# T33A 위젯 — 원터치 재시작
# Fast path: cmd 파일 쓰고 1초 대기 → relay가 처리했으면 끝 (~1초)
# Slow path: relay 죽음 → ADB loopback → 기존 relay kill → 새 relay 띄움 (~3초)

RELAY_PID_FILE=/data/local/tmp/t33a_relay.pid
RELAY=/data/local/tmp/t33a_relay.sh
CMD=/sdcard/Download/t33a.cmd  # /sdcard로: Termux(u0_a533)와 shell 둘 다 write 가능
LOG=/sdcard/Download/t33a_boot.log

echo "" >> "$LOG"
echo "$(date): === widget tap ===" >> "$LOG"

# ── Fast path: cmd 쓰고 relay 처리 여부로 alive 판정 ──
# Termux(u0_a533)에서 shell 유저 /proc 접근 불가 → cmd 파일 소비 여부로 우회
echo restart > "$CMD"
sleep 1.5
if [ ! -f "$CMD" ]; then
    # relay가 cmd를 처리하고 삭제함 = 살아있음
    echo "$(date): fast path — cmd consumed" >> "$LOG"
    termux-toast "T33A 재시작 중"
    exit 0
fi

# ── Slow path: cmd 안 사라짐 = relay 죽음, ADB로 재기동 ──
rm -f "$CMD"
echo "$(date): slow path — relay dead" >> "$LOG"
termux-toast "T33A: 초기화 중..."

/system/bin/settings put global adb_wifi_enabled 1 2>/dev/null

# ADB 서버는 이미 떠있을 가능성 높음 — kill/start 생략, 바로 connect 시도
PORT=$(getprop service.adb.tls.port 2>/dev/null)
[ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=$(getprop service.adb.tcp.port 2>/dev/null)
[ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=5555

connected=false
for i in 1 2 3 4 5; do
    result=$(adb connect localhost:$PORT 2>&1)
    echo "$(date): connect #$i (port=$PORT): $result" >> "$LOG"
    if echo "$result" | grep -q "connected"; then
        connected=true
        break
    fi
    sleep 1
done

# 첫 연결 실패 시에만 ADB 서버 재시작
if ! $connected; then
    adb kill-server >> "$LOG" 2>&1
    sleep 1
    adb start-server >> "$LOG" 2>&1
    sleep 1
    for i in 1 2 3; do
        result=$(adb connect localhost:$PORT 2>&1)
        echo "$(date): retry #$i: $result" >> "$LOG"
        if echo "$result" | grep -q "connected"; then
            connected=true
            break
        fi
        sleep 1
    done
fi

if ! $connected; then
    termux-toast "T33A: ADB 연결 실패"
    echo "$(date): FAILED" >> "$LOG"
    exit 1
fi

# 기존 relay 죽이고 새 relay 띄움 (이중 fork로 PPID=1)
adb -s localhost:$PORT shell \
    "OLD=\$(cat $RELAY_PID_FILE 2>/dev/null); [ -n \"\$OLD\" ] && kill \$OLD 2>/dev/null; rm -f $RELAY_PID_FILE; (setsid /system/bin/sh $RELAY < /dev/null > /dev/null 2>&1 &)"
echo "$(date): old relay killed, new relay started" >> "$LOG"
sleep 2

termux-toast "T33A 재시작됨"
echo "$(date): done" >> "$LOG"
