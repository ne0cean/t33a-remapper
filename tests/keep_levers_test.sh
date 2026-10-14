#!/bin/bash
# 사용: bash tests/keep_levers_test.sh [스크립트]. 실제 adb 는 부르지 않는다. 변이 대조(2026-10-14): 이전 main 은 첫 케이스 FAIL.
# keep_levers 단독 시험: 가짜 adb·probe·ensure_device 로 "무선 디버깅 켜기" 호출 여부만 센다
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a-auto-tcpip.sh}"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fn=$(sed -n '/^keep_levers() {/,/^}/p' "$SRC"); fld=$(grep '^field() ' "$SRC")
fails=0
case_() { # name port wifi want
  : > "$T/calls"
  out=$(bash -c "
    ADB='$T/fakeadb'; LEVER_TS_FILE='$T/lever_ts'; LEVER_COOLDOWN=999999; PHONE_IP=x; HB_REMOTE=x; RELAY_SH=x
    log(){ :; }; sleep(){ :; }; ensure_device(){ echo dev; }; probe(){ echo 'OK=1'; }; assess(){ return 0; }
    $fld
    $fn
    echo \$(date +%s) > '$T/lever_ts'
    keep_levers dev 'PORT=$2 WIFI=$3 OK=1'
  ")
  got=$(grep -c 'adb_wifi_enabled 1' "$T/calls")
  [ "$got" = "$4" ] && echo "PASS $1" || { echo "FAIL $1 (want $4 got $got)"; fails=$((fails+1)); }
}
printf '#!/bin/bash\necho "$*" >> "%s/calls"\n' "$T" > "$T/fakeadb"; chmod +x "$T/fakeadb"
case_ "5555 열림+무선디버깅 꺼짐 → 켜지 않음" 5555 0 0
case_ "5555 열림+무선디버깅 켜짐 → 아무것도 안 함" 5555 1 0
case_ "5555 닫힘+무선디버깅 꺼짐 → 켬" "" 0 1
case_ "5555 닫힘+무선디버깅 켜짐 → 다시 켜지 않음" "" 1 0
echo "fails=$fails"; exit $fails
