#!/bin/bash
# boot_sync_e2e_test.sh — t33a_boot.sh 를 통째로 임시 폴더에서 실행해 레포 사본 맞추기 배선(시작·watchdog 틱·부팅 사본·상태 위젯)을 확인한다.
# 폰 경로(/sdcard/Download·/data/local/tmp·Termux adb·/system/bin)만 임시 폴더로 바꾼 사본을 돌리고, 폰 명령은 가짜로 막는다.
# 첫 adb 호출(초기 시작 단계 — relay 를 띄우기 직전, watchdog 루프 전)에 다운로드 폴더를 스냅샷한다 = 시작 맞추기만의 결과.
# watchdog 주기 sleep(15/60/120) 1번째: relay 를 잘라 놓는다. 2번째: boot.sh 종료.
# 사용: bash tests/boot_sync_e2e_test.sh [boot.sh]
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SRC="${1:-$ROOT/scripts/t33a_boot.sh}"
T=$(mktemp -d) && [ -n "$T" ] && [ -d "$T" ] || { echo "ABORT: 임시 폴더 생성 실패"; exit 2; }
trap 'rm -rf "$T"' EXIT
fails=0; pass() { echo "PASS $1"; }; fail() { echo "FAIL $1"; fails=$((fails+1)); }
FILES="t33a_boot.sh t33a_relay.sh t33a_start.sh t33a_status.sh T33A_status_wrapper"
R="$T/home/t33a-remapper/scripts"
mkdir -p "$T/dl" "$T/tmp" "$T/bin" "$T/snap0" "$R" "$T/home/.termux/boot" "$T/home/.shortcuts"
for f in $FILES; do echo "repo:$f" > "$R/$f"; done
cp "$ROOT/scripts/t33a_sync.sh" "$R/t33a_sync.sh"
# 시작 상태: boot 0바이트·relay 잘림·status 옛 버전·start 없음, 끊긴 교체 임시 파일, 옛 부팅 사본·옛 상태 위젯
: > "$T/dl/t33a_boot.sh"; echo "rep" > "$T/dl/t33a_relay.sh"; echo "old" > "$T/dl/t33a_status.sh"; echo "old" > "$T/dl/T33A_status_wrapper"
: > "$T/dl/.t33a_relay.sh.sync.99999"; echo "secret" > "$T/dl/.t33a_telegram.conf"; touch -t 202001010000 "$T/dl/.t33a_relay.sh.sync.99999"   # 1분 넘은 잔해
echo "old-boot" > "$T/home/.termux/boot/t33a_boot.sh"; echo "old-widget" > "$T/home/.shortcuts/T33A-status"
# 복구 위젯: 다운로드 폴더 래퍼가 0바이트면 설치된 위젯을 덮지 않는다. 부팅·위젯 폴더의 끊긴 교체 임시 파일도 청소 대상
: > "$T/dl/T33A_wrapper"; echo "old-recover" > "$T/home/.shortcuts/T33A"
: > "$T/home/.termux/boot/.t33a_boot.sh.sync.4242"; : > "$T/home/.shortcuts/.T33A.sync.4242"; echo other > "$T/home/.shortcuts/HSC"
: > "$T/home/.shortcuts/.HSC.sync.1"   # 남의 숨김 임시 파일 — 우리 이름이 아니니 보존
touch -t 202001010000 "$T/home/.termux/boot/.t33a_boot.sh.sync.4242" "$T/home/.shortcuts/.T33A.sync.4242" "$T/home/.shortcuts/.HSC.sync.1"
BOOT_INODE=$(ls -i "$T/home/.termux/boot/t33a_boot.sh" | awk '{print $1}')

sed -e "s#/sdcard/Download#$T/dl#g" -e "s#/data/local/tmp#$T/tmp#g" \
    -e "s#/data/data/com.termux/files/usr/bin/adb#$T/bin/adb#g" -e "s#/system/bin/#$T/bin/#g" "$SRC" > "$T/boot.sh"
for c in termux-wake-lock termux-notification termux-notification-remove termux-toast curl am settings svc cmd pkill; do
  printf '#!/bin/bash\nexit 0\n' > "$T/bin/$c"
