#!/bin/bash
# T33A 자동 복구 데몬 v4 (Mac launchd: com.ateam.t33a-tcpip)
#
# 역사:
#  v1 수동형 — `adb devices`에 폰이 저절로 뜨기를 기다림(mDNS 자동연결 이벤트 의존).
#     2026-09-11 10:58~11:49 같은 LAN 에 있었는데도 미연결, 17:49 Wi-Fi 재접속
#     announce 를 잡고서야 복구 = 15시간 방치.
#  v2 능동형 — 15s 마다 직접 붙으러 감. 단 파괴적 조치(pkill)를 백오프·재확인 없이 도입.
#  v3 — 1차 리뷰(review-pr) CRITICAL 1·HIGH 2·MEDIUM 2 반영: 백오프, 2차 확인, relay 위임.
#  v4 (이 파일) — 2차 렌즈 적대 리뷰 반영:
#     ① relay 생존 판정을 /proc/<pid>/cmdline 으로 검증 (PID 재사용·stale pidfile 오탐 →
#        "relay 살아있음" 오판 → remap kill 만 반복하며 영구 무복구 되는 경로 차단)
#     ② 헬스 판정 3중화: relay_hb + remap 프로세스 2개(supervisor+worker) + worker
#        heartbeat 신선도. supervisor 는 설계상 영구 생존이라 개수>0 만 보면 worker
#        크래시루프를 영원히 "정상"으로 본다. status=restarting 고착도 이상으로 본다.
#     ③ FAILS 를 디스크에 영속화 — launchd KeepAlive 재기동마다 백오프가 0 으로
#        리셋되어 감속이 무력화되는 경로 차단.
#     ④ 단일 인스턴스 락 — 수동 실행 + launchd 동시 구동 시 서로의 백오프를 우회.
#     ⑤ 플래핑 대응: FAILS 를 0 으로 리셋하지 않고 감쇠. 알림 스로틀도 FAILS 기준.
#     ⑥ 로그 로테이션을 inode 보존(in-place truncate)으로 — launchd 가 잡은 fd 고아화 방지.
#     ⑦ 폰에서 온 status 문자열을 osascript 에 넣기 전 sanitize.
#     ⑧ IP 정규식의 리터럴 dot 이스케이프 + IP 가 바뀌어도 시리얼로 찾아가는 폴백.

#  v5 — 레버 능동 유지: 붙어 있는 동안 무선 디버깅 플래그와 classic 5555 를
#     *고장나기 전에* 켜 둔다. v4 까지는 둘 다 "이상 확정" 분기 안에서만 켰다 —
#     즉 폰이 건강하지만 5555 가 꺼진 상태(재부팅 후 TLS 로만 붙은 경우)를 방치했고,
#     그 상태에서 맥이 자리를 뜨면 폰의 위젯·boot.sh loopback 이 못 붙어 자력복구 불가.
#     tcpip 는 adbd 를 재시작시켜 relay 를 죽이므로(2026-06 실측) 포트가 이미 5555 면
#     건드리지 않고, 켤 때는 쿨다운 1회 + relay 재기동·검증을 동반한다.

LOG=/tmp/t33a-tcpip.log
STATEDIR=/tmp
FAILS_FILE="$STATEDIR/t33a-tcpip.fails"
LOCK_PIDF="$STATEDIR/t33a-tcpip.pid"
LEVER_TS_FILE="$STATEDIR/t33a-tcpip.lever_ts"
ADB=/opt/homebrew/bin/adb
PHONE_IP="${T33A_IP:-192.168.0.18}"
PHONE_SERIAL="${T33A_SERIAL:-R3CXA0DKVVV}"
HB_REMOTE=/data/local/tmp/t33a.relay_hb
RELAY_SH=/sdcard/Download/t33a_relay.sh
STALE=90             # relay_hb 이 나이를 넘으면 relay 사망(초)
WORKER_STALE=150     # worker heartbeat 주기 60s → 2.5배 여유(초)
CONFIRM_WAIT=15      # 파괴적 조치 전 2차 확인 간격(초)
AWAY_BACKOFF=60      # 폰이 LAN 에 없을 때 대기(초)
LEVER_COOLDOWN=600   # tcpip 레버 재시도 최소 간격(초) — 실패해도 매 틱 relay 를 죽이지 않도록
LOG_MAX=2000000      # 로그 상한(바이트)

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

