#!/bin/bash
# boot_watchdog_wadb_test.sh — 폰 t33a_boot.sh watchdog 의 무선 디버깅 재활성화 줄 시험(2026-10-14).
# 5555 가 열려 있으면 enable_wireless_adb 를 부르지 않고, 닫혀 있으면 부른다. 사용: bash tests/boot_watchdog_wadb_test.sh [스크립트]
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a_boot.sh}"
line=$(sed -n '/^while true; do/,/^done/p' "$SRC" | grep -m1 'enable_wireless_adb')
[ -n "$line" ] || { echo "ABORT: watchdog 의 enable_wireless_adb 줄 없음 ($SRC)"; exit 2; }
fails=0
case_() { # name port want
  got=$(bash -c "getprop(){ echo '$2'; }; n=0; enable_wireless_adb(){ n=\$((n+1)); }; $line; echo \$n")
  [ "$got" = "$3" ] && echo "PASS $1" || { echo "FAIL $1 (want $3 got $got)"; fails=$((fails+1)); }
}
case_ "5555 열림 → 무선 디버깅 켜지 않음" 5555 0
case_ "포트 없음(재부팅 뒤) → 켬" "" 1
case_ "다른 포트 → 켬" 0 1
echo "fails=$fails"; exit $fails
