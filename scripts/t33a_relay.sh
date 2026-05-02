#!/system/bin/sh
# T33A Relay — shell 유저(uid 2000) 상주 프로세스
# 시작: ADB로 한번만 (setsid nohup ... &) → PPID=1 → USB/ADB 종료 후에도 영구 생존
# 역할 1: t33a_remap watchdog (5초 간격)
# 역할 2: 위젯 명령 수신 (t33a.cmd 파일 감시, 1초)
# 역할 3: heartbeat staleness 감지 → hung 상태 postmortem + 재시작

BIN=/data/local/tmp/t33a_remap
CMD=/sdcard/Download/t33a.cmd
LOG=/sdcard/Download/t33a.log
RELAY_PID=/sdcard/Download/t33a_relay.pid   # /sdcard: Termux boot.sh가 읽기 가능
HEARTBEAT=/data/local/tmp/t33a.heartbeat
STATUS=/data/local/tmp/t33a.status
POSTMORTEM_DIR=/sdcard/Download
HEARTBEAT_STALE_SEC=180   # heartbeat 60s × 3 = 3분 이상 없으면 hung

# 중복 실행 방지
if [ -f "$RELAY_PID" ]; then
    OLD=$(cat "$RELAY_PID")
    kill -0 "$OLD" 2>/dev/null && exit 0
fi
echo "$$" > "$RELAY_PID"
trap "" HUP

# 로그 로테이션: 1MB 넘으면 마지막 500줄만 유지
rotate_log() {
    local size=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
    if [ "$size" -gt 1048576 ]; then
        tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
}
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') relay: $1" >> "$LOG"
    LOG_TICK=$((${LOG_TICK:-0} + 1))
    [ $((LOG_TICK % 100)) -eq 0 ] && rotate_log
}
log "started (PID $$, uid=$(id -u))"

restart_daemon() {
    pkill -x t33a_remap 2>/dev/null
    sleep 1
    pkill -9 -x t33a_remap 2>/dev/null
    sleep 1
    rm -f /data/local/tmp/t33a.pid
    "$BIN"
    sleep 2
}

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

is_heartbeat_stale() {
    [ ! -f "$HEARTBEAT" ] && return 1
    local mtime=$(stat -c %Y "$HEARTBEAT" 2>/dev/null || echo 0)
    local now=$(date +%s)
    local age=$((now - mtime))
    [ "$age" -gt "$HEARTBEAT_STALE_SEC" ]
}

log "starting daemon"
restart_daemon

log "watchdog loop started"
tick=0
hung_postmortem_done=0
while true; do
    if [ -f "$CMD" ]; then
        CMD_VAL=$(cat "$CMD" 2>/dev/null)
        rm -f "$CMD"
        log "widget command [$CMD_VAL] — restarting daemon"
        capture_postmortem "manual"
        restart_daemon
        hung_postmortem_done=0
        tick=0
        continue
    fi

    if [ $tick -ge 5 ]; then
        PID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
        if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
            log "daemon dead — capturing postmortem then restarting"
            capture_postmortem "dead"
            restart_daemon
            hung_postmortem_done=0
        elif is_heartbeat_stale; then
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
