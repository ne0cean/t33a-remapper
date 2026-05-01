#!/data/data/com.termux/files/usr/bin/bash
# T33A 위젯 — 원터치 재시작
# Fast path: boot.sh 살아있으면 cmd 파일로 신호
# Slow path: boot.sh 죽어있으면 직접 재시작

CMD=/sdcard/Download/t33a.cmd
LOG=/sdcard/Download/t33a_boot.log
BOOT=/sdcard/Download/t33a_boot.sh
RELAY_PID=/sdcard/Download/t33a_relay.pid

echo "" >> "$LOG"
echo "$(date): === widget tap ===" >> "$LOG"

# ── Fast path ──────────────────────────────────────────────────
echo restart > "$CMD"
sleep 1.5
if [ ! -f "$CMD" ]; then
    echo "$(date): fast path — boot.sh alive" >> "$LOG"
    sleep 2
    STATE=$(cat /data/local/tmp/t33a.status 2>/dev/null || echo unknown)
    timeout 3 termux-toast "T33A 재시작됨 ($STATE)"
    exit 0
fi

# ── Slow path: boot.sh 죽어있음 ────────────────────────────────
rm -f "$CMD"
echo "$(date): slow path — boot.sh dead, restarting" >> "$LOG"
timeout 3 termux-toast "T33A: 초기화 중..."

OLD=$(cat "$RELAY_PID" 2>/dev/null)
[ -n "$OLD" ] && kill "$OLD" 2>/dev/null
rm -f "$RELAY_PID"

(setsid bash "$BOOT" < /dev/null >> "$LOG" 2>&1 &)

sleep 5
RPID=$(cat "$RELAY_PID" 2>/dev/null)
if [ -n "$RPID" ] && kill -0 "$RPID" 2>/dev/null; then
    echo "$(date): boot.sh restarted (PID $RPID)" >> "$LOG"
    timeout 3 termux-toast "T33A 재시작됨"
else
    echo "$(date): FAILED" >> "$LOG"
    timeout 3 termux-toast "T33A: 시작 실패"
fi
