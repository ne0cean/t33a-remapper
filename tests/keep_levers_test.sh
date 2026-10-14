#!/bin/bash
# 사용: bash tests/keep_levers_test.sh [스크립트]. 실제 adb 는 부르지 않는다. 변이 대조(2026-10-14): 이전 main 은 첫 케이스 FAIL.
# keep_levers 단독 시험: 가짜 adb·probe·ensure_device 로 "무선 디버깅 켜기" 호출 여부만 센다
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a-auto-tcpip.sh}"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fn=$(sed -n '/^keep_levers() {/,/^}/p' "$SRC"); fld=$(grep '^field() ' "$SRC")
[ -n "$fn" ] && [ -n "$fld" ] || { echo "ABORT: keep_levers/field 추출 실패 ($SRC)"; exit 2; }
fails=0
case_() { # name port wifi want [dev] [want_tcpip] — want_tcpip 를 주면 쿨다운 없이 돌려 tcpip 호출 수도 단언
  : > "$T/calls"
  out=$(CD="${6:+0}" bash -c "
    ADB='$T/fakeadb'; LEVER_TS_FILE='$T/lever_ts'; LEVER_COOLDOWN=\${CD:-999999}; PHONE_IP=x; HB_REMOTE=x; RELAY_SH=x
    log(){ :; }; sleep(){ :; }; ensure_device(){ echo dev; }; probe(){ echo 'OK=1'; }; assess(){ return 0; }
    $fld
    $fn
    [ -n \"\$CD\" ] && rm -f '$T/lever_ts' || echo \$(date +%s) > '$T/lever_ts'
    keep_levers '${5:-100.107.190.45:5555}' 'PORT=$2 WIFI=$3 OK=1'
  ")
  got=$(grep -c 'adb_wifi_enabled 1' "$T/calls")
  tc=$(grep -c 'tcpip 5555' "$T/calls")
  if [ "$got" = "$4" ] && { [ -z "$6" ] || [ "$tc" = "$6" ]; }; then echo "PASS $1"
  else echo "FAIL $1 (want wifi=$4 tcpip=${6:--} got wifi=$got tcpip=$tc)"; fails=$((fails+1)); fi
}
printf '#!/bin/bash\necho "$*" >> "%s/calls"\n' "$T" > "$T/fakeadb"; chmod +x "$T/fakeadb"
case_ "5555 열림+무선디버깅 꺼짐 → 켜지 않음" 5555 0 0
case_ "5555 열림+무선디버깅 켜짐 → 아무것도 안 함" 5555 1 0
case_ "5555 닫힘+무선디버깅 꺼짐 → 켬" "" 0 1
case_ "5555 닫힘+무선디버깅 켜짐 → 다시 켜지 않음" "" 1 0
case_ "포트 0(adb usb 뒤)+꺼짐 → 켬" 0 0 1
case_ "포트 5556+꺼짐 → 켬" 5556 0 1
case_ "TLS 세션(주소 이동)인데 prop 5555+꺼짐 → 켬(mDNS 재발견 유지)" 5555 0 1 192.168.7.55:41413
# tcpip 는 adbd 를 재시작시켜 relay 를 죽인다 — 5555 가 이미 열려 있으면 어떤 세션이든 부르면 안 된다(적대 리뷰 LOW)
case_ "TLS 세션+prop 5555+켜짐, 쿨다운 없음 → tcpip 안 부름" 5555 1 0 192.168.7.55:41413 0
case_ "5555 세션+prop 5555, 쿨다운 없음 → tcpip 안 부름" 5555 1 0 100.107.190.45:5555 0
case_ "TLS 세션+5555 닫힘, 쿨다운 없음 → tcpip 부름(단언 자체 확인)" "" 1 0 192.168.7.55:41413 1
echo "fails=$fails"; exit $fails
