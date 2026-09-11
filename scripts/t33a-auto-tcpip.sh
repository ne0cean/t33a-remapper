#!/bin/bash
# T33A 자동 복구 데몬 v3 (Mac launchd: com.ateam.t33a-tcpip)
#
# 역사:
#  v1 수동형 — `adb devices`에 폰이 저절로 뜨기를 기다림. 그 자동 등장은 adb mDNS
#     자동연결 이벤트 의존이라 놓치면 안 온다. 2026-09-11 10:58~11:49 폰이 같은 LAN에
#     있었는데도 미연결, 17:49 Wi-Fi 재접속 announce를 잡고서야 복구(15h 방치).
#  v2 능동형 — 15s마다 직접 붙으러 감. 단 파괴적 조치(pkill)를 백오프·재확인 없이
#     도입해 리뷰에서 CRITICAL 1·HIGH 2 지적.
#  v3 (이 파일) — v2의 능동성 유지 + 리뷰 지적 전량 반영:
#     ① FAILS 백오프(15s→60s→300s) — t33a_boot.sh 가 2026-07-23 에 이미 배운 교훈
#     ② 파괴적 조치 전 2차 확인 — adb 단발 실패로 멀쩡한 remap 을 죽이지 않음
#     ③ 폰 relay 가 살아있으면 relay 를 새로 스폰하지 않고 remap kill 만(레이스 감소)
#     ④ IP 매칭 콜론 앵커(.18 이 .180 을 잡던 프리픽스 충돌 제거)
#     ⑤ 상태 프로브 1회 왕복으로 통합, 비숫자 방어, 로그 로테이션

LOG=/tmp/t33a-tcpip.log
ADB=/opt/homebrew/bin/adb
PHONE_IP="${T33A_IP:-192.168.0.18}"
HB_REMOTE=/data/local/tmp/t33a.relay_hb
RELAY_PIDF=/data/local/tmp/t33a_relay.pid
RELAY_SH=/sdcard/Download/t33a_relay.sh
STALE=90             # relay_hb 이 나이를 넘으면 죽은 것으로 간주(초)
CONFIRM_WAIT=15      # 파괴적 조치 전 2차 확인 간격(초)
AWAY_BACKOFF=60      # 폰이 LAN 에 없을 때 대기(초)
LOG_MAX=2000000      # 로그 상한(바이트) — 넘으면 최근 500줄만 남김

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

rotate_log() {
    [ -f "$LOG" ] || return 0
    local sz; sz=$(stat -f %z "$LOG" 2>/dev/null || echo 0)
    [ "$sz" -gt "$LOG_MAX" ] || return 0
    tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    log "(로그 로테이션 — 이전 내용 잘림)"
}

notify() {  # $1=title $2=message $3=sound
    osascript -e "display notification \"$2\" with title \"$1\" sound name \"${3:-Glass}\"" 2>/dev/null || true
}

# 연결된 폰 주소를 표준출력으로. 없으면 빈 문자열. 필요하면 직접 붙으러 간다.
ensure_device() {
    local d tls
    # 0. 이미 device 상태로 붙어 있나 (IP 는 콜론 경계까지 앵커 — .18 vs .180 충돌 방지)
    d=$("$ADB" devices 2>/dev/null | awk -v ip="$PHONE_IP" '$2=="device" && $1 ~ "^"ip":" {print $1}' | head -1)
    [ -n "$d" ] && { echo "$d"; return 0; }

    # 1. classic 5555 직접 시도
    if "$ADB" connect "$PHONE_IP:5555" 2>&1 | grep -qiE "^connected|already connected"; then
        echo "$PHONE_IP:5555"; return 0
    fi

    # 2. 무선디버깅 TLS 포트를 능동 조회 (수동 대기 금지 — v1 의 결함)
    tls=$("$ADB" mdns services 2>/dev/null | awk -v ip="$PHONE_IP" '/_adb-tls-connect/ && $3 ~ "^"ip":" {print $3}' | head -1)
    if [ -n "$tls" ] && "$ADB" connect "$tls" 2>&1 | grep -qiE "^connected|already connected"; then
        echo "$tls"; return 0
    fi
    echo ""
}

# 폰 상태를 1회 왕복으로 수집 → "AGE=<n> REMAP=<개수> RELAY=<0|1> PORT=<n> OK=1"
# OK 가 없으면 통신 실패다(= 죽었다고 단정 금지 — v2 의 HIGH 지적).
probe() {
    "$ADB" -s "$1" shell 'HB=$(stat -c %Y /data/local/tmp/t33a.relay_hb 2>/dev/null || echo 0); NOW=$(date +%s); RP=$(cat /data/local/tmp/t33a_relay.pid 2>/dev/null); [ -z "$RP" ] && RP=0; case "$RP" in *[!0-9]*) RP=0 ;; esac; RELAY=0; [ "$RP" -gt 0 ] && [ -d /proc/$RP ] && RELAY=1; echo "AGE=$((NOW-HB)) REMAP=$(pidof t33a_remap | wc -w) RELAY=$RELAY PORT=$(getprop service.adb.tcp.port) OK=1"' 2>/dev/null | tr -d '\r'
}

