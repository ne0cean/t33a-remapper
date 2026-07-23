#!/data/data/com.termux/files/usr/bin/bash
# T33A — Termux:Boot 자동 시작
# Termux 유저(u0_a533)로 실행 → termux-wake-lock으로 Samsung kill 방지
#
# 구조:
#   boot.sh (Termux 유저, 영구 상주) → ADB → relay.sh (shell 유저, PPID=1 영구 생존)
#   relay.sh가 t33a_remap watchdog (shell 유저 → /dev/input + /dev/uinput 접근 가능)
#
# relay가 PPID=1이면 USB/ADB 종료 후에도 살아있음 (실증 확인됨).
# boot.sh의 ADB는 relay 최초 시작 + 재시작 시에만 필요.
# WiFi ADB 없을 때: deeplink 알림으로 사용자에게 무선 디버깅 토글 1회 안내.

LOG=/sdcard/Download/t33a_boot.log
RELAY_SCRIPT=/sdcard/Download/t33a_relay.sh
RELAY_PID=/sdcard/Download/t33a_relay.pid   # /sdcard: boot.sh(Termux)가 /proc 없이도 읽기 가능
BIN_SRC=/sdcard/Download/t33a_remap
BIN_DST=/data/local/tmp/t33a_remap
SRC=/sdcard/Download/t33a_boot.sh
BOOT_DIR="$HOME/.termux/boot"
SHORTCUT_DIR="$HOME/.shortcuts"
WRAPPER=/sdcard/Download/T33A_wrapper
ADB=/data/data/com.termux/files/usr/bin/adb
NOTIFY_FLAG=/sdcard/Download/t33a_notify_ts
AUTO_PULL="$HOME/t33a-remapper/scripts/t33a_auto_pull.sh"

# ── 자체 설치/업데이트 ─────────────────────────────────────────
mkdir -p "$BOOT_DIR" "$SHORTCUT_DIR" 2>/dev/null
[ -f "$SRC" ] && cp "$SRC" "$BOOT_DIR/t33a_boot.sh" && chmod +x "$BOOT_DIR/t33a_boot.sh"
# 바이너리 복사는 relay(shell 유저)가 담당 — Termux 유저가 직접 하면 "text file busy"
# BIN_SRC가 있으면 relay가 다음 watchdog 사이클에 자동 교체
[ -f "$RELAY_SCRIPT" ] && chmod +x "$RELAY_SCRIPT"
# 불필요한 위젯 정리 후 T33A 1개만 설치
if [ -f "$WRAPPER" ]; then
    ls "$SHORTCUT_DIR/" 2>/dev/null | while read f; do
        [ "$f" = "T33A" ] && continue
        [ "$f" = "FINAL_SNIPER" ] && continue  # HSC 위젯 보존
        [ "$f" = "NET_DIAG" ] && continue      # 네트워크 진단 위젯 보존 (2026-07-23)
        [ "$f" = "termux_ctrl_restart" ] && continue  # 브리지 수동 복구 위젯 보존
        rm -f "$SHORTCUT_DIR/$f"
        echo "$(date): removed shortcut: $f" >> "$LOG"
    done
    cp "$WRAPPER" "$SHORTCUT_DIR/T33A" && chmod +x "$SHORTCUT_DIR/T33A"
fi

# FINAL_SNIPER 항상 보장 (HSC 프로젝트 위젯 — 부팅 시 삭제 방지)
_SNIPER="$SHORTCUT_DIR/FINAL_SNIPER"
if [ ! -f "$_SNIPER" ]; then
    cat > "$_SNIPER" << 'SNIPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~
export RISH_APPLICATION_ID="com.termux"
python hsc_master.py
SNIPER_EOF
    chmod +x "$_SNIPER"
    echo "$(date): restored FINAL_SNIPER" >> "$LOG"
fi
unset _SNIPER

echo "$(date): boot started (PID $$)" > "$LOG"
termux-wake-lock
echo "$(date): wake lock acquired" >> "$LOG"

