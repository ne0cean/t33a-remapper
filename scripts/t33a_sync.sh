# t33a_sync.sh — 레포 사본을 실행 위치로 맞추는 단일 복사기. boot.sh·update.sh·start.sh 가 source 한다.
# 규칙 하나: 실행 위치의 파일은 레포 사본과 바이트 단위로 같아야 한다. 다르면(없음·0바이트·잘림·옛 버전) 교체한다.
# 교체는 같은 폴더 임시 파일 → cmp 대조 → mv. 중간에 끊겨도 잘린 파일이 실행 위치에 남지 않고,
# mv 는 새 inode 라 이미 그 파일을 실행 중인 bash(relay 등)는 옛 내용을 계속 읽는다(제자리 cp 는 실행 중 스크립트를 깨뜨린다).
# 배경: 2026-11-14 다운로드 폴더 정리로 사본이 지워져 11-21 재부팅 뒤 복구 불가 → PR #7.
#   처음엔 "없으면 채우기"로 고쳤으나 -f/-s 판정이 세 곳에 흩어져 잘린 사본·빈 사본 틈이 거듭 나왔다(리뷰 3라운드) → 이 규칙으로 통합.
# 주의: 다운로드 폴더 사본을 손으로 고쳐도 레포와 다르면 되돌아간다 — 배포는 git push(auto_pull) 하나로.

T33A_REPO_SCRIPTS="${T33A_REPO_SCRIPTS:-$HOME/t33a-remapper/scripts}"
T33A_DL_FILES="t33a_boot.sh t33a_relay.sh t33a_start.sh t33a_status.sh T33A_status_wrapper"

# t33a_install <원본> <대상> → 0: 같음(손 안 댐) · 1: 교체함 · 2: 원본 없음/0바이트 · 3: 복사 실패(대상은 그대로)
t33a_install() {
    local src="$1" dst="$2" tmp
    [ -s "$src" ] || return 2
    cmp -s "$src" "$dst" 2>/dev/null && return 0
    tmp="$(dirname "$dst")/.$(basename "$dst").sync.$$"
    if cp "$src" "$tmp" 2>/dev/null && cmp -s "$src" "$tmp" && mv -f "$tmp" "$dst" 2>/dev/null; then
        case "$dst" in *.sh|*/T33A|*/T33A-status) chmod +x "$dst" 2>/dev/null ;; esac
        return 1
    fi
    rm -f "$tmp" 2>/dev/null
    return 3
}

# t33a_sync_dl <다운로드폴더> <로그> — 5개 사본을 레포에 맞춘다. 교체는 매번, 실패는 파일·사유당 한 번만 기록(15초 틱에 쌓이지 않게).
_T33A_SYNC_WARNED=" "
t33a_sync_dl() {
    local dl="$1" log="$2" f rc key
    for f in $T33A_DL_FILES; do
        t33a_install "$T33A_REPO_SCRIPTS/$f" "$dl/$f"; rc=$?
        key="$f:$rc"
        case $rc in
            0) _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:2 / }"; _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:3 / }" ;;
            1) echo "$(date): $f 다운로드 폴더 사본이 레포와 달라(없음·빈 파일·잘림·옛 버전) 레포 사본으로 교체" >> "$log"
               _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:2 / }"; _T33A_SYNC_WARNED="${_T33A_SYNC_WARNED/ $f:3 / }" ;;
            *) case "$_T33A_SYNC_WARNED" in *" $key "*) ;; *)
                   if [ $rc = 2 ]; then echo "$(date): $f 맞추기 못함 — 레포 사본 없음·빈 파일 ($T33A_REPO_SCRIPTS/$f)" >> "$log"
                   else echo "$(date): $f 맞추기 못함 — 복사 실패(쓰기 불가·용량·cmp 없음 등)" >> "$log"; fi
                   _T33A_SYNC_WARNED="$_T33A_SYNC_WARNED$key " ;;
               esac ;;
        esac
    done
}

# t33a_sync_cleanup <폴더> — 끊긴 교체가 남긴 임시 파일 청소(시작 때 한 번, 다른 교체가 돌지 않을 때)
t33a_sync_cleanup() { rm -f "$1"/.t33a_*.sync.* "$1"/.T33A_*.sync.* "$1"/.T33A.sync.* "$1"/.T33A-status.sync.* 2>/dev/null; }
