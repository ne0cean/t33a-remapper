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
  else printf '#!/bin/bash\necho "$2" >> %s/cpdst\nhead -c 10 "$1" > "$2"\n' "$T" > "$T/fbin/cp"; fi
  chmod +x "$T/fbin/cp"
  ( export PATH="$T/fbin:$PATH" T33A_REPO_SCRIPTS="$T/repo"; . "$LIB"; t33a_install "$T/repo/t33a_relay.sh" "$T/dl/t33a_relay.sh"; echo $? > "$T/rc" )
  [ "$(cat "$T/rc")" = 3 ] && [ "$(cat "$T/dl/t33a_relay.sh")" = old ] && [ -z "$(ls -A "$T/dl" | grep sync)" ] \
    && pass "복사 실패($mode) → 반환 3·대상 보존·임시 파일 없음" || fail "복사 실패($mode): rc=$(cat "$T/rc") 대상=$(head -c 20 "$T/dl/t33a_relay.sh") 남은=$(ls -A "$T/dl" | tr '\n' ' ')"
done
[ "$(dirname "$(head -1 "$T/cpdst")")" = "$T/dl" ] && pass "임시 파일은 대상과 같은 폴더(mv 가 같은 파일시스템 안 교체)" || fail "임시 파일 위치: $(head -1 "$T/cpdst")"
( export T33A_REPO_SCRIPTS="$T/repo"; . "$LIB"
  PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log"; PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log"
  t33a_sync_dl "$T/dl" "$T/log"; PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log" )
[ "$(grep -c 't33a_relay.sh 맞추기 못함 — 복사 실패' "$T/log")" = 1 ] && same_all && pass "복사 실패 경고 1회 → 회복 후 교체" \
  || fail "회복 흐름: 경고 $(grep -c 't33a_relay.sh 맞추기 못함' "$T/log")"

# 6. 청소: .sync. 임시 파일만 지우고 비밀 conf·상태 파일은 보존
fresh; for x in .t33a_relay.sh.sync.1 .T33A_status_wrapper.sync.2 .T33A-status.sync.3 .t33a_telegram.conf .t33a_remote_state t33a_relay.sh; do : > "$T/dl/$x"; done
touch -t 202001010000 "$T/dl/".*.sync.* "$T/dl/.t33a_telegram.conf"; : > "$T/dl/.t33a_start.sh.sync.5"   # 마지막 것은 방금 생긴(교체 중인) 임시 파일
run t33a_sync_cleanup "$T/dl"
[ "$(ls -A "$T/dl" | tr '\n' ' ')" = ".t33a_remote_state .t33a_start.sh.sync.5 .t33a_telegram.conf t33a_relay.sh " ] && pass "청소는 1분 넘은 우리 .sync. 임시 파일만(교체 중인 새 임시 파일·비밀 conf 보존)" || fail "청소 후: $(ls -A "$T/dl" | tr '\n' ' ')"

# 7. start.sh 설치 구간 실행: 다운로드 폴더 boot.sh 가 0바이트여도 레포 사본으로 설치
H="$T/home"; rm -rf "$H"; mkdir -p "$H/t33a-remapper/scripts"; cp "$LIB" "$H/t33a-remapper/scripts/t33a_sync.sh"; echo "repo-boot" > "$H/t33a-remapper/scripts/t33a_boot.sh"
blk=$(sed -n '/^# 레포 사본에서 원자 설치/,/^true$/p' "$ROOT/scripts/t33a_start.sh" | sed "s#/sdcard/Download#$T/dl#g")
[ -n "$blk" ] || fail "start.sh 설치 구간 추출 실패"
fresh; : > "$T/dl/t33a_boot.sh"; mkdir -p "$H/.termux/boot"; echo old-boot > "$H/.termux/boot/t33a_boot.sh"; i=$(inode "$H/.termux/boot/t33a_boot.sh")
( HOME="$H"; BOOT_DIR="$H/.termux/boot"; eval "$blk" )
[ "$(cat "$H/.termux/boot/t33a_boot.sh" 2>/dev/null)" = repo-boot ] && pass "start.sh: 0바이트 다운로드 사본 무시, 레포 사본 설치" || fail "start.sh 설치: [$(cat "$H/.termux/boot/t33a_boot.sh" 2>/dev/null)]"
[ "$(inode "$H/.termux/boot/t33a_boot.sh")" != "$i" ] && [ -x "$H/.termux/boot/t33a_boot.sh" ] && pass "start.sh: 부팅 사본 원자 교체(새 inode)·실행 권한" || fail "start.sh: 제자리 덮어쓰기"
rm -rf "$H/t33a-remapper"; echo keep-boot > "$H/.termux/boot/t33a_boot.sh"; ( HOME="$H"; BOOT_DIR="$H/.termux/boot"; eval "$blk" )
[ "$(cat "$H/.termux/boot/t33a_boot.sh")" = keep-boot ] && pass "start.sh 레포 없음 폴백: 0바이트 다운로드 사본이 부팅 사본을 덮지 않음" || fail "start.sh 폴백: [$(cat "$H/.termux/boot/t33a_boot.sh")]"

# 8. update.sh [3] 구간 실행: 레포 5개를 다운로드 폴더로 맞춤
blk=$(sed -n '/^# \[3\] 스크립트 변경 시/,/^# \[3.5\]/p' "$ROOT/scripts/t33a_update.sh")
fresh; cp "$LIB" "$T/repo/t33a_sync.sh"; mkdir -p "$T/urepo"; ln -s "$T/repo" "$T/urepo/scripts"
( REPO="$T/urepo"; SCRIPTS_DST="$T/dl"; LOG="$T/log"; CHANGED_SCRIPTS=1; log() { :; }; eval "$blk" )
same_all && pass "update.sh: 스크립트 5개를 레포와 같게" || fail "update.sh 구간 후 불일치"

# 9. 경고 재무장: 실패 경고 → 성공(교체) → 다시 실패면 경고가 또 남는다(조용히 묻히지 않음)
fresh; printf '#!/bin/bash\nexit 1\n' > "$T/fbin/cp"; chmod +x "$T/fbin/cp"
( export T33A_REPO_SCRIPTS="$T/repo"; . "$LIB"
  PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log"
  t33a_sync_dl "$T/dl" "$T/log"; echo stale > "$T/dl/t33a_relay.sh"
  PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log" )
[ "$(grep -c 't33a_relay.sh 맞추기 못함 — 복사 실패' "$T/log")" = 2 ] && pass "성공 뒤 다시 실패하면 경고 재발(재무장)" \
  || fail "재무장: 경고 $(grep -c 't33a_relay.sh 맞추기 못함' "$T/log")"
fresh; : > "$T/log"
( export T33A_REPO_SCRIPTS="$T/repo"; . "$LIB"
  PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log"
  cp "$T/repo/t33a_relay.sh" "$T/dl/t33a_relay.sh"; PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log"   # 다른 경로로 같아짐 → 반환 0
  echo stale > "$T/dl/t33a_relay.sh"; PATH="$T/fbin:$PATH" t33a_sync_dl "$T/dl" "$T/log" )
[ "$(grep -c 't33a_relay.sh 맞추기 못함 — 복사 실패' "$T/log")" = 2 ] && pass "밖에서 같아진 뒤 다시 실패해도 경고 재발" \
  || fail "같음(0) 재무장: 경고 $(grep -c 't33a_relay.sh 맞추기 못함' "$T/log")"
fresh; rm "$T/repo/t33a_start.sh"
( export T33A_REPO_SCRIPTS="$T/repo"; . "$LIB"; t33a_sync_dl "$T/dl" "$T/log"
  echo "repo:t33a_start.sh" > "$T/repo/t33a_start.sh"; t33a_sync_dl "$T/dl" "$T/log"
  rm "$T/repo/t33a_start.sh"; t33a_sync_dl "$T/dl" "$T/log" )
[ "$(grep -c 't33a_start.sh 맞추기 못함 — 레포 사본 없음' "$T/log")" = 2 ] && pass "레포 사본 없음 경고도 재무장" \
  || fail "레포 없음 재무장: $(grep -c 't33a_start.sh 맞추기 못함' "$T/log")"

# 10. 내용이 같아도 실행 권한이 빠져 있으면 채운다(앞선 chmod 실패·kill 뒤 644 고착 방지)
fresh; cp "$T/repo/t33a_relay.sh" "$T/dl/t33a_relay.sh"; chmod 644 "$T/dl/t33a_relay.sh"
run t33a_install "$T/repo/t33a_relay.sh" "$T/dl/t33a_relay.sh"; rc=$?
[ $rc = 0 ] && [ -x "$T/dl/t33a_relay.sh" ] && pass "같은 내용·644 → 반환 0 + 실행 권한 복원" || fail "644 고착: rc=$rc"

# 11. 청소는 넘긴 폴더 모두(다운로드·부팅·위젯 폴더)
for d in a b c; do mkdir -p "$T/c$d"; : > "$T/c$d/.t33a_boot.sh.sync.7"; : > "$T/c$d/.T33A.sync.8"; : > "$T/c$d/keep"; done
touch -t 202001010000 "$T"/c?/.*.sync.*
run t33a_sync_cleanup "$T/ca" "$T/cb" "$T/cc"
[ "$(ls -A "$T/ca" "$T/cb" "$T/cc" | grep -c sync)" = 0 ] && [ "$(ls "$T"/c?/keep | wc -l | tr -d ' ')" = 3 ] && pass "청소는 넘긴 세 폴더 모두" || fail "다중 폴더 청소"

# 12. update.sh [3.5] 구간 실행: 부팅 사본을 레포 사본으로 원자 교체(새 inode). 프로세스 명령은 가짜(아무것도 죽이지 않음)
blk=$(sed -n '/^# \[3.5\] boot.sh 즉시 활성화/,/^# \[3.7\]/p' "$ROOT/scripts/t33a_update.sh" | sed "s#/sdcard/Download#$T/dl#g")
[ -n "$blk" ] || fail "update.sh [3.5] 추출 실패"
fresh; H="$T/uhome"; rm -rf "$H"; mkdir -p "$H/.termux/boot" "$T/pbin"; echo old-boot > "$H/.termux/boot/t33a_boot.sh"
for c in pgrep pkill nohup sleep; do printf '#!/bin/bash\nexit 0\n' > "$T/pbin/$c"; done; chmod +x "$T/pbin/"*
for c in pgrep pkill nohup; do [ "$(PATH="$T/pbin:$PATH" command -v $c)" = "$T/pbin/$c" ] || { echo "ABORT: 가짜 $c 가 잡히지 않음 — 실제 프로세스를 건드릴 수 있어 중단"; exit 2; }; done
i=$(inode "$H/.termux/boot/t33a_boot.sh")
( export PATH="$T/pbin:$PATH" T33A_REPO_SCRIPTS="$T/repo"; . "$LIB"; HOME="$H"; REPO="$T/urepo"; CHANGED_SCRIPTS=1; log() { :; }; eval "$blk" ) 2>/dev/null
cmp -s "$H/.termux/boot/t33a_boot.sh" "$T/repo/t33a_boot.sh" && [ "$(inode "$H/.termux/boot/t33a_boot.sh")" != "$i" ] && [ -x "$H/.termux/boot/t33a_boot.sh" ] \
  && pass "update.sh [3.5]: 부팅 사본을 레포 사본으로 원자 교체" || fail "update.sh [3.5]: [$(head -c 20 "$H/.termux/boot/t33a_boot.sh")]"

# 13. setup_phone.sh 의 사본 쓰기 구간 실행(네 번째 쓰는 곳 — 같은 복사기를 써야 한다)
fresh; H="$T/shome"; rm -rf "$H"; mkdir -p "$H/.termux/boot"; echo old-boot > "$H/.termux/boot/t33a_boot.sh"; i=$(inode "$H/.termux/boot/t33a_boot.sh")
cp "$LIB" "$T/repo/t33a_sync.sh"
blk=$( { sed -n '/^# boot.sh를 Termux:Boot에 등록/,/Termux:Boot 등록 완료"/p' "$ROOT/scripts/t33a_setup_phone.sh"; grep '^t33a_sync_dl /sdcard/Download' "$ROOT/scripts/t33a_setup_phone.sh"; } | sed "s#/sdcard/Download#$T/dl#g")
[ "$(printf '%s\n' "$blk" | grep -c 't33a_')" -ge 3 ] || fail "setup_phone.sh 구간 추출 실패"
# setup_phone.sh 는 9행이 set -e — 원본처럼 set -e 아래에서 돌리고, 교체가 일어나는 첫 설치가 구간 끝까지 가는지 본다
grep -q '^set -e' "$ROOT/scripts/t33a_setup_phone.sh" || fail "setup_phone.sh 의 set -e 가 사라짐(시험 전제 확인)"
( set -e; REPO="$T/urepo"; BOOT_DIR="$H/.termux/boot"; eval "$blk"; echo REACHED_END ) > "$T/setup_out" 2>&1
grep -q REACHED_END "$T/setup_out" && grep -q 'Termux:Boot 등록 완료' "$T/setup_out" && pass "setup_phone.sh: set -e 아래 첫 설치(교체 발생)가 끝까지 감" \
  || fail "setup_phone.sh: set -e 에서 중간 종료 — 출력[$(tr '\n' '|' < "$T/setup_out")]"
same_all && cmp -s "$H/.termux/boot/t33a_boot.sh" "$T/repo/t33a_boot.sh" && [ "$(inode "$H/.termux/boot/t33a_boot.sh")" != "$i" ] \
  && pass "setup_phone.sh: 다운로드 5개·부팅 사본을 레포와 같게(원자 교체)" || fail "setup_phone.sh 구간 후 불일치"

echo "fails=$fails"; exit $fails