done
# adb 가짜: 첫 호출 때 snap0, relay 기동 명령(setsid) 때 snapS 에 다운로드 폴더를 찍는다. $T/adb_ok 가 있으면 성공(루프백 연결됨)
cat > "$T/bin/adb" <<EOF
#!/bin/bash
[ -e "$T/snap0/.taken" ] || { cp -p "$T/dl/"* "$T/snap0/" 2>/dev/null; : > "$T/snap0/.taken"; }
case "\$*" in *setsid*) [ -e "$T/snapS/.taken" ] || { mkdir -p "$T/snapS"; cp -p "$T/dl/"* "$T/snapS/" 2>/dev/null; : > "$T/snapS/.taken"; } ;; esac
[ -e "$T/adb_ok" ] && exit 0
exit 1
EOF
printf '#!/bin/bash\nexit 1\n' > "$T/bin/pgrep"
printf '#!/bin/bash\n[ "$1" = service.adb.tcp.port ] && echo 5555\nexit 0\n' > "$T/bin/getprop"
printf '#!/bin/bash\n[ "$1" = -c ] && { [ -e "$3" ] && date +%%s || exit 1; exit 0; }\nexec /usr/bin/stat "$@"\n' > "$T/bin/stat"
cat > "$T/bin/sleep" <<EOF
#!/bin/bash
case "\$1" in 15|60|120) ;; *) exit 0 ;; esac
n=\$(cat "$T/ticks" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$T/ticks"
[ \$n = 1 ] && echo "re" > "$T/dl/t33a_relay.sh"
[ \$n -ge 2 ] && kill -TERM \$PPID
exit 0
EOF
chmod +x "$T/bin/"*
touch "$T/tmp/t33a.relay_hb"

run_boot() {   # boot.sh 를 띄우고 PID 로만 기다린다(최대 60초)
  rm -f "$T/ticks"; HOME="$T/home" PATH="$T/bin:$PATH" bash "$T/boot.sh" > "$T/out" 2>&1 & bp=$!
  for i in $(seq 1 300); do kill -0 "$bp" 2>/dev/null || break; command sleep 0.2; done
  kill -0 "$bp" 2>/dev/null && { kill "$bp" 2>/dev/null; fail "60초 안에 끝나지 않음 — 출력: $(tail -3 "$T/out" | tr '\n' '|')"; }
}
run_boot
L="$T/dl/t33a_boot.log"
same() { for f in $FILES; do cmp -s "$R/$f" "$1/$f" || return 1; done; }

[ -e "$T/snap0/.taken" ] || fail "초기 시작 단계에서 adb 가 불리지 않음(스냅샷 없음)"
same "$T/snap0" && pass "relay 기동 단계(watchdog 전)에 이미 5개 사본이 레포와 같음" || fail "시작 단계 사본: $(for f in $FILES; do printf '%s=[%s] ' $f "$(head -c 20 "$T/snap0/$f" 2>/dev/null)"; done)"
same "$T/dl" && pass "틱에서 잘라 놓은 relay 를 다음 틱에 되돌림" || fail "실행 끝 relay=[$(cat "$T/dl/t33a_relay.sh")]"
[ "$(cat "$T/ticks" 2>/dev/null)" = 2 ] && pass "watchdog 루프 2틱 진입" || fail "틱 수 $(cat "$T/ticks" 2>/dev/null)"
n=$(grep -c '레포 사본으로 교체' "$L" 2>/dev/null); [ "$n" = 6 ] && pass "교체 로그 6줄(시작 5 + 틱 1) — 로그 초기화 뒤 기록" || fail "교체 로그 ${n}줄"
[ "$(cat "$T/home/.termux/boot/t33a_boot.sh")" = "repo:t33a_boot.sh" ] && pass "Termux:Boot 사본은 레포 사본에서(0바이트 다운로드 사본 무시)" \
  || fail "Termux:Boot 사본: [$(head -c 40 "$T/home/.termux/boot/t33a_boot.sh")]"
[ "$(ls -i "$T/home/.termux/boot/t33a_boot.sh" | awk '{print $1}')" != "$BOOT_INODE" ] && pass "부팅 사본 교체는 mv(새 inode — 실행 중인 자기 파일을 제자리에서 덮지 않음)" || fail "부팅 사본 제자리 덮어쓰기"
[ "$(cat "$T/home/.shortcuts/T33A")" = "old-recover" ] && pass "0바이트 복구 위젯 래퍼가 설치된 T33A 위젯을 덮지 않음" || fail "T33A 위젯: [$(cat "$T/home/.shortcuts/T33A")]"
[ ! -e "$T/home/.termux/boot/.t33a_boot.sh.sync.4242" ] && [ ! -e "$T/home/.shortcuts/.T33A.sync.4242" ] && [ "$(cat "$T/home/.shortcuts/HSC")" = other ] && [ -e "$T/home/.shortcuts/.HSC.sync.1" ] \
  && pass "부팅·위젯 폴더의 임시 파일도 청소(남의 위젯 보존)" || fail "부팅·위젯 폴더 청소"
[ "$(cat "$T/home/.shortcuts/T33A-status")" = "repo:T33A_status_wrapper" ] && pass "상태 위젯은 레포 사본에서" || fail "상태 위젯: [$(cat "$T/home/.shortcuts/T33A-status")]"
[ ! -e "$T/dl/.t33a_relay.sh.sync.99999" ] && [ "$(cat "$T/dl/.t33a_telegram.conf")" = secret ] && pass "시작 때 임시 파일만 청소(비밀 conf 보존)" || fail "청소"
[ -x "$T/home/.shortcuts/T33A-status" ] && [ -x "$T/home/.termux/boot/t33a_boot.sh" ] && pass "부팅 사본·상태 위젯 실행 권한" || fail "실행 권한 빠짐"

# 2회차: 레포가 없는 폰(초기 설치 전 등) — 예전 폴백. 0바이트 다운로드 사본이 부팅 사본을 덮지 않고, 맞추기 생략을 기록
rm -rf "$T/home/t33a-remapper" "$T/dl/"* ; : > "$T/dl/t33a_boot.sh"; echo "rep" > "$T/dl/t33a_relay.sh"; echo "keep-boot" > "$T/home/.termux/boot/t33a_boot.sh"
run_boot
[ "$(cat "$T/home/.termux/boot/t33a_boot.sh")" = keep-boot ] && pass "레포 없음: 0바이트 다운로드 사본이 부팅 사본을 덮지 않음(폴백 -s)" || fail "레포 없음 폴백: [$(cat "$T/home/.termux/boot/t33a_boot.sh")]"
grep -q 't33a_sync.sh 없음 — 다운로드 폴더 사본 맞추기 생략' "$T/dl/t33a_boot.log" && pass "레포 없음: 맞추기 생략을 로그에 남김" || fail "레포 없음 로그 없음"
[ "$(grep -c '레포 사본으로 교체' "$T/dl/t33a_boot.log")" = 0 ] && pass "레포 없음: 교체 시도 없음" || fail "레포 없음인데 교체 기록"

# 3회차: 재부팅 사고 경로 — relay 죽음(hb 없음) → 루프백 연결 → start_relay. relay 를 띄우는 그 순간 사본이 이미 레포와 같아야 한다
mkdir -p "$R"; for f in $FILES; do echo "repo:$f" > "$R/$f"; done; cp "$ROOT/scripts/t33a_sync.sh" "$R/t33a_sync.sh"
rm -rf "$T/dl/"* "$T/snapS"; : > "$T/dl/t33a_relay.sh"; echo "rep" > "$T/dl/t33a_boot.sh"
rm -f "$T/tmp/t33a.relay_hb" "$T/tmp/t33a.heartbeat"; : > "$T/adb_ok"
echo "new-recover" > "$T/dl/T33A_wrapper"; chmod 644 "$T/dl/T33A_wrapper"   # 복구 위젯 정상 설치 경로
run_boot
grep -q 'starting relay via ADB' "$T/dl/t33a_boot.log" && pass "3회차가 relay 기동 시도 로그를 남김(진입 증거는 아래 setsid 스냅샷)" || fail "3회차: relay 기동 경로 미진입 — $(tail -3 "$T/dl/t33a_boot.log" | tr '\n' '|')"
[ -e "$T/snapS/.taken" ] && same "$T/snapS" && pass "relay 를 띄우는 순간 5개 사본이 레포와 같음(재부팅 사고 경로)" \
  || fail "relay 기동 시점 사본: $(for f in $FILES; do printf '%s=[%s] ' $f "$(head -c 12 "$T/snapS/$f" 2>/dev/null)"; done)"
[ "$(cat "$T/home/.shortcuts/T33A")" = new-recover ] && [ -x "$T/home/.shortcuts/T33A" ] && pass "복구 위젯: 내용 있는 래퍼면 설치 + 실행 권한" || fail "복구 위젯 설치: [$(cat "$T/home/.shortcuts/T33A")]"
echo "fails=$fails"; exit $fails
