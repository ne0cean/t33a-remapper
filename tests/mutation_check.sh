#!/bin/bash
# mutation_check.sh — 레포 사본 맞추기(t33a_sync.sh)와 그 배선을 한 줄씩 망가뜨려 sync_test·boot_sync_e2e_test 가 잡는지 확인한다.
# 레포를 임시 폴더에 복제해서 망가뜨린다(작업 트리는 건드리지 않음). 생존 변이가 하나라도 있으면 종료 코드 1.
# 사용: bash tests/mutation_check.sh   (약 2~4분)
W="$(cd "$(dirname "$0")/.." && pwd)"
M=$(mktemp -d) && [ -n "$M" ] && [ -d "$M" ] || { echo "ABORT: 임시 폴더 생성 실패"; exit 2; }
trap 'rm -rf "$M"' EXIT
survived=0; total=0
mut() {  # mut <이름> <파일> <원문> <바꿀 글>
  total=$((total+1)); rm -rf "$M/w"; mkdir -p "$M/w"; cp -R "$W/scripts" "$W/tests" "$M/w/"
  python3 -c "
import sys;p,o,n=sys.argv[1:4];s=open(p).read()
assert o in s, 'NOMATCH'
open(p,'w').write(s.replace(o,n,1))" "$M/w/$2" "$3" "$4" 2>/dev/null || { echo "?? $1 (원문 없음 — 변이표 갱신 필요)"; survived=$((survived+1)); return; }
  a=$(bash "$M/w/tests/sync_test.sh" 2>/dev/null | tail -1); b=$(bash "$M/w/tests/boot_sync_e2e_test.sh" 2>/dev/null | tail -1)
  case "$a$b" in *"fails=0"*"fails=0"*) echo "SURVIVED $1"; survived=$((survived+1));; *) echo "killed   $1 (sync:$a e2e:$b)";; esac
}
B=scripts/t33a_boot.sh; S=scripts/t33a_sync.sh; U=scripts/t33a_update.sh
mut "boot: 시작 맞추기 제거"          $B '    sync_scripts                  # 위 줄이' '    :                  # 위 줄이'
mut "boot: 시작 맞추기를 relay 뒤로"  $B '    sync_scripts                  # 위 줄이' '    sleep 15; sync_scripts                  # 위 줄이'
mut "boot: 틱 맞추기 제거"            $B '    sync_scripts   # relay 가' '    :   # relay 가'
mut "boot: 부팅 사본을 다운로드에서"  $B 't33a_install "$REPO_SCRIPTS/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' 'cp "$SRC" "$BOOT_DIR/t33a_boot.sh"'
mut "boot: 부팅 사본 제자리 cp"       $B 't33a_install "$REPO_SCRIPTS/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' 'cp "$REPO_SCRIPTS/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"'
mut "boot: 상태 위젯을 다운로드에서"  $B 't33a_install "$REPO_SCRIPTS/T33A_status_wrapper" "$SHORTCUT_DIR/T33A-status"' 'cp "$STATUS_WRAPPER" "$SHORTCUT_DIR/T33A-status"'
mut "boot: 복구 위젯 무조건 cp"       $B '    t33a_install "$WRAPPER" "$SHORTCUT_DIR/T33A"' '    cp "$WRAPPER" "$SHORTCUT_DIR/T33A"'
mut "boot: 청소 제거"                 $B '    t33a_sync_cleanup "$DL_DIR" "$BOOT_DIR" "$SHORTCUT_DIR"' '    :'
mut "boot: 청소를 다운로드만"         $B '    t33a_sync_cleanup "$DL_DIR" "$BOOT_DIR" "$SHORTCUT_DIR"' '    t33a_sync_cleanup "$DL_DIR"'
mut "sync: 레포 판정 -s→-f"           $S '[ -s "$src" ] || return 2' '[ -f "$src" ] || return 2'
mut "sync: 같음 검사 제거"            $S '    if cmp -s "$src" "$dst" 2>/dev/null; then' '    if false; then'
mut "sync: 같을 때 chmod 생략"        $S '        _t33a_exec "$dst" && [ ! -x "$dst" ] && chmod +x "$dst" 2>/dev/null' '        :'
mut "sync: 임시 파일 대조 제거"       $S 'cp "$src" "$tmp" 2>/dev/null && cmp -s "$src" "$tmp" && mv' 'cp "$src" "$tmp" 2>/dev/null && mv'
mut "sync: mv→제자리 cp"              $S 'mv -f "$tmp" "$dst" 2>/dev/null' 'cp "$tmp" "$dst" 2>/dev/null && rm -f "$tmp"'
mut "sync: 실패 시 임시 파일 남김"    $S '    rm -f "$tmp" 2>/dev/null
    return 3' '    return 3'
mut "sync: 경고 1회 기억 제거"        $S '_T33A_SYNC_WARNED="$_T33A_SYNC_WARNED$key "' ':'
mut "sync: 성공 시 재무장 제거"       $S '            0) _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:2 / }"; _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:3 / }" ;;' '            0) ;;'
mut "sync: 교체 시 재무장 제거"       $S '               _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:2 / }"; _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:3 / }" ;;' '               ;;'
mut "sync: 청소 glob 넓힘"            $S 'rm -f "$d"/.t33a_*.sync.*' 'rm -f "$d"/.t33a_*'
mut "sync: 청소가 첫 폴더만"          $S '    for d in "$@"; do' '    for d in "$1"; do'
mut "start: 다운로드에서 설치"        scripts/t33a_start.sh 't33a_install "$HOME/t33a-remapper/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' 'cp /sdcard/Download/t33a_boot.sh "$BOOT_DIR/t33a_boot.sh"'
mut "update: 레포 위치 미전달"        $U 'T33A_REPO_SCRIPTS="$REPO/scripts"; ' ''
mut "update: 맞추기 제거"             $U '    t33a_sync_dl "$SCRIPTS_DST" "$LOG"' '    :'
mut "update: [3.5] 부팅 사본 설치 제거" $U '    t33a_install "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' '    :'
mut "update: [3.5] 제자리 cp"         $U '    t33a_install "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' '    cp "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"'
# 리뷰어(e31a113 재설계 리뷰) 추가 변이 중 현재 코드에 해당하는 것
mut "sync: 상태 위젯 실행 권한 누락"  $S '*.sh|*/T33A|*/T33A-status) return 0' '*.sh|*/T33A) return 0'
mut "sync: 임시 파일을 TMPDIR 에"     $S 'tmp="$(dirname "$dst")/.$(basename "$dst").sync.$$"' 'tmp="${TMPDIR:-/tmp}/.$(basename "$dst").sync.$$"'
mut "boot: 폴백 -s→-f"                $B '    [ -s "$SRC" ] && cp "$SRC"' '    [ -f "$SRC" ] && cp "$SRC"'
mut "boot: 맞추기 생략 로그 제거"     $B '    echo "$(date): $REPO_SCRIPTS/t33a_sync.sh 없음' '    : "$(date): $REPO_SCRIPTS/t33a_sync.sh 없음'
mut "start: 폴백 -s→-f"               scripts/t33a_start.sh 'elif [ -s /sdcard/Download/t33a_boot.sh ]' 'elif [ -f /sdcard/Download/t33a_boot.sh ]'
echo "변이 $total 종 중 생존 $survived"; [ $survived = 0 ]
