#!/bin/bash
# sync_test.sh — scripts/t33a_sync.sh(레포 사본 맞추기 단일 복사기)와 그것을 쓰는 start.sh·update.sh 설치 구간 시험.
# 폰·adb·git 은 부르지 않는다(임시 폴더로만). 사용: bash tests/sync_test.sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; LIB="${1:-$ROOT/scripts/t33a_sync.sh}"
T=$(mktemp -d) && [ -n "$T" ] && [ -d "$T" ] || { echo "ABORT: 임시 폴더 생성 실패"; exit 2; }
trap 'rm -rf "$T"' EXIT
fails=0; pass() { echo "PASS $1"; }; fail() { echo "FAIL $1"; fails=$((fails+1)); }
FILES="t33a_boot.sh t33a_relay.sh t33a_start.sh t33a_status.sh T33A_status_wrapper"
fresh() {   # 레포 5개(내용 있음) + 빈 다운로드 폴더 + 새 셸 상태
  rm -rf "$T/repo" "$T/dl" "$T/log"; mkdir -p "$T/repo" "$T/dl"
  for f in $FILES; do printf 'repo:%s\n%s\n' "$f" "$(head -c 300 /dev/zero | tr '\0' x)" > "$T/repo/$f"; done
}
run() { ( export T33A_REPO_SCRIPTS="$T/repo"; . "$LIB"; "$@" ); }   # 매 호출 새 서브셸(경고 기억 없음)
same_all() { for f in $FILES; do cmp -s "$T/repo/$f" "$T/dl/$f" || return 1; done; }
inode() { ls -i "$1" | awk '{print $1}'; }

# 1. 없음·0바이트·잘림·옛 버전 → 전부 레포와 같게
fresh; : > "$T/dl/t33a_relay.sh"; head -c 50 "$T/repo/t33a_boot.sh" > "$T/dl/t33a_boot.sh"; echo old > "$T/dl/t33a_status.sh"
run t33a_sync_dl "$T/dl" "$T/log"
same_all && pass "없음·0바이트·잘림·옛 버전 4종 모두 레포 내용으로" || fail "맞추기 후 불일치"
[ "$(grep -c '레포 사본으로 교체' "$T/log")" = 5 ] && pass "교체 로그 5줄" || fail "교체 로그 $(grep -c '레포 사본으로 교체' "$T/log")줄"
[ -x "$T/dl/t33a_relay.sh" ] && [ ! -x "$T/dl/T33A_status_wrapper" ] && pass ".sh 만 실행 권한" || fail "실행 권한"

# 2. 이미 같으면 손대지 않음(같은 inode·로그 없음)
i=$(inode "$T/dl/t33a_relay.sh"); : > "$T/log"; run t33a_sync_dl "$T/dl" "$T/log"
[ "$(inode "$T/dl/t33a_relay.sh")" = "$i" ] && [ ! -s "$T/log" ] && pass "같으면 그대로(쓰기·로그 없음)" || fail "같은데 건드림"

# 3. 교체는 새 inode(mv) — 실행 중인 relay 가 읽는 파일을 제자리에서 덮지 않는다
echo stale > "$T/dl/t33a_relay.sh"; i=$(inode "$T/dl/t33a_relay.sh"); run t33a_sync_dl "$T/dl" "$T/log"
[ "$(inode "$T/dl/t33a_relay.sh")" != "$i" ] && pass "교체는 mv(새 inode)" || fail "제자리 덮어쓰기"

# 4. 레포 사본 없음·0바이트 → 대상 그대로, 반환 2, 같은 셸에서 두 번 돌려도 경고 1줄
fresh; rm "$T/repo/t33a_start.sh"; : > "$T/repo/t33a_status.sh"; echo keep > "$T/dl/t33a_status.sh"
run bash -c ". '$LIB'; t33a_sync_dl '$T/dl' '$T/log'; t33a_sync_dl '$T/dl' '$T/log'"
[ "$(cat "$T/dl/t33a_status.sh")" = keep ] && [ ! -e "$T/dl/t33a_start.sh" ] && pass "레포 사본 없음·빈 파일이면 대상 보존" || fail "대상 변경됨"
[ "$(grep -c 't33a_start.sh 맞추기 못함 — 레포 사본 없음' "$T/log")" = 1 ] && [ "$(grep -c 't33a_status.sh 맞추기 못함' "$T/log")" = 1 ] \
  && pass "실패 경고는 파일당 1회(두 번 실행)" || fail "경고 횟수 $(grep -c '맞추기 못함' "$T/log")"
run t33a_install "$T/repo/t33a_status.sh" "$T/dl/t33a_status.sh"; [ $? = 2 ] && pass "0바이트 레포 사본 → 반환 2" || fail "0바이트 레포 판정"