field() { echo "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1; }

# 건강한가? 0=건강, 1=죽음, 2=판정불가(통신 실패)
assess() {
    local p="$1" age remap
    echo "$p" | grep -q "OK=1" || return 2
    age=$(field "$p" AGE); remap=$(field "$p" REMAP)
    case "$age" in ''|*[!0-9]*) return 2 ;; esac
    case "$remap" in ''|*[!0-9]*) return 2 ;; esac
    [ "$age" -lt "$STALE" ] && [ "$remap" -gt 0 ] && return 0
    return 1
}

log "=== t33a-auto-tcpip v3 (능동형+백오프) started (PID $$) ==="
STATE=unknown   # alive | dead | away
FAILS=0

while true; do
    # 백오프: 연속 실패가 쌓이면 감속 (t33a_boot.sh 와 동일한 교훈)
    if   [ "$FAILS" -ge 20 ]; then sleep 300
    elif [ "$FAILS" -ge 5  ]; then sleep 60
    else sleep 15
    fi
    rotate_log

    DEV=$(ensure_device)
    if [ -z "$DEV" ]; then
        [ "$STATE" != "away" ] && log "폰 접속 불가 — 같은 LAN 에 없거나 무선디버깅 OFF (대기)"
        STATE=away
        sleep "$AWAY_BACKOFF"
        continue
    fi

    P=$(probe "$DEV"); assess "$P"; VERDICT=$?
    if [ "$VERDICT" = "0" ]; then
        [ "$STATE" != "alive" ] && log "[$DEV] 정상 (relay_hb $(field "$P" AGE)s)"
        STATE=alive; FAILS=0
        continue
    fi

    # ── 2차 확인: adb 단발 실패/순단으로 멀쩡한 remap 을 죽이지 않는다 ──
    sleep "$CONFIRM_WAIT"
    P=$(probe "$DEV"); assess "$P"; VERDICT2=$?
    if [ "$VERDICT2" = "0" ]; then
        log "[$DEV] 1차 이상 → 2차 정상, 일시적 통신 실패로 판단하고 무시"
        STATE=alive; FAILS=0
        continue
    fi
    if [ "$VERDICT2" = "2" ]; then
        FAILS=$((FAILS+1))
        log "[$DEV] 폰 응답 없음(판정불가) — 파괴적 조치 보류 (연속 $FAILS)"
        continue
    fi

    # ── 여기부터 복구 (진짜 죽음으로 2회 연속 확인됨) ──
    FAILS=$((FAILS+1))
    log "[$DEV] relay 사망 확정 (relay_hb $(field "$P" AGE)s, remap 프로세스 $(field "$P" REMAP)개, 연속 $FAILS) — 복구 시작"

    PORT=$(field "$P" PORT)
    if [ "$PORT" != "5555" ]; then
        log "[$DEV] tcp port=$PORT → adb tcpip 5555"
        log "[$DEV] 결과: $("$ADB" -s "$DEV" tcpip 5555 2>&1)"
        sleep 5
        "$ADB" connect "$PHONE_IP:5555" >/dev/null 2>&1
        NEW=$(ensure_device); [ -n "$NEW" ] && DEV="$NEW"
        P=$(probe "$DEV")
    fi

    if [ "$(field "$P" RELAY)" = "1" ]; then
        # 폰 relay 가 살아있다 → 자체 워치독(5s)이 remap 을 되살린다. relay 중복 스폰 금지.
        log "[$DEV] 폰 relay 생존 — remap 만 kill 하고 온디바이스 워치독에 위임"
        "$ADB" -s "$DEV" shell "pkill -x t33a_remap" >/dev/null 2>&1
    else
        log "[$DEV] 폰 relay 도 사망 — relay 직접 재기동"
        "$ADB" -s "$DEV" shell "pkill -x t33a_remap 2>/dev/null; rm -f $HB_REMOTE; setsid /system/bin/sh $RELAY_SH < /dev/null > /dev/null 2>&1 &" >/dev/null 2>&1
    fi

    RECOVERED=0
    for i in $(seq 1 20); do
        sleep 3
        P=$(probe "$DEV")
        if assess "$P"; then RECOVERED=1; break; fi
    done

    if [ "$RECOVERED" = "1" ]; then
        STATUS=$("$ADB" -s "$DEV" shell "cat /data/local/tmp/t33a.status 2>/dev/null" | tr -d '\r\n ')
        log "[$DEV] ✅ 복구 확인 (relay_hb $(field "$P" AGE)s, status=$STATUS)"
        [ "$STATE" != "alive" ] && notify "✅ T33A 복구됨" "리매핑 동작 중 (status=${STATUS:-?})" "Glass"
        STATE=alive; FAILS=0
    else
        log "[$DEV] ⚠️ 복구 실패 (연속 $FAILS) — 폰 T33A 위젯 1회 탭 필요"
        # 첫 실패 + 이후 5회마다 재알림 (v2 는 최초 1회뿐이라 무음 방치됐다)
        if [ "$STATE" != "dead" ] || [ $((FAILS % 5)) = 0 ]; then
            notify "⚠️ T33A 복구 실패" "relay 미복구(연속 $FAILS). 폰 T33A 위젯 1회 탭 필요." "Basso"
        fi
        STATE=dead
    fi
done
