#!/system/bin/sh
# T33A Relay — shell유저 상주 프로세스
# 역할 1: 위젯 명령 수신 (t33a.cmd 파일 감시)
# 역할 2: 데몬 watchdog (5초 간격)
# 시작: setsid nohup t33a_relay.sh < /dev/null > /dev/null 2>&1 &

BIN=/data/local/tmp/t33a_remap
CMD=/sdcard/Download/t33a.cmd  # /sdcard로: Termux와 shell 둘 다 write 가능
LOG=/sdcard/Download/t33a.log
RELAY_PID=/data/local/tmp/t33a_relay.pid
HEARTBEAT=/data/local/tmp/t33a.heartbeat
STATUS=/data/local/tmp/t33a.status
POSTMORTEM_DIR=/sdcard/Download
HEARTBEAT_STALE_SEC=180   # 3분 이상 heartbeat 없으면 hung 판정 (heartbeat 60s × 3)

# 중복 실행 방지
if [ -f "$RELAY_PID" ]; then
    OLD=$(cat "$RELAY_PID")
    kill -0 "$OLD" 2>/dev/null && exit 0
fi
echo "$$" > "$RELAY_PID"
trap "" HUP

# 로그 로테이션: 1MB 넘으면 마지막 500줄만 유지 (로그 무한 증가 방지)
rotate_log() {
    local size=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
    if [ "$size" -gt 1048576 ]; then
        tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
}
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') relay: $1" >> "$LOG"
    # 매 100번째 로그마다 사이즈 체크
    LOG_TICK=$((${LOG_TICK:-0} + 1))
    [ $((LOG_TICK % 100)) -eq 0 ] && rotate_log
}
log "started (PID $$)"

restart_daemon() {
    pkill -x t33a_remap 2>/dev/null
    sleep 1
    # SIGTERM 후에도 살아있으면 SIGKILL
    pkill -9 -x t33a_remap 2>/dev/null
    sleep 1
    rm -f /data/local/tmp/t33a.pid
    "$BIN"
    sleep 2
}

# 데몬 죽음/응답불능 감지 시 진단 데이터 즉시 캡처.
# 다음 사건 발생 시 진범 식별을 위해 logcat/dmesg/heartbeat/메모리 스냅샷을 보존.
# 사유: $1 = "dead" | "hung" | "manual"
capture_postmortem() {
    REASON="$1"
    TS=$(date '+%Y%m%d_%H%M%S')
    PM="$POSTMORTEM_DIR/t33a_postmortem_${TS}_${REASON}.log"
    {
        echo "=== T33A POSTMORTEM ($REASON) ==="
        echo "captured: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "uptime: $(uptime)"
        echo
        echo "--- last status ---"
        cat "$STATUS" 2>/dev/null || echo "(no status file)"
        echo
        echo "--- last heartbeat ---"
        cat "$HEARTBEAT" 2>/dev/null || echo "(no heartbeat file)"
        echo "heartbeat mtime: $(stat -c '%y' "$HEARTBEAT" 2>/dev/null || echo unknown)"
        echo
        echo "--- pid file ---"
        cat /data/local/tmp/t33a.pid 2>/dev/null || echo "(no pid file)"
        echo
        echo "--- t33a processes ---"
        ps -ef 2>/dev/null | grep -E 't33a' | grep -v grep
        echo
        echo "--- recent t33a.log (last 30 lines) ---"
        tail -30 "$LOG" 2>/dev/null
        echo
        echo "--- memory ---"
        cat /proc/meminfo 2>/dev/null | head -5
        echo
        echo "--- input devices (T33A visible?) ---"
        for ev in /dev/input/event*; do
            NAME=$(cat "/sys/class/input/$(basename $ev)/device/name" 2>/dev/null)
            echo "$ev: $NAME"
        done | grep -iE 't33a|^$' || echo "(no T33A device found)"
        echo
        echo "--- logcat last 500 lines (t33a/oom/kill/signal/bluetooth) ---"
        logcat -d -t 500 2>/dev/null | grep -iE 't33a|oom|killing|signal|lowmem|bluetooth' | tail -100
        echo
        echo "--- dmesg recent (kernel events) ---"
        dmesg 2>/dev/null | tail -50
        echo "=== END POSTMORTEM ==="
    } > "$PM" 2>&1
    log "postmortem saved: $PM ($REASON)"
}

# heartbeat staleness check — 데몬 살아있어도 hung 상태면 잡아냄
is_heartbeat_stale() {
    [ ! -f "$HEARTBEAT" ] && return 1   # heartbeat 파일 없으면 (구버전 데몬) skip
    local mtime=$(stat -c %Y "$HEARTBEAT" 2>/dev/null || echo 0)
    local now=$(date +%s)
    local age=$((now - mtime))
    [ "$age" -gt "$HEARTBEAT_STALE_SEC" ]
}

tick=0
hung_postmortem_done=0
while true; do
    # 위젯 명령 처리 (1초마다 — 위젯 fast path 응답성)
    if [ -f "$CMD" ]; then
        CMD_VAL=$(cat "$CMD" 2>/dev/null)
        rm -f "$CMD"
        log "widget command [$CMD_VAL] — restarting daemon"
        # 위젯이 명시적으로 재시작 요청 시에도 직전 상태 보존 (왜 사용자가 탭했는지 단서)
        capture_postmortem "manual"
        restart_daemon
        hung_postmortem_done=0
        tick=0
        continue
    fi

    # watchdog (5초마다 — 데몬 헬스체크)
    if [ $tick -ge 5 ]; then
        PID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
        if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
            log "daemon dead — capturing postmortem then restarting"
            capture_postmortem "dead"
            restart_daemon
            hung_postmortem_done=0
        elif is_heartbeat_stale; then
            # 프로세스는 살아있는데 heartbeat 끊김 = hung 상태 (BLE deadlock 등)
            # 같은 hung 상태에서 매 5초마다 postmortem 찍지 않도록 1회만
            if [ "$hung_postmortem_done" -eq 0 ]; then
                log "daemon hung (heartbeat stale) — capturing postmortem then restarting"
                capture_postmortem "hung"
                restart_daemon
                hung_postmortem_done=1
            fi
        else
            hung_postmortem_done=0
        fi
        tick=0
    fi

    sleep 1
    tick=$((tick + 1))
done
