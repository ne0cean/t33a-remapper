#!/bin/bash
# 사용: bash tests/tls_endpoints_test.sh [스크립트]. 실제 adb·dns-sd 는 부르지 않는다.
# ① tls_endpoints: adb 탐색에 이 폰이 없을 때 dns-sd 로 주소:포트를 찾는지(호출 인자·대역 필터·정리 포함)
# ② ensure_device: 그 결과로 알려진 IP 우선·시리얼 확인·불일치 시 연결 해제가 배선돼 있는지
# 가짜 dns-sd 는 실물처럼 스스로 끝나지 않는다 — dnssd_run 이 죽이지 않으면 케이스가 느려져 FAIL 한다.
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a-auto-tcpip.sh}"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fn=$(sed -n '/^tls_endpoints() {/,/^}/p' "$SRC"); run=$(sed -n '/^dnssd_run() (/,/^)/p' "$SRC")
ens=$(sed -n '/^ensure_device() {/,/^}/p' "$SRC"); sof=$(sed -n '/^serial_of() {/,/^}/p' "$SRC")   # serial_of 없는 이전 판도 허용
[ -n "$fn" ] && [ -n "$run" ] && [ -n "$ens" ] || { echo "ABORT: tls_endpoints/dnssd_run/ensure_device 추출 실패 ($SRC)"; exit 2; }
fails=0

# 가짜 adb: mdns 목록·connect 성공 대상·시리얼을 파일에서 읽고, 모든 호출을 기록한다
cat > "$T/fakeadb" <<EOF
#!/bin/bash
echo "\$*" >> "$T/adb_calls"
case "\$1" in
  mdns) cat "$T/adb_out" ;;
  devices) echo "List of devices attached" ;;
  connect) grep -qxF "\$2" "$T/connect_ok" 2>/dev/null && echo "connected to \$2" || echo "failed to connect to \$2" ;;
  -s) [ "\$3 \$4 \$5" = "shell getprop ro.serialno" ] && cat "$T/serial_of" ;;
esac
EOF
# 가짜 dns-sd: 인자를 기록하고 준비된 출력을 낸 뒤 끝나지 않는다(exec 라 PID 가 그대로 — kill 대상)
cat > "$T/fakednssd" <<EOF
#!/bin/bash
echo "\$*" >> "$T/calls"; echo \$\$ >> "$T/pids"
case "\$1" in -B) cat "$T/b_out" ;; -L) cat "$T/l_out" ;; -G) cat "$T/g_out" ;; esac
: > "$T/done"
exec sleep 20
EOF
chmod +x "$T/fakeadb" "$T/fakednssd"

B_HDR='Timestamp     A/R    Flags  if Domain               Service Type         Instance Name'
b_line() { echo " 9:08:52.801  ${2:-Add}        2  11 local.               _adb-tls-connect._tcp. $1"; }
L_OK=' 9:14:52.401  adb-SER1-wFZOh4._adb-tls-connect._tcp.local. can be reached at Android_X.local.:38937 (interface 11)'
G_HDR='Timestamp     A/R  Flags         IF  Hostname                               Address                                      TTL'
g_line() { echo " 9:15:42.013  ${2:-Add}  40000002      11  Android_X.local.                $1                                 120"; }

