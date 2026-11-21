#!/bin/bash
# boot_restore_scripts_test.sh — 폰 t33a_boot.sh 의 다운로드 폴더 사본 되살리기 시험(2026-11-21).
# 사용: bash tests/boot_restore_scripts_test.sh [스크립트]. 폰·adb 는 부르지 않는다(임시 폴더로만).
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)/scripts/t33a_boot.sh}"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fn=$(sed -n '/^restore_missing_scripts() {/,/^}/p' "$SRC")
[ -n "$fn" ] || { echo "ABORT: restore_missing_scripts 추출 실패 ($SRC)"; exit 2; }
fails=0
FILES="t33a_boot.sh t33a_relay.sh t33a_start.sh t33a_status.sh T33A_status_wrapper"
pass() { echo "PASS $1"; }; fail() { echo "FAIL $1"; fails=$((fails+1)); }

setup() { # 레포 사본 5개를 만들고 다운로드 폴더·로그를 비운다
  rm -rf "$T/repo" "$T/dl"; mkdir -p "$T/repo" "$T/dl"; : > "$T/log"
  for f in $FILES; do echo "repo:$f" > "$T/repo/$f"; done
}
run() { # $1 = 같은 셸에서 부를 횟수
  bash -c "LOG='$T/log'; REPO_SCRIPTS='$T/repo'; DL_DIR='$T/dl'; _RESTORE_WARNED=' '
$fn
for i in \$(seq 1 ${1:-1}); do restore_missing_scripts; done"
}

setup; run
ok=1; for f in $FILES; do [ "$(cat "$T/dl/$f" 2>/dev/null)" = "repo:$f" ] || ok=0; done
[ "$ok" = 1 ] && pass "다운로드 폴더가 비면 5개 모두 레포 사본에서 채움" || fail "5개 복구 ($(ls "$T/dl" | tr '\n' ' '))"
[ -x "$T/dl/t33a_relay.sh" ] && [ -x "$T/dl/t33a_boot.sh" ] && pass ".sh 는 실행 권한" || fail ".sh 실행 권한"
[ "$(grep -c '레포 사본에서 복구' "$T/log")" = 5 ] && pass "복구마다 로그 1줄" || fail "복구 로그 $(grep -c . "$T/log")줄"

setup; for f in $FILES; do echo "live:$f" > "$T/dl/$f"; done; run
ok=1; for f in $FILES; do [ "$(cat "$T/dl/$f")" = "live:$f" ] || ok=0; done
[ "$ok" = 1 ] && [ ! -s "$T/log" ] && pass "모두 있으면 아무것도 덮지 않고 로그도 없음" || fail "있는 파일 보존"

setup; echo "live:relay" > "$T/dl/t33a_relay.sh"; rm "$T/repo/t33a_start.sh"; run
[ "$(cat "$T/dl/t33a_relay.sh")" = "live:relay" ] && pass "있는 relay 는 그대로" || fail "있는 relay 덮음"
[ "$(cat "$T/dl/t33a_status.sh" 2>/dev/null)" = "repo:t33a_status.sh" ] && pass "없는 것만 채움" || fail "없는 것 채우기"
[ ! -e "$T/dl/t33a_start.sh" ] && grep -q 't33a_start.sh 가 다운로드 폴더에 없음 — 복구 못함: 레포 사본 없음' "$T/log" \
  && pass "레포 사본도 없으면 만들지 않고 기록" || fail "레포 사본 부재 처리"

setup; rm "$T/repo/t33a_relay.sh"; run 3
[ "$(grep -c 't33a_relay.sh 가 다운로드 폴더에 없음 — 복구 못함' "$T/log")" = 1 ] && pass "복구 못한 파일 경고는 3틱에 1번만" \
  || fail "경고 반복 $(grep -c 't33a_relay.sh 가' "$T/log")번"

