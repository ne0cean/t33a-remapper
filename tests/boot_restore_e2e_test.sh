#!/bin/bash
# boot_restore_e2e_test.sh — t33a_boot.sh 를 통째로 임시 폴더에서 실행해 "시작 때 복구"와 "watchdog 틱 복구" 배선을 실제로 확인한다.
# 폰 경로(/sdcard/Download·/data/local/tmp·Termux adb·/system/bin)만 임시 폴더로 바꾼 사본을 돌리고, 폰 명령은 가짜로 막는다.
# watchdog 의 첫 sleep(15/60/120)에서 relay 사본을 지우고, 두 번째에서 스크립트를 끝낸다. 실제 adb·폰은 부르지 않는다.
# 사용: bash tests/boot_restore_e2e_test.sh [스크립트]
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a_boot.sh}"
T=$(mktemp -d) && [ -n "$T" ] && [ -d "$T" ] || { echo "ABORT: 임시 폴더 생성 실패"; exit 2; }
trap 'rm -rf "$T"' EXIT
grep -q '^restore_missing_scripts' "$SRC" || { echo "ABORT: restore_missing_scripts 호출 없음 ($SRC)"; exit 2; }
fails=0; pass() { echo "PASS $1"; }; fail() { echo "FAIL $1"; fails=$((fails+1)); }
FILES="t33a_boot.sh t33a_relay.sh t33a_start.sh t33a_status.sh T33A_status_wrapper"
mkdir -p "$T/dl" "$T/tmp" "$T/bin" "$T/home/t33a-remapper/scripts"
for f in $FILES; do echo "repo:$f" > "$T/home/t33a-remapper/scripts/$f"; done
: > "$T/dl/.t33a_relay.sh.restore.99999"   # 지난 실행이 남긴 임시 파일 — 시작 때 지워져야 한다
: > "$T/dl/t33a_boot.sh"                    # 0바이트 사본 — Termux:Boot 사본을 덮으면 안 되고, 복구 대상이다(격리 레인 L-SR-2)
mkdir -p "$T/home/.termux/boot"; echo "old-boot" > "$T/home/.termux/boot/t33a_boot.sh"

# 폰 경로를 임시 폴더로 바꾼 사본
sed -e "s#/sdcard/Download#$T/dl#g" -e "s#/data/local/tmp#$T/tmp#g" \
    -e "s#/data/data/com.termux/files/usr/bin/adb#$T/bin/adb#g" -e "s#/system/bin/#$T/bin/#g" "$SRC" > "$T/boot.sh"

# 가짜 명령: 폰 전용 명령은 아무것도 안 하거나 실패한다
for c in termux-wake-lock termux-notification termux-notification-remove termux-toast curl am settings svc cmd pkill; do
  printf '#!/bin/bash\nexit 0\n' > "$T/bin/$c"
done
printf '#!/bin/bash\nexit 1\n' > "$T/bin/adb"; printf '#!/bin/bash\nexit 1\n' > "$T/bin/pgrep"
printf '#!/bin/bash\n[ "$1" = service.adb.tcp.port ] && echo 5555\nexit 0\n' > "$T/bin/getprop"
# GNU stat -c %%Y 흉내(macOS stat 은 -c 없음): 파일이 있으면 지금 시각
printf '#!/bin/bash\n[ "$1" = -c ] && { [ -e "$3" ] && date +%%s || exit 1; exit 0; }\nexec /usr/bin/stat "$@"\n' > "$T/bin/stat"
# sleep: watchdog 주기(15·60·120)만 센다 — 1번째에 relay 사본 삭제, 2번째에 부모(boot.sh)를 끝낸다
cat > "$T/bin/sleep" <<EOF
#!/bin/bash
case "\$1" in 15|60|120) ;; *) exit 0 ;; esac
n=\$(cat "$T/ticks" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$T/ticks"
[ \$n = 1 ] && rm -f "$T/dl/t33a_relay.sh"
[ \$n -ge 2 ] && kill -TERM \$PPID
exit 0
EOF
chmod +x "$T/bin/"*
touch "$T/tmp/t33a.relay_hb"

HOME="$T/home" PATH="$T/bin:$PATH" bash "$T/boot.sh" > "$T/out" 2>&1 & bp=$!
for i in $(seq 1 300); do kill -0 "$bp" 2>/dev/null || break; command sleep 0.2; done
kill -0 "$bp" 2>/dev/null && { kill "$bp" 2>/dev/null; fail "60초 안에 끝나지 않음(sleep 가짜가 안 불림?) — 출력: $(tail -3 "$T/out" | tr '\n' '|')"; }
L="$T/dl/t33a_boot.log"

ok=1; for f in $FILES; do [ "$(cat "$T/dl/$f" 2>/dev/null)" = "repo:$f" ] || ok=0; done
[ "$ok" = 1 ] && pass "실행 끝에 5개 사본 모두 레포 내용" || fail "사본 상태: $(ls "$T/dl" | tr '\n' ' ')"
[ "$(cat "$T/ticks" 2>/dev/null)" = 2 ] && pass "watchdog 루프 2틱 진입" || fail "틱 수 $(cat "$T/ticks" 2>/dev/null)"
[ "$(grep -c '레포 사본에서 복구' "$L" 2>/dev/null)" = 6 ] && pass "복구 로그 6줄(시작 5 + 틱 1) — 로그 초기화 뒤에 기록됨" \
  || fail "복구 로그 $(grep -c '레포 사본에서 복구' "$L" 2>/dev/null)줄"
[ "$(grep '레포 사본에서 복구' "$L" | tail -1 | grep -c t33a_relay.sh)" = 1 ] && pass "틱에서 지운 relay 를 다음 틱 전에 복구" || fail "틱 복구"
[ ! -e "$T/dl/.t33a_relay.sh.restore.99999" ] && pass "시작 때 남은 임시 파일 청소" || fail "임시 파일 잔존"
[ "$(cat "$T/home/.termux/boot/t33a_boot.sh" 2>/dev/null)" = "old-boot" ] && pass "0바이트 다운로드 사본이 Termux:Boot 사본을 덮지 않음" \
  || fail "Termux:Boot 사본 덮임: [$(head -c 40 "$T/home/.termux/boot/t33a_boot.sh" 2>/dev/null)]"
echo "fails=$fails"; exit $fails
