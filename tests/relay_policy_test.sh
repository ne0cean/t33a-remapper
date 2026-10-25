#!/bin/bash
# 사용: bash tests/relay_policy_test.sh [relay 스크립트]. 실제 폰 명령은 부르지 않는다.
# relay 의 무선 디버깅 정책·WADB Keeper 되살리기·주기 배선 시험: 가짜 cmd/settings/getprop/dumpsys/am 으로 호출만 센다.
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a_relay.sh}"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fns=$(sed -n '/^current_ssid() {/,/^}/p; /^wifi_debug_policy() {/,/^}/p; /^wadb_keeper_revive() {/,/^}/p; /^periodic_checks() {/,/^}/p' "$SRC")
cfg=$(grep -E '^(WIFI_DEBUG_SSIDS|WIFI_POLICY_INTERVAL|WADB_CHECK_INTERVAL|WADB_PKG|WIFI_ON_RETRIES|WIFI_ON_SSID)=' "$SRC")
init=$(grep -E '^(wifi_tick|wadb_tick)=' "$SRC")
[ "$(echo "$fns" | grep -c '() {$')" = 4 ] && [ -n "$cfg" ] && [ "$(echo "$init" | wc -l)" -eq 2 ] || { echo "ABORT: 추출 실패 ($SRC)"; exit 2; }
fails=0
# fake: $1 ssid  $2 cur(파일로 상태 유지)  $3 port  $4 enabled  $5 stopped
fakes() { cat <<F
log(){ :; }; timeout(){ shift; "\$@"; }
cmd(){ [ -n '$1' ] && echo 'Wifi is connected to "$1"' || echo 'Wifi is not connected'; echo 'WifiInfo: SSID: "x"'; }
settings(){ if [ "\$1" = get ]; then cat '$T/cur'; else echo "settings \$*" >> '$T/calls'; [ -n "\$KEEP" ] || echo "\$4" > '$T/cur'; fi; }
getprop(){ echo '$3'; }
dumpsys(){ echo '  User 150: installed=false stopped=true enabled=0'; echo '  User 0: installed=true stopped=${5:-false} enabled=$4 instant=false'; echo '  User 0: firstInstallTime'; }
am(){ echo "am \$*" >> '$T/calls'; }
F
}
summ() { sed -e 's/settings put global adb_wifi_enabled /wifi=/' -e 's/^am start.*/am/' "$T/calls" | tr '\n' ' ' | sed 's/ $//'; }
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want [$2] got [$3])"; fails=$((fails+1)); fi; }
case_() { # name ssid cur port enabled want [stopped]
  : > "$T/calls"; echo "$3" > "$T/cur"
  bash -c "$cfg; $(fakes "$2" "$3" "$4" "$5" "$7"); $fns; wifi_debug_policy; wadb_keeper_revive"
  check "$1" "$6" "$(summ)"
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
case_ "WADB Keeper 강제 정지 → 앱 화면 실행" NOIR_5G 1 5555 0 "am" true
case_ "WADB Keeper enabled=0 → 실행 안 함"   NOIR_5G 1 5555 0 ""
case_ "WADB Keeper enabled=3(사용자 끔) → 존중" NOIR_5G 1 5555 3 ""

# OS 가 계속 끄는 지정 Wi-Fi: 5번 점검해도 3번까지만 켠다. Wi-Fi 가 바뀌면 다시 3번.
: > "$T/calls"; echo 0 > "$T/cur"
KEEP=1 bash -c "$cfg; $(fakes twnap 0 5555 0); $fns; for i in 1 2 3 4 5; do wifi_debug_policy; done"
check "OS 가 계속 끄면 3번까지만 다시 켬" "wifi=1 wifi=1 wifi=1" "$(summ)"

# 배선: 실제 기본 간격·초기값으로 periodic_checks 를 틱마다 돌려 첫 호출 틱을 잰다.
: > "$T/calls"; echo 0 > "$T/cur"
out=$(KEEP=1 bash -c "$cfg; $init; $(fakes NOIR_5G 0 5555 4); $fns
  wifi_debug_policy(){ echo \"W \$t\"; }; wadb_keeper_revive(){ echo \"K \$t\"; }
  for t in \$(seq 1 700); do periodic_checks; done")
check "무선 디버깅 정책: 기동 60초 뒤 첫 점검, 이후 60초마다" "60 120" "$(echo "$out" | awk '/^W/{print $2}' | head -2 | tr '\n' ' ' | sed 's/ $//')"
check "앱 점검: 기동 60초 뒤 첫 회, 이후 600초마다" "60 660" "$(echo "$out" | awk '/^K/{print $2}' | head -2 | tr '\n' ' ' | sed 's/ $//')"
# 배선: 실제 1초 루프 본문이 periodic_checks 를 부르는지
check "1초 루프가 periodic_checks 를 부름" 1 "$(sed -n '/^while true; do/,/^done/p' "$SRC" | grep -c '^    periodic_checks$')"
echo "fails=$fails"; exit $fails