# ── auto_pull 백그라운드 시작 (GitHub 변경 감지 → 자동 업데이트) ────────
if [ -f "$AUTO_PULL" ]; then
    # 이미 실행 중이면 skip
    if ! pgrep -f "t33a_auto_pull" > /dev/null 2>&1; then
        bash "$AUTO_PULL" &
        echo "$(date): auto_pull started (PID $!)" >> "$LOG"
    fi
fi

# ── ADB 연결 (USB 우선, WiFi 차선) ────────────────────────────
ADB_TARGET=""

connect_adb() {
    # 1) TCP 루프백 (폰 자체 adbd) — PRIMARY.
    #    relay가 USB 분리에도 살아남는 cgroup은 폰 내장 adbd(루프백)뿐.
    #    USB로 띄운 relay는 선 뽑으면 cgroup째 죽으므로 루프백을 먼저 잡는다.
    PORT=$(getprop service.adb.tls.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=$(getprop service.adb.tcp.port 2>/dev/null)
    [ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT=5555
    "$ADB" connect "localhost:$PORT" > /dev/null 2>&1
    sleep 1
    if "$ADB" -s "localhost:$PORT" shell echo ok > /dev/null 2>&1; then
        ADB_TARGET="localhost:$PORT"
        echo "$(date): ADB loopback (localhost:$PORT)" >> "$LOG"
        return 0
    fi

    # 2) USB ADB FALLBACK — 부트스트랩 전용(USB 분리 시 죽음, 루프백 안 될 때만)
    if "$ADB" devices 2>/dev/null | grep -qE '^[A-Za-z0-9]+.*device$'; then
        USB_DEV=$("$ADB" devices 2>/dev/null | grep -E '^[A-Za-z0-9]+.*device$' | grep -v localhost | awk '{print $1}' | head -1)
        if [ -n "$USB_DEV" ] && "$ADB" -s "$USB_DEV" shell echo ok > /dev/null 2>&1; then
            ADB_TARGET="$USB_DEV"
            echo "$(date): USB ADB ($USB_DEV) — WARN: USB 분리 시 죽음" >> "$LOG"
            return 0
        fi
    fi

    ADB_TARGET=""
    return 1
}

notify_adb_needed() {
    NOW=$(date +%s)
    LAST=$(cat "$NOTIFY_FLAG" 2>/dev/null || echo 0)
    [ $((NOW - LAST)) -lt 60 ] && return
    echo "$NOW" > "$NOTIFY_FLAG"
    echo "$(date): notifying user — WiFi ADB toggle needed" >> "$LOG"
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification \
            --id t33a_adb \
            --title "T33A: 무선 디버깅 켜기 필요" \
            --content "개발자 옵션 → 무선 디버깅 OFF→ON 1회 토글 후 자동 복구" \
            --priority high \
            --action "am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS" \
            2>/dev/null || true
    else
        timeout 3 termux-toast "T33A: 개발자 옵션 → 무선 디버깅 토글 필요" 2>/dev/null || true
    fi
}

# ── 무선 디버깅 자동 ON ────────────────────────────────────────
# Android는 재부팅마다 wireless debugging을 끔 → loopback ADB 불가로 복구 실패.
# Termux에 WRITE_SECURE_SETTINGS가 부여되어 있으면 여기서 직접 재활성화.
# (1회 부여: adb shell pm grant com.termux android.permission.WRITE_SECURE_SETTINGS)
# Termux 유저의 system binary 실행은 기기/버전에 따라 경로가 달라 다중 프로브로 탐지.
SETTINGS_CMD=""
_WADB_DEAD=""
_detect_settings() {
    for c in \
        "settings" \
        "/system/bin/settings" \
        "env -u LD_PRELOAD /system/bin/settings" \
        "/system/bin/cmd settings" \
        "env -u LD_PRELOAD /system/bin/cmd settings"; do
        V=$(eval "$c get global adb_wifi_enabled" 2>&1)
        case "$V" in
            0|1|null)
                SETTINGS_CMD="$c"
                echo "$(date): settings 실행경로 확정: [$c] (adb_wifi_enabled=$V)" >> "$LOG"
                return 0 ;;
        esac
        echo "$(date): settings probe fail [$c]: $(echo "$V" | head -1)" >> "$LOG"
    done
    return 1
}
enable_wireless_adb() {
    [ -n "$_WADB_DEAD" ] && return 1
    if [ -z "$SETTINGS_CMD" ]; then
        if ! _detect_settings; then
            echo "$(date): enable_wireless_adb 사용 불가 — 모든 settings 실행경로 실패 (이 세션에서 재시도 안 함)" >> "$LOG"
            _WADB_DEAD=1
            return 1
        fi
    fi
    CUR=$(eval "$SETTINGS_CMD get global adb_wifi_enabled" 2>/dev/null)
    [ "$CUR" = "1" ] && return 0
    ERR=$(eval "$SETTINGS_CMD put global adb_wifi_enabled 1" 2>&1)
    if [ "$(eval "$SETTINGS_CMD get global adb_wifi_enabled" 2>/dev/null)" = "1" ]; then
        echo "$(date): wireless debugging re-enabled (adb_wifi_enabled ${CUR:-?}→1)" >> "$LOG"
        sleep 3   # adbd TLS 서버 기동 대기
        return 0
    fi
    echo "$(date): settings put 실패 — WRITE_SECURE_SETTINGS 미부여? ($(echo "$ERR" | head -1))" >> "$LOG"
    return 1
}

# ── relay heartbeat 확인 헬퍼 ──────────────────────────────────
_relay_alive() {
    HB_FILE=/data/local/tmp/t33a.heartbeat
    [ -f "$HB_FILE" ] || return 1
    MTIME=$(stat -c %Y "$HB_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    AGE=$((NOW - MTIME))
    [ "$AGE" -lt 180 ]
}

_relay_check_start() {
    # 시작 후 3초 대기 → relay_hb(relay.sh 매초 갱신) 확인
    # relay_hb는 relay 시작 후 ~1s 내 최초 기록 → 3s면 충분
    # 주의: t33a.heartbeat는 daemon이 60초마다 갱신 → 부팅 직후 항상 stale → 사용 금지
    sleep 3
    HB_FILE=/data/local/tmp/t33a.relay_hb
    [ ! -f "$HB_FILE" ] && HB_FILE=/data/local/tmp/t33a.heartbeat
    MTIME=$(stat -c %Y "$HB_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    AGE=$((NOW - MTIME))
    RPID=$(cat "$RELAY_PID" 2>/dev/null)
    if [ "$AGE" -lt 30 ]; then
        echo "$(date): relay started OK (PID $RPID, relay_hb age ${AGE}s)" >> "$LOG"
        rm -f "$NOTIFY_FLAG"
        return 0
    fi
    echo "$(date): relay start failed (PID $RPID, relay_hb age ${AGE}s)" >> "$LOG"
    return 1
}

# ── ADB(TCP 루프백) 경유 relay 시작 (self-contained) ───────────
start_relay() {
    [ -z "$ADB_TARGET" ] && return 1

    echo "$(date): starting relay via ADB ($ADB_TARGET)" >> "$LOG"
    rm -f "$RELAY_PID"   # /sdcard: Termux 유저 쓰기 가능

    # ⚠️ 정리·stale hb 삭제·기동을 모두 adb shell(=shell 유저)로 수행.
    #    /data/local/tmp = 0771 shell:shell → Termux 유저는 그 안 파일 rm 불가(과거 회귀버그).
    #    pkill -x: 정확한 프로세스명만 → 이 launcher 셸(cmdline에 t33a_remap 문자열 포함) 자기-kill 방지.
    #    setsid: 새 세션 → PPID=1 고아화 (USB/ADB 종료 후 생존).
    "$ADB" -s "$ADB_TARGET" shell \
        "pkill -x t33a_remap 2>/dev/null; rm -f /data/local/tmp/t33a.relay_hb; setsid /system/bin/sh '$RELAY_SCRIPT' < /dev/null > /dev/null 2>&1 &"

    _relay_check_start
}

# ── 초기 시작 ──────────────────────────────────────────────────
# relay가 이미 살아있으면 시작 루프 스킵 (watchdog 재시작 시 즉시 진입)
_HB_Q=/data/local/tmp/t33a.relay_hb
[ ! -f "$_HB_Q" ] && _HB_Q=/data/local/tmp/t33a.heartbeat
_HB_Q_AGE=$(( $(date +%s) - $(stat -c %Y "$_HB_Q" 2>/dev/null || echo 0) ))
if [ "$_HB_Q_AGE" -lt 30 ]; then
    echo "$(date): relay already alive (hb age ${_HB_Q_AGE}s) — skipping startup" >> "$LOG"
else
    # TCP 루프백 ADB로 relay 시작 (PRIMARY — 외부 앱 의존 0, 폰 내장 adbd)
    echo "$(date): starting relay via ADB loopback (self-contained)..." >> "$LOG"
    for i in $(seq 1 6); do
        enable_wireless_adb   # 재부팅 시 OS가 끈 무선 디버깅 재활성화 (WiFi 미연결 대비 매회 시도)
        if connect_adb; then
            break
        fi
        echo "$(date): ADB attempt $i/6 failed, retry in 10s" >> "$LOG"
        sleep 10
    done

    if [ -n "$ADB_TARGET" ]; then
        start_relay
    else
        echo "$(date): ADB unavailable — notifying user" >> "$LOG"
        notify_adb_needed
    fi
fi
unset _HB_Q _HB_Q_AGE

# ── Termux 상주 watchdog ────────────────────────────────────────
# relay는 PPID=1이므로 거의 죽지 않음.
# 15초마다 heartbeat 확인 → 죽으면 ADB로 재시작.
# sleep 1×15틱이 아니라 sleep 15 — 감지 주기는 동일하고 CPU 웨이크업만 1/15.
# FAILS 백오프: ADB 장기 불가(무선 디버깅 OFF 등)에서 15s 재시도 폭풍 방지
#   (2026-07-23 실측: relay 죽은 채 15시간 × 18초 간격 재시도+알림).
echo "$(date): watchdog loop started" >> "$LOG"
FAILS=0
while true; do
    # 무선 디버깅 꺼짐 감지 → 재활성화 (OS/Samsung이 임의로 끄는 경우 방어)
    enable_wireless_adb
    # relay 자체 heartbeat (10s 갱신) — 빠른 감지. 없으면 기존 t33a.heartbeat 폴백
    HB_FILE=/data/local/tmp/t33a.relay_hb
    [ ! -f "$HB_FILE" ] && HB_FILE=/data/local/tmp/t33a.heartbeat
    MTIME=$(stat -c %Y "$HB_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    AGE=$((NOW - MTIME))
    if [ "$AGE" -lt 20 ]; then
        FAILS=0
    else
        RPID=$(cat "$RELAY_PID" 2>/dev/null)
        echo "$(date): relay dead (heartbeat ${AGE}s, PID $RPID) — restarting" >> "$LOG"
        ADB_TARGET=""
        if connect_adb && start_relay; then
            FAILS=0
        else
            notify_adb_needed
            FAILS=$((FAILS + 1))
        fi
    fi

    # 연속 실패 5회+ = ADB 장기 불가 → 60s, 20회+ → 300s로 감속 (복구 시 FAILS=0 즉시 정상화)
    if [ "$FAILS" -ge 20 ]; then
        sleep 300
    elif [ "$FAILS" -ge 5 ]; then
        sleep 60
    else
        sleep 15
    fi
done
