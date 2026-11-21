#!/bin/bash
# 사용: bash tests/tls_endpoints_test.sh [스크립트]. 실제 adb·dns-sd 는 부르지 않는다.
# tls_endpoints 단독 시험: adb 자체 탐색이 비었을 때 dns-sd 로 이 폰(시리얼)의 주소:포트를 찾는지.
# 변이 대조(2026-11-21): 이전 main 에는 함수가 없어 ABORT(exit 2).
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a-auto-tcpip.sh}"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fn=$(sed -n '/^tls_endpoints() {/,/^}/p' "$SRC"); run=$(sed -n '/^dnssd_run() {/,/^}/p' "$SRC")
[ -n "$fn" ] && [ -n "$run" ] || { echo "ABORT: tls_endpoints/dnssd_run 추출 실패 ($SRC)"; exit 2; }
fails=0

# 가짜 adb: $T/adb_out 내용을 mdns 목록으로 낸다
printf '#!/bin/bash\n[ "$1 $2" = "mdns services" ] && cat "%s/adb_out"\n' "$T" > "$T/fakeadb"
# 가짜 dns-sd: 호출을 기록하고 -B/-L/-G 별 준비된 파일을 낸 뒤 바로 끝난다(실물은 안 끝나므로 dnssd_run 이 죽인다)
cat > "$T/fakednssd" <<EOF
#!/bin/bash
echo "\$*" >> "$T/calls"
case "\$1" in -B) cat "$T/b_out" ;; -L) cat "$T/l_out" ;; -G) cat "$T/g_out" ;; esac
: > "$T/done"
EOF
chmod +x "$T/fakeadb" "$T/fakednssd"

B_HDR='Timestamp     A/R    Flags  if Domain               Service Type         Instance Name'
b_line() { echo " 9:08:52.801  Add        2  11 local.               _adb-tls-connect._tcp. $1"; }
L_OK=' 9:14:52.401  adb-SER1-wFZOh4._adb-tls-connect._tcp.local. can be reached at Android_X.local.:38937 (interface 11)'
G_HDR='Timestamp     A/R  Flags         IF  Hostname                               Address                                      TTL'
G_OK=' 9:15:42.013  Add  40000002      11  Android_X.local.                192.168.0.18                                 120'

case_() { # name want want_dnssd_calls(빈 값이면 미검사)
  : > "$T/calls"
  got=$(bash -c "
    ADB='$T/fakeadb'; DNSSD='$T/fakednssd'; PHONE_SERIAL=SER1
    # 가짜 dns-sd 가 끝냈다는 표시를 기다린다 — 그냥 넘기면 뜨기도 전에 kill 된다(부하 높을 때 실측)
    sleep(){ local i=0; while [ ! -e '$T/done' ] && [ \$i -lt 100 ]; do command sleep 0.05; i=\$((i+1)); done; rm -f '$T/done'; }
    $run
    $fn
    tls_endpoints
  " | tr '\n' ' ' | sed 's/ $//')
  n=$(grep -c . "$T/calls")
  if [ "$got" = "$2" ] && { [ -z "$3" ] || [ "$n" = "$3" ]; }; then echo "PASS $1"
  else echo "FAIL $1 (want [$2] calls=${3:--} got [$got] calls=$n)"; fails=$((fails+1)); fi
}

echo "adb-SER1-abc	_adb-tls-connect._tcp	192.168.0.18:40603" > "$T/adb_out"
: > "$T/b_out"; : > "$T/l_out"; : > "$T/g_out"
case_ "adb 탐색에 있으면 그대로 쓰고 dns-sd 는 안 부름" "192.168.0.18:40603" 0

: > "$T/adb_out"
{ echo "$B_HDR"; b_line adb-SER1-wFZOh4; } > "$T/b_out"; echo "$L_OK" > "$T/l_out"; { echo "$G_HDR"; echo "$G_OK"; } > "$T/g_out"
case_ "adb 탐색이 비면 dns-sd 로 주소:포트" "192.168.0.18:38937" 3

echo "adb-SER1-abc	_adb-tls-pairing._tcp	192.168.0.18:44855" > "$T/adb_out"
case_ "adb 탐색에 페어링 항목만 있으면 빈 것으로 보고 dns-sd 로" "192.168.0.18:38937" 3
: > "$T/adb_out"

{ echo "$B_HDR"; b_line adb-OTHER9-zzzzzz; } > "$T/b_out"
case_ "다른 시리얼 광고는 고르지 않음(조회도 안 함)" "" 1

{ echo "$B_HDR"; b_line adb-SER1-wFZOh4; b_line adb-SER1-wFZOh4; } > "$T/b_out"
case_ "같은 광고가 두 번 떠도 한 번만" "192.168.0.18:38937" 3

{ echo "$B_HDR"; b_line adb-SER1-wFZOh4; } > "$T/b_out"; : > "$T/l_out"
case_ "포트 조회가 비면 내지 않음" "" 2

echo "$L_OK" > "$T/l_out"; echo "$G_HDR" > "$T/g_out"
case_ "주소 조회가 비면 내지 않음" "" 3

{ echo "$G_HDR"; echo ' 9:15:42.013  Add  2  0  Android_X.local.  fe80::1  120'; echo "$G_OK"; } > "$T/g_out"
case_ "IPv4 가 아닌 줄은 건너뜀" "192.168.0.18:38937" 3

: > "$T/b_out"
case_ "광고가 없으면 빈 출력" "" 1
echo "fails=$fails"; exit $fails