# 같은 셸에서: 복구 실패(경고) → 레포 사본이 생겨 복구 → 다시 지워지고 레포도 없으면 다시 경고
setup; rm "$T/repo/t33a_relay.sh"
got=$(bash -c "LOG='$T/log'; REPO_SCRIPTS='$T/repo'; DL_DIR='$T/dl'; _RESTORE_WARNED=' '
$fn
restore_missing_scripts; echo r > '$T/repo/t33a_relay.sh'; restore_missing_scripts
rm '$T/dl/t33a_relay.sh' '$T/repo/t33a_relay.sh'; restore_missing_scripts
grep -c 't33a_relay.sh 가 다운로드 폴더에 없음 — 복구 못함' '$T/log'")
[ "$got" = 2 ] && pass "복구에 성공하면 경고 표시를 지워 다음 부재 때 다시 경고" || fail "경고 재무장 (got $got)"

# 리뷰 H1: 0바이트 사본은 "없음"으로 보고 채운다
setup; for f in $FILES; do echo "live:$f" > "$T/dl/$f"; done; : > "$T/dl/t33a_relay.sh"; run
[ "$(cat "$T/dl/t33a_relay.sh")" = "repo:t33a_relay.sh" ] && pass "0바이트 사본은 레포 사본으로 채움" || fail "0바이트 사본"

# 리뷰 H1: cp 가 앞부분만 쓰고 실패하면 잘린 사본을 남기지 않고, 다음 틱에 다시 시도한다
setup; printf 'repo:%%s\n' $(seq 1 500) > "$T/repo/t33a_relay.sh"
mkdir -p "$T/bin"; printf '#!/bin/bash\nhead -c 12 "$1" > "$2"; exit 1\n' > "$T/bin/cp"; chmod +x "$T/bin/cp"
bash -c "PATH='$T/bin':\$PATH; LOG='$T/log'; REPO_SCRIPTS='$T/repo'; DL_DIR='$T/dl'; _RESTORE_WARNED=' '
$fn
restore_missing_scripts"
[ ! -e "$T/dl/t33a_relay.sh" ] && [ -z "$(ls -A "$T/dl" | grep restore)" ] \
  && pass "cp 중간 실패면 사본도 임시 파일도 남기지 않음" || fail "잘린 사본 잔존 ($(ls -la "$T/dl" | tr '\n' '|'))"
grep -q 't33a_relay.sh 가 다운로드 폴더에 없음 — 복구 못함: 복사 실패' "$T/log" && pass "복사 실패는 레포 사본 없음과 구분해 기록" || fail "복사 실패 문구"
run
cmp -s "$T/repo/t33a_relay.sh" "$T/dl/t33a_relay.sh" && pass "다음 틱(정상 cp)에 온전히 복구" || fail "재시도 복구"

# cp 는 성공했다고 하는데 내용이 다르면(잘림) 채택하지 않는다
setup; printf '#!/bin/bash\nhead -c 3 "$1" > "$2"; exit 0\n' > "$T/bin/cp"
bash -c "PATH='$T/bin':\$PATH; LOG='$T/log'; REPO_SCRIPTS='$T/repo'; DL_DIR='$T/dl'; _RESTORE_WARNED=' '
$fn
restore_missing_scripts"
[ ! -e "$T/dl/t33a_boot.sh" ] && pass "cp 가 성공을 돌려도 원본과 다르면 채택하지 않음" || fail "내용 대조 없음"
rm -rf "$T/bin"

# 배선: 시작 때(로그 새로 쓴 뒤)와 watchdog 매 틱에 부른다
start_ln=$(grep -nE '^restore_missing_scripts( |$)' "$SRC" | head -1 | cut -d: -f1)   # 정의 줄(`…() {`)은 제외
trunc_ln=$(grep -n 'boot started (PID \$\$)" > "\$LOG"' "$SRC" | cut -d: -f1)
[ -n "$start_ln" ] && [ -n "$trunc_ln" ] && [ "$start_ln" -gt "$trunc_ln" ] \
  && pass "시작 때 호출이 로그를 새로 쓰는 줄 뒤" || fail "시작 호출 위치(start=$start_ln trunc=$trunc_ln)"
sed -n '/^while true; do/,/^done/p' "$SRC" | grep -q '^    restore_missing_scripts' \
  && pass "watchdog 루프에서 호출" || fail "watchdog 루프 호출 없음"
echo "fails=$fails"; exit $fails
