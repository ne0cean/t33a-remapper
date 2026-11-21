#!/bin/bash
# mutation_check.sh — 레포 사본 맞추기(t33a_sync.sh)와 그 배선을 한 줄씩 망가뜨려 sync_test·boot_sync_e2e_test 가 잡는지 확인한다.
# 레포를 임시 폴더에 복제해서 망가뜨린다(작업 트리는 건드리지 않음). 생존 변이가 하나라도 있으면 종료 코드 1.
# 사용: bash tests/mutation_check.sh   (약 2~4분)
W="$(cd "$(dirname "$0")/.." && pwd)"
M=$(mktemp -d) && [ -n "$M" ] && [ -d "$M" ] || { echo "ABORT: 임시 폴더 생성 실패"; exit 2; }
trap 'rm -rf "$M"' EXIT
survived=0; total=0
# 시험 한 쌍 실행 → "sync 실패수 e2e 실패수". 마지막 줄이 fails=N 이 아니면(ABORT·시간 초과·환경 오류) X 로 낸다
pair() {
  local a b
  a=$(bash "$1/tests/sync_test.sh" 2>/dev/null | tail -1); b=$(bash "$1/tests/boot_sync_e2e_test.sh" 2>/dev/null | tail -1)
  case "$a" in fails=[0-9]*) a=${a#fails=} ;; *) a=X ;; esac
  case "$b" in fails=[0-9]*) b=${b#fails=} ;; *) b=X ;; esac
  echo "$a $b"
}
# 기준: 변이 없는 복제본에서 두 시험이 끝까지 돌고 0건 실패여야 한다(아니면 "잡힘"이 환경 탓일 수 있어 판정 무효)
rm -rf "$M/w"; mkdir -p "$M/w"; cp -R "$W/scripts" "$W/tests" "$M/w/"
base=$(pair "$M/w"); [ "$base" = "0 0" ] || { echo "ABORT: 기준(무변이) 실행이 깨끗하지 않음 [sync e2e = $base] — 변이 판정 무효"; exit 2; }
echo "기준(무변이): sync 0 · e2e 0"
mut() {  # mut <파일> <원문> <바꿀 글> [<원문2> <바꿀 글2>] — 이름은 $NAME(m 이 넣음)
  total=$((total+1)); rm -rf "$M/w"; mkdir -p "$M/w"; cp -R "$W/scripts" "$W/tests" "$M/w/"
  local f="$M/w/$1" name="$NAME"; shift 1
  python3 -c "
import sys;p=sys.argv[1];s=open(p).read();a=sys.argv[2:]
for o,n in zip(a[0::2],a[1::2]):
    assert o in s, 'NOMATCH'
    s=s.replace(o,n,1)
open(p,'w').write(s)" "$f" "$@" 2>/dev/null || { echo "?? $name (원문 없음 — 변이표 갱신 필요)"; survived=$((survived+1)); return; }
  set -- $(pair "$M/w")
  if [ "$1" = X ] || [ "$2" = X ]; then echo "INVALID  $name (시험이 끝까지 돌지 않음: sync=$1 e2e=$2 — 잡힘으로 세지 않음)"; survived=$((survived+1))
  elif [ "$1" = 0 ] && [ "$2" = 0 ]; then echo "SURVIVED $name"; survived=$((survived+1))
  else echo "killed   $name (sync 실패 $1 · e2e 실패 $2)"; fi
}
m() { NAME="$1"; shift; mut "$@"; }
B=scripts/t33a_boot.sh; S=scripts/t33a_sync.sh; U=scripts/t33a_update.sh
m "boot: 시작 맞추기 제거"          $B '    sync_scripts                  # 위 줄이' '    :                  # 위 줄이'
m "boot: 시작 맞추기를 watchdog 직전으로" $B '    sync_scripts                  # 위 줄이' '    :                  # 위 줄이' 'while true; do
    sync_scripts   # relay 가' 'sync_scripts
while true; do
    sync_scripts   # relay 가'
