#!/bin/bash
# T33A 자동 복구 데몬 v2 (Mac launchd: com.ateam.t33a-tcpip)
#
# v1(수동형)의 결함 — 2026-09-11 실측:
#   v1은 `adb devices`에 폰이 "저절로 뜨기"를 기다렸다. 그 자동 등장은 adb 서버의
#   mDNS 자동연결에 의존하는데 이벤트성이라 놓치면 영원히 안 온다. 실제로 09-11
#   10:58~11:49 폰이 같은 Wi-Fi에 있고 폰 워치독도 돌았으나 맥은 한 번도 붙지 않았고,
#   17:49 Wi-Fi 재접속 순간에야 붙어 15시간 방치됐다.
# v2(능동형): 15초마다 직접 붙으러 간다.
#   ① adb connect IP:5555 (adbd가 이미 TCP면 즉시)
#   ② 실패 시 `adb mdns services`로 무선디버깅 TLS 포트를 능동 조회해 connect
#   ③ 붙으면 service.adb.tcp.port!=5555일 때 adb tcpip 5555
#   ④ 그래도 relay_hb가 stale이면 relay를 직접 재기동(폰 워치독 backoff 대기 없이)
#   → 폰이 같은 LAN에 있고 맥이 깨어 있으면 늦어도 ~1분 내 복구.

LOG=/tmp/t33a-tcpip.log
ADB=/opt/homebrew/bin/adb
PHONE_IP="${T33A_IP:-192.168.0.18}"
HB_REMOTE=/data/local/tmp/t33a.relay_hb
HB_FALLBACK=/data/local/tmp/t33a.heartbeat
INTERVAL=15          # 정상일 때 점검 주기(초)
STALE=90             # relay_hb 이 나이를 넘으면 죽은 것으로 간주(초)
AWAY_BACKOFF=60      # 폰이 LAN에 없을 때 추가 대기(초)

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

notify() {  # $1=title $2=message $3=sound
    local sound="${3:-Glass}"
    osascript -e "display notification \"$2\" with title \"$1\" sound name \"$sound\"" 2>/dev/null || true
}

# 연결된 폰 주소를 표준출력으로. 없으면 빈 문자열.
# 부작용: 필요하면 직접 adb connect 를 시도한다(능동형의 핵심).
ensure_device() {
    local d
    # 0. 이미 device 상태로 붙어 있나 (5555 우선)
    d=$("$ADB" devices 2>/dev/null | awk -v ip="$PHONE_IP" '$2=="device" && index($1,ip)==1 {print $1}' | sort -t: -k2 -n | head -1)
    [ -n "$d" ] && { echo "$d"; return 0; }

    # 1. classic 5555 직접 시도
    if "$ADB" connect "$PHONE_IP:5555" 2>&1 | grep -qiE "^connected|already connected"; then
        echo "$PHONE_IP:5555"; return 0
    fi

    # 2. 무선디버깅 TLS 포트를 능동 조회 (수동 대기 금지 — v1의 결함)
    local tls
    tls=$("$ADB" mdns services 2>/dev/null | awk -v ip="$PHONE_IP" '/_adb-tls-connect/ && index($3,ip)==1 {print $3}' | head -1)
    if [ -n "$tls" ] && "$ADB" connect "$tls" 2>&1 | grep -qiE "^connected|already connected"; then
        echo "$tls"; return 0
    fi
    echo ""
}

hb_age() {  # $1=device
    # 주의: t33a.heartbeat 폴백 금지. relay 가 죽어도 워치독 재시도가 그 파일을 계속
    # 건드려 "살아있음"으로 오판한다(2026-09-11 장애주입 실측). relay_hb 만 본다.
    local mtime now
    mtime=$("$ADB" -s "$1" shell "stat -c %Y $HB_REMOTE 2>/dev/null || echo 0" 2>/dev/null | tr -d '\r\n ')
    now=$("$ADB" -s "$1" shell "date +%s" 2>/dev/null | tr -d '\r\n ')
    [ -z "$mtime" ] && mtime=0
    [ -z "$now" ] && { echo 999999; return; }
    echo $(( now - mtime ))
}

log "=== t33a-auto-tcpip v2 (능동형) started (PID $$) ==="
STATE=unknown   # alive | dead | away

while true; do
    sleep "$INTERVAL"

    DEV=$(ensure_device)
    if [ -z "$DEV" ]; then
        [ "$STATE" != "away" ] && log "폰 접속 불가 — 같은 LAN에 없거나 무선디버깅 OFF (대기)"
        STATE=away
        sleep "$AWAY_BACKOFF"
        continue
    fi

    AGE=$(hb_age "$DEV")
    ALIVE=$("$ADB" -s "$DEV" shell "pidof t33a_remap 2>/dev/null" 2>/dev/null | tr -d '\r\n ')
    if [ "$AGE" -lt "$STALE" ] && [ -n "$ALIVE" ]; then
        [ "$STATE" != "alive" ] && log "[$DEV] 정상 (relay_hb ${AGE}s, remap PID $ALIVE)"
        STATE=alive
        continue
    fi

    # ── 여기부터 복구 ──
    log "[$DEV] relay 사망 감지 (relay_hb ${AGE}s, remap PID='${ALIVE:-none}') — 복구 시작"

    PORT=$("$ADB" -s "$DEV" shell getprop service.adb.tcp.port 2>/dev/null | tr -d '\r\n ')
    if [ "$PORT" != "5555" ]; then
        log "[$DEV] tcp port=$PORT → adb tcpip 5555"
        log "[$DEV] 결과: $("$ADB" -s "$DEV" tcpip 5555 2>&1)"
        sleep 5
        "$ADB" connect "$PHONE_IP:5555" >/dev/null 2>&1
        NEW=$(ensure_device); [ -n "$NEW" ] && DEV="$NEW"
    fi

    # 폰 워치독(backoff 최대 120s)을 기다리지 않고 직접 기동 — revive.sh 와 동일 경로
    log "[$DEV] relay 직접 재기동"
    "$ADB" -s "$DEV" shell "pkill -x t33a_remap 2>/dev/null; rm -f $HB_REMOTE; setsid /system/bin/sh /sdcard/Download/t33a_relay.sh < /dev/null > /dev/null 2>&1 &" >/dev/null 2>&1

    RECOVERED=0
    for i in $(seq 1 20); do
        sleep 3
        AGE=$(hb_age "$DEV")
        ALIVE=$("$ADB" -s "$DEV" shell "pidof t33a_remap 2>/dev/null" 2>/dev/null | tr -d '\r\n ')
        [ "$AGE" -lt 20 ] && [ -n "$ALIVE" ] && { RECOVERED=1; break; }
    done

    if [ "$RECOVERED" = "1" ]; then
        STATUS=$("$ADB" -s "$DEV" shell "cat /data/local/tmp/t33a.status 2>/dev/null" | tr -d '\r\n ')
        log "[$DEV] ✅ 복구 확인 (relay_hb ${AGE}s, status=$STATUS)"
        [ "$STATE" != "alive" ] && notify "✅ T33A 복구됨" "리매핑 동작 중 (status=${STATUS:-?})" "Glass"
        STATE=alive
    else
        log "[$DEV] ⚠️ 복구 실패 (relay_hb ${AGE}s) — 폰 T33A 위젯 1회 탭 필요"
        [ "$STATE" != "dead" ] && notify "⚠️ T33A 복구 실패" "relay 미복구. 폰 T33A 위젯 1회 탭 필요." "Basso"
        STATE=dead
    fi
done
