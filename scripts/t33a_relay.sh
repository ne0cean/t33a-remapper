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
RELAY_HB=/data/local/tmp/t33a.relay_hb      # relay 자체 heartbeat (10s) — boot.sh fast 감지용
STATUS=/data/local/tmp/t33a.status
POSTMORTEM_DIR=/sdcard/Download
HEARTBEAT_STALE_SEC=180   # heartbeat 60s × 3 = 3분 이상 없으면 hung
BATTERY_LOG_INTERVAL=300  # 5분마다 배터리/절전 상태 로그
WIFI_POLICY_INTERVAL=60   # 무선 디버깅 정책 점검 간격(초)
WADB_CHECK_INTERVAL=600   # WADB Keeper 비활성화 점검 간격(초)
# 무선 디버깅을 켜 둘 Wi-Fi(공백 구분, 2026-10-25 의장 결정: 집·회사). 폰은 허용을 공유기마다 따로 묻기 때문에
# 이 밖의 Wi-Fi 에서는 끈다. 단 5555 가 닫혀 있으면(재부팅 뒤) 복구 경로라서 어느 Wi-Fi 든 건드리지 않는다.
WIFI_DEBUG_SSIDS="NOIR_5G twnap"
WADB_PKG=com.ateam.wadbkeeper

# 중복 실행 방지
if [ -f "$RELAY_PID" ]; then
    OLD=$(cat "$RELAY_PID")
    kill -0 "$OLD" 2>/dev/null && exit 0
fi
echo "$$" > "$RELAY_PID"
echo "$$" > /data/local/tmp/t33a_relay.pid   # 구버전 boot.sh 호환성
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
    # /sdcard/Download에 새 바이너리가 있으면 교체 (boot.sh/update.sh가 거기에 빌드)
    BIN_SRC=/sdcard/Download/t33a_remap
    if [ -f "$BIN_SRC" ]; then
        pkill -x t33a_remap 2>/dev/null; sleep 1; pkill -9 -x t33a_remap 2>/dev/null; sleep 1
        cp "$BIN_SRC" "$BIN" && chmod +x "$BIN"
        rm -f "$BIN_SRC"
        log "binary updated from $BIN_SRC"
    else
        pkill -x t33a_remap 2>/dev/null
        sleep 1
        pkill -9 -x t33a_remap 2>/dev/null
        sleep 1
    fi
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

# 배터리/절전/BLE 상태 스냅샷 — 문제 발생 시 원인 추적용
log_power_state() {
    local tag="${1:-periodic}"
    local batt=$(dumpsys battery 2>/dev/null | grep ' level:' | tr -d ' ' | cut -d: -f2)
    local low=$(settings get global low_power 2>/dev/null)
    local status=$(cat "$STATUS" 2>/dev/null | tr -d '\n' || echo unknown)
    local hb=$(cat "$HEARTBEAT" 2>/dev/null | tr -d '\n' || echo none)
    log "power[$tag] battery=${batt}% low_power=${low} daemon=${status} heartbeat=${hb}"
}

# heartbeat 상태 변화 감지용 이전 값 추적
LAST_HB_STATE=""

is_heartbeat_stale() {
    [ ! -f "$HEARTBEAT" ] && return 1
    local mtime=$(stat -c %Y "$HEARTBEAT" 2>/dev/null || echo 0)
    local now=$(date +%s)
    local age=$((now - mtime))
    [ "$age" -gt "$HEARTBEAT_STALE_SEC" ]
}

# 현재 Wi-Fi 이름. 연결 안 됨이면 빈 값.
current_ssid() {
    cmd wifi status 2>/dev/null | sed -n 's/^Wifi is connected to "\(.*\)"$/\1/p' | head -1
}