m "boot: 시작 맞추기를 alive 분기 안으로만" $B '    sync_scripts                  # 위 줄이' '    :                  # 위 줄이' '    connect_adb && ensure_bluetooth_on' '    sync_scripts; connect_adb && ensure_bluetooth_on'
m "boot: 틱 맞추기 제거"            $B '    sync_scripts   # relay 가' '    :   # relay 가'
m "boot: 부팅 사본을 다운로드에서"  $B 't33a_install "$REPO_SCRIPTS/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' 'cp "$SRC" "$BOOT_DIR/t33a_boot.sh"'
m "boot: 부팅 사본 제자리 cp"       $B 't33a_install "$REPO_SCRIPTS/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' 'cp "$REPO_SCRIPTS/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"'
m "boot: 상태 위젯을 다운로드에서"  $B 't33a_install "$REPO_SCRIPTS/T33A_status_wrapper" "$SHORTCUT_DIR/T33A-status"' 'cp "$STATUS_WRAPPER" "$SHORTCUT_DIR/T33A-status"'
m "boot: 복구 위젯 무조건 cp"       $B '    t33a_install "$WRAPPER" "$SHORTCUT_DIR/T33A"' '    cp "$WRAPPER" "$SHORTCUT_DIR/T33A"'
m "boot: 청소 제거"                 $B '    t33a_sync_cleanup "$DL_DIR" "$BOOT_DIR" "$SHORTCUT_DIR"' '    :'
m "boot: 청소를 다운로드만"         $B '    t33a_sync_cleanup "$DL_DIR" "$BOOT_DIR" "$SHORTCUT_DIR"' '    t33a_sync_cleanup "$DL_DIR"'
m "sync: 레포 판정 -s→-f"           $S '[ -s "$src" ] || return 2' '[ -f "$src" ] || return 2'
m "sync: 같음 검사 제거"            $S '    if cmp -s "$src" "$dst" 2>/dev/null; then' '    if false; then'
m "sync: 같을 때 chmod 생략"        $S '        _t33a_exec "$dst" && [ ! -x "$dst" ] && chmod +x "$dst" 2>/dev/null' '        :'
m "sync: 임시 파일 대조 제거"       $S 'cp "$src" "$tmp" 2>/dev/null && cmp -s "$src" "$tmp" && mv' 'cp "$src" "$tmp" 2>/dev/null && mv'
m "sync: mv→제자리 cp"              $S 'mv -f "$tmp" "$dst" 2>/dev/null' 'cp "$tmp" "$dst" 2>/dev/null && rm -f "$tmp"'
m "sync: 실패 시 임시 파일 남김"    $S '    rm -f "$tmp" 2>/dev/null
    return 3' '    return 3'
m "sync: 경고 1회 기억 제거"        $S '_T33A_SYNC_WARNED="$_T33A_SYNC_WARNED$key "' ':'
m "sync: 성공 시 재무장 제거"       $S '            0) _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:2 / }"; _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:3 / }" ;;' '            0) ;;'
m "sync: 교체 시 재무장 제거"       $S '               _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:2 / }"; _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:3 / }" ;;' '               ;;'
m "sync: 청소 glob 넓힘(남의 숨김 임시 파일까지)" $S "-name '.t33a_*.sync.*'" "-name '.*.sync.*'"
m "sync: 청소 glob 넓힘(우리 접두어 전부)" $S "-name '.t33a_*.sync.*'" "-name '.t33a_*'"
m "sync: 청소 나이 조건 제거"        $S '-mmin +1 -exec' '-exec'
m "boot: 복구 위젯 설치 제거"        $B '    t33a_install "$WRAPPER" "$SHORTCUT_DIR/T33A"' '    :'
m "sync: 청소가 첫 폴더만"          $S '    for d in "$@"; do' '    for d in "$1"; do'
m "start: 다운로드에서 설치"        scripts/t33a_start.sh 't33a_install "$HOME/t33a-remapper/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' 'cp /sdcard/Download/t33a_boot.sh "$BOOT_DIR/t33a_boot.sh"'
m "update: 레포 위치 미전달"        $U 'T33A_REPO_SCRIPTS="$REPO/scripts"; ' ''
m "update: 맞추기 제거"             $U '    t33a_sync_dl "$SCRIPTS_DST" "$LOG"' '    :'
m "update: [3.5] 부팅 사본 설치 제거" $U '    t33a_install "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' '    :'
m "update: [3.5] 제자리 cp"         $U '    t33a_install "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' '    cp "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"'
# 리뷰어(e31a113 재설계 리뷰) 추가 변이 중 현재 코드에 해당하는 것
m "sync: 상태 위젯 실행 권한 누락"  $S '*.sh|*/T33A|*/T33A-status) return 0' '*.sh|*/T33A) return 0'
m "sync: 임시 파일을 TMPDIR 에"     $S 'tmp="$(dirname "$dst")/.$(basename "$dst").sync.$$"' 'tmp="${TMPDIR:-/tmp}/.$(basename "$dst").sync.$$"'
m "boot: 폴백 -s→-f"                $B '    [ -s "$SRC" ] && cp "$SRC"' '    [ -f "$SRC" ] && cp "$SRC"'
m "boot: 맞추기 생략 로그 제거"     $B '    echo "$(date): $REPO_SCRIPTS/t33a_sync.sh 없음' '    : "$(date): $REPO_SCRIPTS/t33a_sync.sh 없음'
m "start: 폴백 -s→-f"               scripts/t33a_start.sh 'elif [ -s /sdcard/Download/t33a_boot.sh ]' 'elif [ -f /sdcard/Download/t33a_boot.sh ]'
m "start: 부팅 사본 제자리 cp"       scripts/t33a_start.sh 't33a_install "$HOME/t33a-remapper/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' 'cp "$HOME/t33a-remapper/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"'
m "setup: 부팅 사본 제자리 cp"       scripts/t33a_setup_phone.sh 't33a_install "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"' 'cp "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"'
m "setup: 다운로드 맞추기 제거"      scripts/t33a_setup_phone.sh 't33a_sync_dl /sdcard/Download /sdcard/Download/t33a_boot.log' ':'
echo "변이 $total 종 중 생존·무효 $survived"; [ $survived = 0 ]
