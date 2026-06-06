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
RISH=/data/local/tmp/rish

log() { echo "$(date): $1" >> "$LOG"; }

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

# ── Slow path: relay 죽음 → rish(PRIMARY) 또는 ADB(FALLBACK)로 재시작 ─
log "slow path — relay dead (hb_age=${HB_AGE}s)"
termux-toast "T33A: relay 재시작 중..."

STARTED=0

# ── 1) rish (Shizuku) — Termux 유저로 실행 → Shizuku cgroup → USB 분리 무관 ──
log "rish_check: f=$([ -f "$RISH" ] && echo y || echo n) x=$([ -x "$RISH" ] && echo y || echo x) path=$RISH"
if [ -f "$RISH" ] && [ -x "$RISH" ]; then
    if RISH_APPLICATION_ID="com.termux" "$RISH" -c "echo ok" > /dev/null 2>&1; then
        log "rish available — starting relay via Shizuku cgroup"
        RPID=$(cat "$RELAY_PID_FILE" 2>/dev/null)
        [ -n "$RPID" ] && kill "$RPID" 2>/dev/null
        rm -f "$RELAY_PID_FILE"
        RISH_APPLICATION_ID="com.termux" "$RISH" -c \
            "setsid /system/bin/sh '$RELAY_SCRIPT' < /dev/null > /dev/null 2>&1 &"
        sleep 6
        MTIME=$(stat -c %Y "$HB_FILE" 2>/dev/null || echo 0)
        AGE=$(( $(date +%s) - MTIME ))
        if [ "$AGE" -lt 30 ]; then
            log "relay via rish OK (hb_age ${AGE}s)"
            STARTED=1
        else
            log "relay via rish FAILED (hb_age ${AGE}s) — falling back to ADB"
        fi
    else
        log "rish/Shizuku not available — trying ADB"
    fi
fi

# ── 2) ADB fallback ──────────────────────────────────────────────
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

    "$ADB" -s "$ADB_TARGET" shell \
        "setsid /system/bin/sh '$RELAY_SCRIPT' < /dev/null > /dev/null 2>&1 &"
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