# 5. 복사 실패(cp 실패·잘린 복사) → 대상 그대로, 임시 파일 없음, 반환 3. 회복되면 교체 로그
for mode in fail trunc; do
  fresh; echo old > "$T/dl/t33a_relay.sh"; mkdir -p "$T/fbin"
  if [ $mode = fail ]; then printf '#!/bin/bash\nexit 1\n' > "$T/fbin/cp"
  else printf '#!/bin/bash\nhead -c 10 "$1" > "$2"\n' > "$T/fbin/cp"; fi
  chmod +x "$T/fbin/cp"
  ( export PATH="$T/fbin:$PATH" T33A_REPO_SCRIPTS="$T/repo"; . "$LIB"; t33a_install "$T/repo/t33a_relay.sh" "$T/dl/t33a_relay.sh"; echo $? > "$T/rc" )
  [ "$(cat "$T/rc")" = 3 ] && [ "$(cat "$T/dl/t33a_relay.sh")" = old ] && [ -z "$(ls -A "$T/dl" | grep sync)" ] \
    && pass "복사 실패($mode) → 반환 3·대상 보존·임시 파일 없음" || fail "복사 실패($mode): rc=$(cat "$T/rc") 대상=$(head -c 20 "$T/dl/t33a_relay.sh") 남은=$(ls -A "$T/dl" | tr '\n' ' ')"
done
( export T33A_REPO_SCRIPTS="$T/repo"; . "$LIB"
  PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log"; PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log"
  t33a_sync_dl "$T/dl" "$T/log"; PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log" )
[ "$(grep -c 't33a_relay.sh 맞추기 못함 — 복사 실패' "$T/log")" = 1 ] && same_all && pass "복사 실패 경고 1회 → 회복 후 교체" \
  || fail "회복 흐름: 경고 $(grep -c 't33a_relay.sh 맞추기 못함' "$T/log")"

# 6. 청소: .sync. 임시 파일만 지우고 비밀 conf·상태 파일은 보존
fresh; for x in .t33a_relay.sh.sync.1 .T33A_status_wrapper.sync.2 .T33A-status.sync.3 .t33a_telegram.conf .t33a_remote_state t33a_relay.sh; do : > "$T/dl/$x"; done
run t33a_sync_cleanup "$T/dl"
[ "$(ls -A "$T/dl" | tr '\n' ' ')" = ".t33a_remote_state .t33a_telegram.conf t33a_relay.sh " ] && pass "청소는 .sync. 임시 파일만" || fail "청소 후: $(ls -A "$T/dl" | tr '\n' ' ')"

# 7. start.sh 설치 구간 실행: 다운로드 폴더 boot.sh 가 0바이트여도 레포 사본으로 설치
H="$T/home"; rm -rf "$H"; mkdir -p "$H/t33a-remapper/scripts"; cp "$LIB" "$H/t33a-remapper/scripts/t33a_sync.sh"; echo "repo-boot" > "$H/t33a-remapper/scripts/t33a_boot.sh"
blk=$(sed -n '/^# 레포 사본에서 원자 설치/,/^true$/p' "$ROOT/scripts/t33a_start.sh" | sed "s#/sdcard/Download#$T/dl#g")
[ -n "$blk" ] || fail "start.sh 설치 구간 추출 실패"
fresh; : > "$T/dl/t33a_boot.sh"; ( HOME="$H"; BOOT_DIR="$H/.termux/boot"; eval "$blk" )
[ "$(cat "$H/.termux/boot/t33a_boot.sh" 2>/dev/null)" = repo-boot ] && pass "start.sh: 0바이트 다운로드 사본 무시, 레포 사본 설치" || fail "start.sh 설치: [$(cat "$H/.termux/boot/t33a_boot.sh" 2>/dev/null)]"

# 8. update.sh [3] 구간 실행: 레포 5개를 다운로드 폴더로 맞춤
blk=$(sed -n '/^# \[3\] 스크립트 변경 시/,/^# \[3.5\]/p' "$ROOT/scripts/t33a_update.sh")
fresh; cp "$LIB" "$T/repo/t33a_sync.sh"; mkdir -p "$T/urepo"; ln -s "$T/repo" "$T/urepo/scripts"
( REPO="$T/urepo"; SCRIPTS_DST="$T/dl"; LOG="$T/log"; CHANGED_SCRIPTS=1; log() { :; }; eval "$blk" )
same_all && pass "update.sh: 스크립트 5개를 레포와 같게" || fail "update.sh 구간 후 불일치"

echo "fails=$fails"; exit $fails