# launchd 의 StandardOutPath 와 같은 파일이므로 inode 를 바꾸면 안 된다(fd 고아화).
rotate_log() {
    [ -f "$LOG" ] || return 0
    local sz; sz=$(stat -f %z "$LOG" 2>/dev/null || echo 0)
    [ "$sz" -gt "$LOG_MAX" ] || return 0
    tail -500 "$LOG" > "$LOG.tmp" 2>/dev/null && cat "$LOG.tmp" > "$LOG" && rm -f "$LOG.tmp"
    log "(로그 로테이션 — 이전 내용 잘림)"
}

notify() {  # $1=title $2=message
    local msg; msg=$(printf '%s' "$2" | tr -cd 'A-Za-z0-9 ().,:=?가-힣✅⚠️-')
    osascript -e "display notification \"$msg\" with title \"$1\" sound name \"${3:-Glass}\"" 2>/dev/null || true
}

# ── 단일 인스턴스 락 (수동 실행 + launchd 동시 구동 차단) ──
if [ -f "$LOCK_PIDF" ]; then
    OLD=$(cat "$LOCK_PIDF" 2>/dev/null)
    case "$OLD" in ''|*[!0-9]*) OLD=0 ;; esac
    if [ "$OLD" -gt 0 ] && ps -p "$OLD" -o command= 2>/dev/null | grep -q t33a-auto-tcpip; then
        log "이미 인스턴스 PID $OLD 가동 중 — 중복 실행 중단 (PID $$)"
        exit 0
    fi
fi
echo $$ > "$LOCK_PIDF"
trap 'rm -f "$LOCK_PIDF"' EXIT INT TERM

# ── FAILS 영속화 (launchd 재기동으로 백오프가 리셋되는 것 차단) ──
FAILS=$(cat "$FAILS_FILE" 2>/dev/null)
case "$FAILS" in ''|*[!0-9]*) FAILS=0 ;; esac
set_fails() { FAILS="$1"; echo "$FAILS" > "$FAILS_FILE"; }

# 연결된 폰 주소를 표준출력으로. 없으면 빈 문자열. 필요하면 직접 붙으러 간다.
ensure_device() {
    local d tls cand ipre
    ipre=$(printf '%s' "$PHONE_IP" | sed 's/\./\\./g')   # 리터럴 dot 이스케이프

    d=$("$ADB" devices 2>/dev/null | awk -v ip="$ipre" '$2=="device" && $1 ~ "^"ip":" {print $1}' | head -1)
    [ -n "$d" ] && { echo "$d"; return 0; }

    if "$ADB" connect "$PHONE_IP:5555" 2>&1 | grep -qiE "^connected|already connected"; then
        echo "$PHONE_IP:5555"; return 0
    fi

    # 무선디버깅 TLS 포트 능동 조회 — 먼저 알려진 IP, 실패 시 시리얼로 신원 확인(DHCP 대비)
    tls=$("$ADB" mdns services 2>/dev/null | awk -v ip="$ipre" '/_adb-tls-connect/ && $3 ~ "^"ip":" {print $3}' | head -1)
    if [ -n "$tls" ] && "$ADB" connect "$tls" 2>&1 | grep -qiE "^connected|already connected"; then
        echo "$tls"; return 0
    fi
    for cand in $("$ADB" mdns services 2>/dev/null | awk '/_adb-tls-connect/ {print $3}'); do
        "$ADB" connect "$cand" 2>&1 | grep -qiE "^connected|already connected" || continue
        if [ "$("$ADB" -s "$cand" shell getprop ro.serialno 2>/dev/null | tr -d '\r\n ')" = "$PHONE_SERIAL" ]; then
            log "IP 변경 감지 — 시리얼로 재발견: $cand (기존 $PHONE_IP)"
            PHONE_IP="${cand%%:*}"
            echo "$cand"; return 0
        fi
        "$ADB" disconnect "$cand" >/dev/null 2>&1
    done
    echo ""
}

