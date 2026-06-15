#!/data/data/com.termux/files/usr/bin/bash
# T33A 통합 위젯 v3 — 원터치 복구 (3개 위젯 통합본)
# fast path: relay 살아있으면 cmd로 daemon 재시작
# slow path: relay 죽으면 TCP ADB로 relay 재기동
# 실패: 무선 디버깅 토글 안내 알림

RELAY_PID_FILE=/sdcard/Download/t33a_relay.pid
RELAY_SCRIPT=/sdcard/Download/t33a_relay.sh
CMD=/sdcard/Download/t33a.cmd
LOG=/sdcard/Download/t33a_boot.log
HB_FILE=/data/local/tmp/t33a.heartbeat
STATUS_FILE=/data/local/tmp/t33a.status
ADB=/data/data/com.termux/files/usr/bin/adb
BOOT_DIR="$HOME/.termux/boot"
# boot.sh 자동 설치 — start.sh가 Termux 유저로 실행되므로 ~/.termux/boot/ 접근 가능
[ -f /sdcard/Download/t33a_boot.sh ] && mkdir -p "$BOOT_DIR" && \
    cp /sdcard/Download/t33a_boot.sh "$BOOT_DIR/t33a_boot.sh" && \
    chmod +x "$BOOT_DIR/t33a_boot.sh" 2>/dev/null || true

log() { echo "$(date): $1" >> "$LOG"; }

# ── boot.sh watchdog 업그레이드 (구 버전 교체) ─────────────────
# start.sh는 Termux 유저로 실행 → ~/.termux/boot/ 쓰기 가능 + pgrep 가능
_OLD_BOOT=$(pgrep -f "t33a_boot.sh" 2>/dev/null | head -1)
if [ -n "$_OLD_BOOT" ]; then
    log "watchdog upgrade: killing old (PID $_OLD_BOOT)"
    kill "$_OLD_BOOT" 2>/dev/null
    sleep 1
fi
nohup bash "$BOOT_DIR/t33a_boot.sh" < /dev/null >> "$LOG" 2>&1 &
log "new boot.sh watchdog started (PID $!)"
unset _OLD_BOOT

echo "" >> "$LOG"
log "=== T33A 위젯 탭 ==="

# ── FINAL_SNIPER 위젯 복구 (심링크 아닌 실파일로 강제 재생성) ─
_SNIPER="$HOME/.shortcuts/FINAL_SNIPER"
rm -f "$_SNIPER"
cat > "$_SNIPER" << 'SNIPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~
export RISH_APPLICATION_ID="com.termux"
python hsc_master.py
SNIPER_EOF
chmod +x "$_SNIPER"
log "restored: FINAL_SNIPER (real file)"
unset _SNIPER

# ── 현재 상태 확인 ─────────────────────────────────────────────
STATUS=$(cat "$STATUS_FILE" 2>/dev/null | tr -d '\n' || echo "unknown")
HB_AGE=9999
if [ -f "$HB_FILE" ]; then
    MTIME=$(stat -c %Y "$HB_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    HB_AGE=$((NOW - MTIME))
fi

log "status=$STATUS hb_age=${HB_AGE}s"

# ── Fast path: relay 살아있으면 cmd로 daemon 재시작 ───────────
if [ "$HB_AGE" -lt 90 ]; then
    echo restart > "$CMD"
    sleep 2
    if [ ! -f "$CMD" ]; then
        STATUS_NEW=$(cat "$STATUS_FILE" 2>/dev/null | tr -d '\n' || echo "?")
        log "fast path OK — cmd consumed, status=$STATUS_NEW"
        termux-toast "T33A: $STATUS_NEW"
        exit 0
    fi
    rm -f "$CMD"
    log "fast path: cmd 미소비 (relay 무응답) — slow path로 전환"
fi

# ── Slow path: relay 죽음 → TCP 루프백 ADB로 재시작 (self-contained) ─
log "slow path — relay dead (hb_age=${HB_AGE}s)"
termux-toast "T33A: relay 재시작 중..."

STARTED=0

# ── TCP 루프백 ADB로 relay 재시작 (외부 앱 의존 0) ────────────────
if [ "$STARTED" = "0" ]; then
    ADB_TARGET=""
    PORT=$(getprop service.adb.tcp.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=$(getprop service.adb.tls.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=5555

    for i in 1 2 3 4 5; do
        result=$("$ADB" connect "localhost:$PORT" 2>&1)
        log "ADB connect #$i (port=$PORT): $result"
        if echo "$result" | grep -q "connected" && \
           "$ADB" -s "localhost:$PORT" shell echo ok > /dev/null 2>&1; then
            ADB_TARGET="localhost:$PORT"
            break
        fi
        sleep 1
    done

    if [ -z "$ADB_TARGET" ]; then
        log "ADB 없음 — 무선 디버깅 토글 안내"
        if command -v termux-notification >/dev/null 2>&1; then
            termux-notification \
                --id t33a_adb \
                --title "T33A: 무선 디버깅 토글 필요" \
                --content "개발자 옵션 -> 무선 디버깅 OFF->ON -> 다시 위젯 탭" \
                --priority high \
                --ongoing \
                --action "am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS" \
                2>/dev/null || termux-toast "무선 디버깅 OFF->ON 후 다시 탭"
        else
            termux-toast "무선 디버깅 OFF->ON 후 다시 탭"
        fi
        exit 1
    fi

    log "ADB OK ($ADB_TARGET) — relay 재시작"
    RPID=$(cat "$RELAY_PID_FILE" 2>/dev/null)
    [ -n "$RPID" ] && "$ADB" -s "$ADB_TARGET" shell \
        "kill $RPID 2>/dev/null; sleep 0.5; kill -9 $RPID 2>/dev/null" 2>/dev/null
    rm -f "$RELAY_PID_FILE"

    # 중복 daemon 제거 + stale hb 삭제 + 기동 모두 adb shell(shell 유저)로 — Termux 유저는 /data/local/tmp 쓰기 불가
    "$ADB" -s "$ADB_TARGET" shell \
        "pkill -x t33a_remap 2>/dev/null; rm -f /data/local/tmp/t33a.relay_hb; setsid /system/bin/sh '$RELAY_SCRIPT' < /dev/null > /dev/null 2>&1 &"
    sleep 6
    STARTED=1
fi

# 알림 정리
command -v termux-notification-remove >/dev/null 2>&1 && \
    termux-notification-remove t33a_adb 2>/dev/null || true

# 결과 확인
MTIME=$(stat -c %Y "$HB_FILE" 2>/dev/null || echo 0)
AGE=$(( $(date +%s) - MTIME ))
RPID=$(cat "$RELAY_PID_FILE" 2>/dev/null)
STATUS_NEW=$(cat "$STATUS_FILE" 2>/dev/null | tr -d '\n' || echo "?")

if [ "$AGE" -lt 30 ]; then
    log "relay 재시작 성공 (PID $RPID, hb_age ${AGE}s, status=$STATUS_NEW)"
    termux-toast "T33A: 재시작됨 ($STATUS_NEW)"
else
    log "relay 재시작 불확실 (PID $RPID, hb_age ${AGE}s)"
    termux-toast "T33A: 재시작됨 (확인 필요)"
fi
