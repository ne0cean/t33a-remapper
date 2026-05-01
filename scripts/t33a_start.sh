#!/data/data/com.termux/files/usr/bin/bash
# T33A 위젯 — 원터치 재시작
# Fast path: relay 살아있으면 cmd 파일로 재시작 신호 (1초)
# Slow path: relay 죽어있으면 Termux에서 직접 재시작 (ADB 불필요)

CMD=/sdcard/Download/t33a.cmd
LOG=/sdcard/Download/t33a_boot.log
RELAY=/data/local/tmp/t33a_relay.sh
RELAY_PID=/sdcard/Download/t33a_relay.pid

echo "" >> "$LOG"
echo "$(date): === widget tap ===" >> "$LOG"

# ── Fast path: relay 살아있으면 cmd로 신호 ──────────────────────
echo restart > "$CMD"
sleep 1.5
if [ ! -f "$CMD" ]; then
    # relay가 cmd 소비 = 살아있음
    echo "$(date): fast path — relay alive" >> "$LOG"
    sleep 2
    HB_MTIME=$(stat -c %Y /data/local/tmp/t33a.heartbeat 2>/dev/null || echo 0)
    NOW=$(date +%s)
    STATE=$(cat /data/local/tmp/t33a.status 2>/dev/null || echo unknown)
    if [ $((NOW - HB_MTIME)) -le 15 ] 2>/dev/null; then
        timeout 3 termux-toast "T33A 재시작됨 ($STATE)"
    else
        timeout 3 termux-toast "T33A: 데몬 응답 없음"
    fi
    exit 0
fi

# ── Slow path: relay 죽어있음 — Termux에서 직접 재시작 ──────────
rm -f "$CMD"
echo "$(date): slow path — relay dead, restarting directly" >> "$LOG"
timeout 3 termux-toast "T33A: 초기화 중..."

OLD=$(cat "$RELAY_PID" 2>/dev/null)
[ -n "$OLD" ] && kill "$OLD" 2>/dev/null
rm -f "$RELAY_PID"
(setsid /system/bin/sh "$RELAY" < /dev/null > /dev/null 2>&1 &)

sleep 5
RPID=$(cat "$RELAY_PID" 2>/dev/null)
if [ -n "$RPID" ] && kill -0 "$RPID" 2>/dev/null; then
    echo "$(date): relay restarted (PID $RPID)" >> "$LOG"
    timeout 3 termux-toast "T33A 재시작됨"
else
    echo "$(date): FAILED — relay did not start" >> "$LOG"
    timeout 3 termux-toast "T33A: 시작 실패"
fi
