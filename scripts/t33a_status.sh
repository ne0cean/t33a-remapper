#!/data/data/com.termux/files/usr/bin/bash
# T33A 상태 위젯 — 읽기 전용. 아무것도 죽이지 않고 아무것도 띄우지 않는다.
#
# 왜 별도 위젯인가: 기존 T33A 위젯(t33a_start.sh)은 "복구" 동작이라
# watchdog 을 kill·재기동한다. 살아있는지 *확인만* 하려고 그걸 누르면
# 멀쩡한 데몬을 건드리게 된다. 확인과 조치를 분리한다.
#
# Termux 유저(uid 10xxx)로 돌아간다 — /data/local/tmp 는 쓰기 불가지만
# 개별 파일 stat/read 는 통과한다(t33a_start.sh 가 이미 같은 방식으로 읽음).

STATUS_FILE=/data/local/tmp/t33a.status
HB_FILE=/data/local/tmp/t33a.heartbeat      # worker, 60s 주기
RELAY_HB=/data/local/tmp/t33a.relay_hb      # relay, 1s 주기
RELAY_PID_FILE=/sdcard/Download/t33a_relay.pid
BOOT_LOG=/sdcard/Download/t33a_boot.log

STALE_RELAY=90     # auto-tcpip.sh 와 같은 기준
STALE_WORKER=150

age() {  # $1=path → 초, 없으면 99999
    local m; m=$(stat -c %Y "$1" 2>/dev/null) || m=0
    [ -z "$m" ] && m=0
    [ "$m" = "0" ] && { echo 99999; return; }
    echo $(( $(date +%s) - m ))
}

fmt_age() { [ "$1" -ge 99999 ] && echo "없음" || echo "${1}s"; }

STATUS=$(cat "$STATUS_FILE" 2>/dev/null | tr -d '\r\n')
[ -z "$STATUS" ] && STATUS="?"
RELAY_AGE=$(age "$RELAY_HB")
WORKER_AGE=$(age "$HB_FILE")

# relay PID 는 참고용으로만 출력한다. Termux uid 는 shell uid 프로세스의
# /proc/<pid> 를 볼 수 없어(hidepid) 살아있어도 항상 "없음"으로 보인다
# — 2026-09-25 라이브 실측. 판정에 쓰면 정상인데 "이상"이라 오보한다.
RPID=$(cat "$RELAY_PID_FILE" 2>/dev/null | tr -d '\r\n')
case "$RPID" in ''|*[!0-9]*) RPID="-" ;; esac

# watchdog(boot.sh) 는 Termux 유저 소유라 pgrep 으로 직접 보인다
WD=$(pgrep -f t33a_boot.sh 2>/dev/null | head -1)
[ -z "$WD" ] && WD="없음(!)"

PORT=$(getprop service.adb.tcp.port 2>/dev/null)
[ -z "$PORT" ] || [ "$PORT" = "0" ] && PORT="꺼짐"

# ── 판정: heartbeat 두 개 + status. Mac 쪽 assess() 와 같은 임계값이되
#    프로세스 개수 항목은 Termux uid 가 볼 수 없어 제외한다.
if [ "$RELAY_AGE" -ge "$STALE_RELAY" ]; then
    VERDICT="죽음"; WHY="relay heartbeat 멈춤"
elif [ "$WORKER_AGE" -ge "$STALE_WORKER" ]; then
    VERDICT="죽음"; WHY="remap worker heartbeat 멈춤"
elif [ "$STATUS" = "restarting" ]; then
    VERDICT="이상"; WHY="restarting 고착(크래시 루프 의심)"
else
    VERDICT="살아있음"; WHY=""
fi

case "$VERDICT" in
    살아있음) MARK="[OK]" ;;
    이상)     MARK="[??]" ;;
    *)        MARK="[XX]" ;;
esac

echo "───── T33A 데몬 상태 ─────"
echo " 판정      : $MARK $VERDICT${WHY:+  ($WHY)}"
echo " status    : $STATUS"
echo " relay hb  : $(fmt_age "$RELAY_AGE")  (90s 넘으면 죽음)"
echo " worker hb : $(fmt_age "$WORKER_AGE")  (150s 넘으면 죽음)"
echo " relay PID : ${RPID}  (참고용)"
echo " watchdog  : PID $WD"
echo " adb tcp   : ${PORT}"
echo " 시각      : $(date '+%m-%d %H:%M:%S')"
echo
if [ "$VERDICT" = "살아있음" ]; then
    echo " → 조치 필요 없음. 리모컨 그대로 쓰면 된다."
else
    echo " → 옆의 T33A 위젯(복구)을 1회 탭. 그래도 안 되면"
    echo "   개발자 옵션 → 무선 디버깅 OFF→ON 후 다시 탭."
fi
echo
echo "── boot.log 최근 5줄 ──"
tail -5 "$BOOT_LOG" 2>/dev/null || echo "(로그 없음)"

command -v termux-toast >/dev/null 2>&1 && \
    termux-toast "T33A $VERDICT / status=$STATUS / relay $(fmt_age "$RELAY_AGE")" 2>/dev/null
