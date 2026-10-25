#!/bin/bash
# 사용: bash tests/relay_policy_test.sh [relay 스크립트]. 실제 폰 명령은 부르지 않는다.
# relay 의 wifi_debug_policy·wadb_keeper_revive 단독 시험: 가짜 cmd/settings/getprop/dumpsys/am 으로 호출만 센다.
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a_relay.sh}"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fns=$(sed -n '/^current_ssid() {/,/^}/p; /^wifi_debug_policy() {/,/^}/p; /^wadb_keeper_revive() {/,/^}/p' "$SRC")
ssids=$(grep '^WIFI_DEBUG_SSIDS=' "$SRC")
[ -n "$fns" ] && [ -n "$ssids" ] || { echo "ABORT: 함수 추출 실패 ($SRC)"; exit 2; }
fails=0
run() { # ssid cur port wadb_state
  : > "$T/calls"
  bash -c "
    $ssids; WADB_PKG=com.ateam.wadbkeeper; log(){ :; }
    cmd(){ [ -n '$1' ] && echo 'Wifi is connected to \"$1\"' || echo 'Wifi is disconnected'; echo 'WifiInfo: SSID: \"x\"'; }
    settings(){ [ \"\$1\" = get ] && { echo '$2'; return; }; echo \"settings \$*\" >> '$T/calls'; }
    getprop(){ echo '$3'; }
    dumpsys(){ echo '  User 150: installed=false enabled=0'; echo '  User 0: installed=true stopped=false enabled=$4 instant=false'; }
    am(){ echo \"am \$*\" >> '$T/calls'; }
    $fns
    wifi_debug_policy; wadb_keeper_revive
  "
}
case_() { # name ssid cur port wadb want(호출 요약)
  run "$2" "$3" "$4" "$5"
  got=$(sed -e 's/settings put global adb_wifi_enabled /wifi=/' -e 's/^am start.*/am/' "$T/calls" | tr '\n' ' ' | sed 's/ $//')
  if [ "$got" = "$6" ]; then echo "PASS $1"; else echo "FAIL $1 (want [$6] got [$got])"; fails=$((fails+1)); fi
}
case_ "집 Wi-Fi+꺼짐 → 켬"                 NOIR_5G 0 5555 0 "wifi=1"
case_ "회사 twnap+꺼짐 → 켬"               twnap   0 5555 0 "wifi=1"
case_ "회사 twnap+켜짐 → 아무것도 안 함"    twnap   1 5555 0 ""
case_ "지정 밖 Wi-Fi+켜짐+5555 → 끔"        cafe    1 5555 0 "wifi=0"
case_ "지정 밖 Wi-Fi+켜짐+5555 닫힘 → 유지(복구 경로)" cafe 1 "" 0 ""
case_ "지정 밖 Wi-Fi+꺼짐 → 아무것도 안 함" cafe    0 5555 0 ""
case_ "Wi-Fi 없음+켜짐 → 손대지 않음"       ""      1 5555 0 ""
case_ "부분 일치 금지(NOIR_5G_EXT) → 끔"    NOIR_5G_EXT 1 5555 0 "wifi=0"
case_ "WADB Keeper enabled=4 → 앱 화면 실행" NOIR_5G 1 5555 4 "am"
case_ "WADB Keeper enabled=0 → 실행 안 함"   NOIR_5G 1 5555 0 ""
case_ "WADB Keeper enabled=3(사용자 끔) → 존중" NOIR_5G 1 5555 3 ""
echo "fails=$fails"; exit $fails