# 지정 Wi-Fi 면 무선 디버깅을 켜 두고, 아니면 끈다(5555 열림일 때만). Wi-Fi 없음이면 손대지 않는다.
wifi_debug_policy() {
    local ssid cur port s allowed=0
    ssid=$(current_ssid)
    [ -z "$ssid" ] && return 0
    for s in $WIFI_DEBUG_SSIDS; do [ "$s" = "$ssid" ] && allowed=1; done
    cur=$(settings get global adb_wifi_enabled 2>/dev/null)
    port=$(getprop service.adb.tcp.port 2>/dev/null)
    if [ "$allowed" = 1 ] && [ "$cur" != "1" ]; then
        settings put global adb_wifi_enabled 1 && log "wifi policy: [$ssid] 지정 Wi-Fi — 무선 디버깅 켬"
    elif [ "$allowed" = 0 ] && [ "$cur" = "1" ] && [ "$port" = "5555" ]; then
        settings put global adb_wifi_enabled 0 && log "wifi policy: [$ssid] 지정 밖 Wi-Fi — 무선 디버깅 끔(5555 유지)"
    fi
}

# 삼성·안드로이드가 쓰지 않는 앱으로 보고 WADB Keeper 를 '쓸 때까지 비활성'(enabled=4)으로 돌리면
# 부팅 신호도 킥도 못 받아 재부팅 복구가 끊긴다(2026-10-24 재부팅 30시간 다운의 원인).
# 셸은 pm enable 권한이 없지만 앱 화면을 한 번 띄우면 '사용'으로 돌아온다(10-25 실측: 4 → 0).
wadb_keeper_revive() {
    local st
    st=$(dumpsys package "$WADB_PKG" 2>/dev/null | sed -n 's/.*User 0:.*enabled=\([0-9]\).*/\1/p' | head -1)
    [ "$st" = "4" ] || return 0
    am start --user 0 -n "$WADB_PKG/.Main" >/dev/null 2>&1
    log "WADB Keeper 비활성(enabled=4) 감지 — 앱 화면 실행으로 되살림"
}

# relay 재시작 시 daemon이 살아있으면 건드리지 않음 (BLE 연결 유지)
EXISTING_PID=$(cat /data/local/tmp/t33a.pid 2>/dev/null)
if [ -n "$EXISTING_PID" ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    log "daemon already running (PID $EXISTING_PID) — skipping startup restart"
    LAST_HB_STATE=$(cat "$HEARTBEAT" 2>/dev/null | awk '{print $3}')
else
    log "starting daemon"
    log_power_state "startup"
    restart_daemon
fi

log "watchdog loop started"
tick=0
battery_tick=0
wifi_tick=$WIFI_POLICY_INTERVAL   # 기동 직후 첫 틱에 바로 점검
wadb_tick=$WADB_CHECK_INTERVAL
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
            log_power_state "daemon_dead"
            capture_postmortem "dead"
            restart_daemon
            hung_postmortem_done=0
        elif is_heartbeat_stale; then
            if [ "$hung_postmortem_done" -eq 0 ]; then
                log "daemon hung (heartbeat stale) — capturing postmortem then restarting"
                log_power_state "daemon_hung"
                capture_postmortem "hung"
                restart_daemon
                hung_postmortem_done=1
            fi
        else
            hung_postmortem_done=0
            # heartbeat 상태 변화 감지 — BLE 연결/끊김 전환 시 배터리 스냅샷
            CUR_HB=$(cat "$HEARTBEAT" 2>/dev/null | awk '{print $3}')
            if [ -n "$CUR_HB" ] && [ "$CUR_HB" != "$LAST_HB_STATE" ]; then
                log_power_state "hb_change:${LAST_HB_STATE}->${CUR_HB}"
                LAST_HB_STATE="$CUR_HB"
            fi
        fi
        tick=0
    fi

    # 10초마다 relay 자체 heartbeat 갱신 (boot.sh watchdog 빠른 감지용)
    touch "$RELAY_HB" 2>/dev/null

    # 5분마다 배터리/절전 상태 정기 기록
    battery_tick=$((battery_tick + 1))
    if [ "$battery_tick" -ge "$BATTERY_LOG_INTERVAL" ]; then
        log_power_state "periodic"
        battery_tick=0
    fi

    wifi_tick=$((wifi_tick + 1))
    if [ "$wifi_tick" -ge "$WIFI_POLICY_INTERVAL" ]; then
        wifi_debug_policy
        wifi_tick=0
    fi
    wadb_tick=$((wadb_tick + 1))
    if [ "$wadb_tick" -ge "$WADB_CHECK_INTERVAL" ]; then
        wadb_keeper_revive
        wadb_tick=0
    fi

    sleep 1
    tick=$((tick + 1))
done
