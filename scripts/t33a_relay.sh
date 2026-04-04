#!/system/bin/sh
# T33A Relay — shell유저 상주 프로세스
# 역할 1: 위젯 명령 수신 (t33a.cmd 파일 감시)
# 역할 2: 데몬 watchdog (5초 간격)
# 시작: setsid nohup t33a_relay.sh < /dev/null > /dev/null 2>&1 &

BIN=/data/local/tmp/t33a_remap
CMD=/data/local/tmp/t33a.cmd
LOG=/sdcard/Download/t33a.log
RELAY_PID=/data/local/tmp/t33a_relay.pid

# 중복 실행 방지
if [ -f "$RELAY_PID" ]; then
    OLD=$(cat "$RELAY_PID")
    kill -0 "$OLD" 2>/dev/null && exit 0
fi
echo "$$" > "$RELAY_PID"
trap "" HUP

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') relay: $1" >> "$LOG"; }
log "started (PID $$)"

restart_daemon() {
    pkill -x t33a_remap 2>/dev/null
    sleep 1
    rm -f /data/local/tmp/t33a.pid
    "$BIN"
    sleep 2
}

while true; do
    # 위젯 명령 처리
    if [ -f "$CMD" ]; then
        rm -f "$CMD"
        log "widget command — restarting daemon"
        restart_daemon
        continue
    fi

    # watchdog
    PID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
    if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
        log "daemon dead — restarting"
        restart_daemon
    fi

    sleep 5
done