# 셸 머리말: 가짜 주입 + sleep 은 "가짜 dns-sd 가 출력을 끝냈다"는 표시까지만 기다린다(부하 높을 때 뜨기 전 kill 방지)
PRE="ADB='$T/fakeadb'; DNSSD='$T/fakednssd'; PHONE_SERIAL=SER1; DNSSD_BROWSE_SEC=3; DNSSD_QUERY_SEC=2
PHONE_IP=192.168.0.18; PHONE_TS_IP=100.107.190.45; HOTSPOT_SSID=none; LOGF='$T/log'
log(){ echo \"\$1\" >> \"\$LOGF\"; }; networksetup(){ :; }; route(){ :; }
sleep(){ local i=0; while [ ! -e '$T/done' ] && [ \$i -lt 100 ]; do command sleep 0.05; i=\$((i+1)); done; rm -f '$T/done'; }
$run
$fn
$sof
$ens"

check() { # name got want [want_calls 파일 내용] [elapsed]
  local ok=1
  [ "$2" = "$3" ] || ok=0
  [ -z "$4" ] || [ "$(cat "$T/calls" 2>/dev/null)" = "$4" ] || ok=0
  [ "${5:-0}" -lt 8 ] || ok=0
  # 남은 가짜 dns-sd 는 기록해 둔 PID 로만 판정·정리한다 — 이름 패턴(pkill -f)은 무관한 프로세스를 죽인다(리뷰 2R)
  local pid; for pid in $(cat "$T/pids" 2>/dev/null); do kill -0 "$pid" 2>/dev/null && { ok=0; kill "$pid" 2>/dev/null; }; done
  : > "$T/pids"
  if [ "$ok" = 1 ]; then echo "PASS $1"
  else echo "FAIL $1 (want [$3] got [$2] ${5:-0}초, dns-sd 호출: $(tr '\n' '|' < "$T/calls" 2>/dev/null))"; fails=$((fails+1)); fi
}
ep() { # name want [want_calls]
  : > "$T/calls"; rm -f "$T/done"; local s e got
  s=$(date +%s); got=$(bash -c "$PRE
tls_endpoints" | tr '\n' ' ' | sed 's/ $//'); e=$(date +%s)
  check "$1" "$got" "$2" "$3" $((e-s))
}
CALLS_OK='-B _adb-tls-connect._tcp local.
-L adb-SER1-wFZOh4 _adb-tls-connect._tcp local.
-G v4 Android_X.local.'
CALLS_B='-B _adb-tls-connect._tcp local.'

echo "── tls_endpoints"
echo "adb-SER1-abc	_adb-tls-connect._tcp	192.168.0.18:40603" > "$T/adb_out"
: > "$T/b_out"; : > "$T/l_out"; : > "$T/g_out"
ep "adb 탐색에 이 폰이 있으면 그대로 쓰고 dns-sd 는 안 부름" "192.168.0.18:40603" ""

: > "$T/adb_out"
{ echo "$B_HDR"; b_line adb-SER1-wFZOh4; } > "$T/b_out"; echo "$L_OK" > "$T/l_out"; { echo "$G_HDR"; g_line 192.168.0.18; } > "$T/g_out"
ep "adb 탐색이 비면 dns-sd 로 주소:포트(호출 인자·안 끝나는 dns-sd 정리까지)" "192.168.0.18:38937" "$CALLS_OK"

echo "adb-SER1-abc	_adb-tls-pairing._tcp	192.168.0.18:44855" > "$T/adb_out"
ep "adb 탐색에 페어링 항목만 있으면 빈 것으로 보고 dns-sd 로" "192.168.0.18:38937" "$CALLS_OK"

echo "adb-OTHER9-zzz	_adb-tls-connect._tcp	192.168.0.77:41000" > "$T/adb_out"
ep "adb 탐색에 다른 기기만 있으면 그 항목 + dns-sd 로 찾은 이 폰" "192.168.0.77:41000 192.168.0.18:38937" "$CALLS_OK"
: > "$T/adb_out"

{ echo "$G_HDR"; g_line 218.38.137.27; g_line 192.168.0.18; } > "$T/g_out"
ep "주소 조회가 공인 IP 를 먼저 내도 사설 주소만" "192.168.0.18:38937" "$CALLS_OK"

{ echo "$G_HDR"; g_line 192.168.0.18; g_line 100.107.190.45; g_line 192.168.0.18; g_line 100.128.0.1; g_line 172.32.0.1; } > "$T/g_out"
ep "사설·CGNAT 주소는 전부, 중복 없이(대역 밖 100.128·172.32 는 버림)" "100.107.190.45:38937 192.168.0.18:38937" "$CALLS_OK"

{ echo "$G_HDR"; g_line 192.168.0.18 Rmv; } > "$T/g_out"
ep "주소 조회의 Rmv 줄은 쓰지 않음" "" "$CALLS_OK"
{ echo "$G_HDR"; g_line 192.168.0.18; } > "$T/g_out"

{ echo "$B_HDR"; b_line adb-SER1-wFZOh4 Rmv; } > "$T/b_out"
ep "광고의 Rmv 줄은 쓰지 않음(조회도 안 함)" "" "$CALLS_B"

{ echo "$B_HDR"; b_line adb-OTHER9-zzzzzz; } > "$T/b_out"
ep "다른 시리얼 광고는 고르지 않음(조회도 안 함)" "" "$CALLS_B"

{ echo "$B_HDR"; b_line adb-SER1-wFZOh4; b_line adb-SER1-wFZOh4; } > "$T/b_out"
ep "같은 광고가 두 번 떠도 한 번만" "192.168.0.18:38937" "$CALLS_OK"

{ echo "$B_HDR"; b_line adb-SER1-wFZOh4; } > "$T/b_out"; : > "$T/l_out"
ep "포트 조회가 비면 내지 않음" "" "-B _adb-tls-connect._tcp local.
-L adb-SER1-wFZOh4 _adb-tls-connect._tcp local."

echo "$L_OK" > "$T/l_out"; echo "$G_HDR" > "$T/g_out"
ep "주소 조회가 비면 내지 않음" "" "$CALLS_OK"

: > "$T/b_out"
ep "광고가 없으면 빈 출력" "" "$CALLS_B"

echo "── ensure_device 배선"
ed() { # name want_out want_adb_grep(있어야 할 호출, 빈 값이면 미검사) want_log_grep
  : > "$T/calls"; : > "$T/adb_calls"; : > "$T/log"; rm -f "$T/done"; local s e got ok=1
  s=$(date +%s); got=$(bash -c "$PRE
ensure_device" | tr '\n' ' ' | sed 's/ $//'); e=$(date +%s)
  [ -z "$3" ] || grep -qF -- "$3" "$T/adb_calls" || ok=0
  [ -z "$4" ] || grep -qF -- "$4" "$T/log" || ok=0
  [ "$ok" = 1 ] && check "$1" "$got" "$2" "" $((e-s)) || { echo "FAIL $1 (adb 호출·로그 불일치: $(tr '\n' '|' < "$T/adb_calls"))"; fails=$((fails+1)); }
}
: > "$T/adb_out"; { echo "$B_HDR"; b_line adb-SER1-wFZOh4; } > "$T/b_out"; echo "$L_OK" > "$T/l_out"
{ echo "$G_HDR"; g_line 192.168.0.18; } > "$T/g_out"; echo "192.168.0.18:38937" > "$T/connect_ok"; echo SER1 > "$T/serial_of"
ed "5555 가 닫혀도 dns-sd 로 찾은 알려진 IP 접속점에 붙음" "192.168.0.18:38937" "connect 192.168.0.18:38937" ""

{ echo "$G_HDR"; g_line 192.168.7.55; } > "$T/g_out"; echo "192.168.7.55:38937" > "$T/connect_ok"
ed "IP 가 바뀌어도 시리얼이 맞으면 붙고 기록" "192.168.7.55:38937" "-s 192.168.7.55:38937 shell getprop ro.serialno" "IP 변경 감지"

echo OTHER9 > "$T/serial_of"
ed "시리얼이 다르면 붙지 않고 연결 해제" "" "disconnect 192.168.7.55:38937" ""

: > "$T/connect_ok"; echo SER1 > "$T/serial_of"
ed "접속이 안 되면 빈 출력" "" "connect 192.168.7.55:38937" ""
echo "fails=$fails"; exit $fails