# 폰 상태 1회 왕복 수집 → "AGE=<n> WHB=<n> REMAP=<개수> RELAY=<0|1> PORT=<n> ST=<status> OK=1"
# RELAY 는 pid 존재만이 아니라 cmdline 까지 대조한다(PID 재사용 오탐 차단).
probe() {
    "$ADB" -s "$1" shell 'NOW=$(date +%s); HB=$(stat -c %Y /data/local/tmp/t33a.relay_hb 2>/dev/null || echo 0); WH=$(stat -c %Y /data/local/tmp/t33a.heartbeat 2>/dev/null || echo 0); RP=$(cat /data/local/tmp/t33a_relay.pid 2>/dev/null); [ -z "$RP" ] && RP=0; case "$RP" in *[!0-9]*) RP=0 ;; esac; RELAY=0; if [ "$RP" -gt 0 ] && [ -d /proc/$RP ]; then tr "\0" " " < /proc/$RP/cmdline 2>/dev/null | grep -q t33a_relay && RELAY=1; fi; echo "AGE=$((NOW-HB)) WHB=$((NOW-WH)) REMAP=$(pidof t33a_remap | wc -w) RELAY=$RELAY PORT=$(getprop service.adb.tcp.port) WIFI=$(settings get global adb_wifi_enabled 2>/dev/null | tr -cd "0-9") ST=$(cat /data/local/tmp/t33a.status 2>/dev/null | tr -cd "A-Za-z:_") OK=1"' 2>/dev/null | tr -d '\r'
}

# 붙어 있는 동안 두 레버를 켜 둔다. 건강할 때 호출한다 — 고장난 뒤가 아니라.
# ① adb_wifi_enabled: 부작용 없음(adbd 재시작 안 함) → 꺼져 있으면 즉시 켠다.
# ② service.adb.tcp.port=5555: 켜는 행위가 adbd 를 재시작시켜 relay 를 죽인다.
#    그래서 이미 5555 면 절대 건드리지 않고, 켤 때는 relay 재기동까지 책임진다.
keep_levers() {
    local dev="$1" p="$2" wifi port now last nd i pp
    wifi=$(field "$p" WIFI); port=$(field "$p" PORT)

    if [ "$wifi" != "1" ]; then
        "$ADB" -s "$dev" shell "settings put global adb_wifi_enabled 1" >/dev/null 2>&1
        log "[$dev] 무선 디버깅 꺼져 있었음(=${wifi:-빈값}) → 켬"
    fi

    [ "$port" = "5555" ] && return 0

    now=$(date +%s)
    last=$(cat "$LEVER_TS_FILE" 2>/dev/null)
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    [ $((now - last)) -lt "$LEVER_COOLDOWN" ] && return 0
    echo "$now" > "$LEVER_TS_FILE"

    log "[$dev] 정상이지만 tcp port=${port:-빈값} → 자력복구용 5555 활성화"
    "$ADB" -s "$dev" tcpip 5555 >/dev/null 2>&1
    sleep 5
    "$ADB" connect "$PHONE_IP:5555" >/dev/null 2>&1
    nd=$(ensure_device); [ -n "$nd" ] && dev="$nd"

    # adbd 재시작이 relay 를 죽였는지 *확인하고* 대응한다. 무조건 재기동하면
    # "tcpip 는 항상 relay 를 죽인다"는 전제가 어긋나는 날 멀쩡한 relay 를
    # 매번 한 번 더 죽였다 살리게 된다. 아래 복구 분기와 같은 형태로 맞춘다.
    pp=$(probe "$dev")
    if assess "$pp"; then
        log "[$dev] ✅ 5555 활성, relay 무사 ($pp)"
        return 0
    fi
    if [ "$(field "$pp" RELAY)" = "1" ]; then
        log "[$dev] 5555 활성 후 relay 생존(cmdline 확인) — remap 만 kill, 온디바이스 워치독에 위임"
        "$ADB" -s "$dev" shell "pkill -x t33a_remap" >/dev/null 2>&1
    else
        log "[$dev] 5555 활성으로 relay 사망 — 직접 재기동"
        "$ADB" -s "$dev" shell "pkill -x t33a_remap 2>/dev/null; rm -f $HB_REMOTE; setsid /system/bin/sh $RELAY_SH < /dev/null > /dev/null 2>&1 &" >/dev/null 2>&1
    fi

    for i in $(seq 1 20); do
        sleep 3
        pp=$(probe "$dev")
        if assess "$pp"; then log "[$dev] ✅ 5555 활성 + relay 복구 ($pp)"; return 0; fi
    done
    log "[$dev] ⚠️ 5555 는 켰으나 relay 미복구 — 다음 사이클 복구 분기에 위임"
}

