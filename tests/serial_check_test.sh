#!/bin/bash
# serial_check_test.sh — 맥 데몬이 낯선 경로(Tailscale·게이트웨이)로 붙은 뒤 시리얼로 신원을 확인하는 부분 시험(2026-11-21).
# 빈 응답은 2번 더 묻고, 값이 오면 다시 묻지 않으며, 확인 실패·불일치 모두 연결을 끊는다.
# 사용: bash tests/serial_check_test.sh [스크립트]. 실제 adb 는 부르지 않는다.
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a-auto-tcpip.sh}"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
sof=$(sed -n '/^serial_of() {/,/^}/p' "$SRC"); ens=$(sed -n '/^ensure_device() {/,/^}/p' "$SRC")
[ -n "$sof" ] && [ -n "$ens" ] || { echo "ABORT: serial_of/ensure_device 추출 실패 ($SRC)"; exit 2; }
fails=0

# 가짜 adb: Tailscale 주소만 connect 성공. getprop 응답은 $T/answers 의 줄을 차례로 낸다(다 쓰면 마지막 줄 반복).
cat > "$T/fakeadb" <<EOF
#!/bin/bash
echo "\$*" >> "$T/adb_calls"
case "\$1" in
  devices) echo "List of devices attached" ;;
  mdns) : ;;
  connect) [ "\$2" = "100.107.190.45:5555" ] && echo "connected to \$2" || echo "failed to connect to \$2" ;;
  -s) if [ "\$3 \$4 \$5" = "shell getprop ro.serialno" ]; then
        n=\$(cat "$T/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$T/n"
        a=\$(sed -n "\${n}p" "$T/answers"); [ -z "\$a" ] && [ "\$n" -gt "\$(grep -c '' "$T/answers")" ] && a=\$(tail -1 "$T/answers")
        [ "\$a" = "-" ] || printf '%s\r\n' "\$a"
      fi ;;
esac
EOF
chmod +x "$T/fakeadb"

case_() { # name answers(공백 구분, '-'=빈 응답) want_out want_getprop_calls want_disconnect(0|1) want_log
  : > "$T/adb_calls"; : > "$T/log"; rm -f "$T/n"; printf '%s\n' $2 > "$T/answers"
  got=$(bash -c "ADB='$T/fakeadb'; PHONE_SERIAL=SER1; PHONE_IP=192.168.0.18; PHONE_TS_IP=100.107.190.45; HOTSPOT_SSID=none
    log(){ echo \"\$1\" >> '$T/log'; }; sleep(){ :; }; networksetup(){ :; }; route(){ :; }; tls_endpoints(){ :; }
    $sof
    $ens
    ensure_device")
  gp=$(grep -c 'shell getprop ro.serialno' "$T/adb_calls"); dc=$(grep -c '^disconnect 100.107.190.45:5555' "$T/adb_calls")
  if [ "$got" = "$3" ] && [ "$gp" = "$4" ] && [ "$dc" = "$5" ] && grep -qF -- "$6" "$T/log"; then echo "PASS $1"
  else echo "FAIL $1 (want out=[$3] getprop=$4 disc=$5 log~[$6] got out=[$got] getprop=$gp disc=$dc log=[$(tr '\n' '|' < "$T/log")])"; fails=$((fails+1)); fi
}
case_ "첫 응답이 맞으면 한 번만 묻고 접속"            "SER1"        "100.107.190.45:5555" 1 0 "후보 경로로 접속"
case_ "빈 응답 뒤 맞는 값이면 재시도로 접속(11-21 오판)" "- SER1"      "100.107.190.45:5555" 2 0 "후보 경로로 접속"
case_ "빈 응답 2번 뒤 맞는 값이면 접속"               "- - SER1"    "100.107.190.45:5555" 3 0 "후보 경로로 접속"
case_ "끝내 빈 응답이면 3번만 묻고 끊음(응답 없음 기록)" "- - - SER1"  ""                    3 1 "신원 확인 응답 없음"
case_ "다른 시리얼이면 다시 묻지 않고 끊음"           "OTHER9 SER1" ""                    1 1 "시리얼 불일치"
# 응답 없음과 불일치는 로그로 구분돼야 한다
: > "$T/adb_calls"; : > "$T/log"; rm -f "$T/n"; printf '%s\n' - - - > "$T/answers"
bash -c "ADB='$T/fakeadb'; PHONE_SERIAL=SER1; PHONE_IP=192.168.0.18; PHONE_TS_IP=100.107.190.45; HOTSPOT_SSID=none
  log(){ echo \"\$1\" >> '$T/log'; }; sleep(){ :; }; networksetup(){ :; }; route(){ :; }; tls_endpoints(){ :; }
  $sof
  $ens
  ensure_device" >/dev/null
grep -q "시리얼 불일치" "$T/log" && { echo "FAIL 응답 없음을 불일치로 기록"; fails=$((fails+1)); } || echo "PASS 응답 없음은 불일치로 기록하지 않음"
echo "fails=$fails"; exit $fails