field() { echo "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1; }

# 0=건강, 1=죽음/이상, 2=판정불가(통신 실패)
assess() {
    local p="$1" age whb remap st
    echo "$p" | grep -q "OK=1" || return 2
    age=$(field "$p" AGE); whb=$(field "$p" WHB); remap=$(field "$p" REMAP); st=$(field "$p" ST)
    case "$age$whb$remap" in ''|*[!0-9]*) return 2 ;; esac
    [ "$age" -lt "$STALE" ] || return 1              # relay 살아있나
    [ "$remap" -ge 2 ] || return 1                   # supervisor+worker 둘 다
    [ "$whb" -lt "$WORKER_STALE" ] || return 1       # worker 가 실제로 돌고 있나
    [ "$st" = "restarting" ] && return 1             # 재시작 고착 = 크래시루프 의심
    return 0
}

log "=== t33a-auto-tcpip v5 started (PID $$, 이월 FAILS=$FAILS) ==="
STATE=unknown   # alive | dead | away

while true; do
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
        [ "$STATE" != "alive" ] && log "[$DEV] 정상 ($P)"
        STATE=alive
        [ "$FAILS" -gt 0 ] && set_fails $((FAILS-1))   # 리셋이 아니라 감쇠(플래핑 대비)
        keep_levers "$DEV" "$P"
        continue
    fi

    # ── 2차 확인: adb 단발 실패/순단으로 멀쩡한 remap 을 죽이지 않는다 ──
    sleep "$CONFIRM_WAIT"
    P=$(probe "$DEV"); assess "$P"; VERDICT2=$?
    if [ "$VERDICT2" = "0" ]; then
        log "[$DEV] 1차 이상 → 2차 정상, 일시적 오류로 판단 (FAILS 유지 $FAILS)"
        STATE=alive
        continue
    fi
    if [ "$VERDICT2" = "2" ]; then
        set_fails $((FAILS+1))
        log "[$DEV] 폰 응답 없음(판정불가) — 파괴적 조치 보류 (연속 $FAILS)"
        continue
    fi

    # ── 복구 (2회 연속 이상 확인됨) ──
    set_fails $((FAILS+1))
    log "[$DEV] 이상 확정 ($P, 연속 $FAILS) — 복구 시작"

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
        log "[$DEV] 폰 relay 생존(cmdline 확인) — remap 만 kill 하고 온디바이스 워치독에 위임"
        "$ADB" -s "$DEV" shell "pkill -x t33a_remap" >/dev/null 2>&1
    else
        log "[$DEV] 폰 relay 사망 — relay 직접 재기동"
        "$ADB" -s "$DEV" shell "pkill -x t33a_remap 2>/dev/null; rm -f $HB_REMOTE; setsid /system/bin/sh $RELAY_SH < /dev/null > /dev/null 2>&1 &" >/dev/null 2>&1
    fi

    RECOVERED=0
    for i in $(seq 1 20); do
        sleep 3
        P=$(probe "$DEV")
        if assess "$P"; then RECOVERED=1; break; fi
    done

    if [ "$RECOVERED" = "1" ]; then
        STATUS=$(field "$P" ST)
        log "[$DEV] ✅ 복구 확인 ($P)"
        [ "$STATE" != "alive" ] && notify "T33A 복구됨" "리매핑 동작 중 (status=${STATUS:-?})" "Glass"
        STATE=alive
        set_fails $((FAILS/2))     # 리셋이 아니라 절반 — 반복 복구는 이상 신호다
    else
        log "[$DEV] ⚠️ 복구 실패 (연속 $FAILS) — 폰 T33A 위젯 1회 탭 필요"
        if [ "$FAILS" = "1" ] || [ $((FAILS % 5)) = 0 ]; then
            notify "T33A 복구 실패" "relay 미복구(연속 $FAILS). 폰 위젯 1회 탭 필요." "Basso"
        fi
        STATE=dead
    fi
done
