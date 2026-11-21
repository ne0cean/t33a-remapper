# t33a_sync.sh — 레포 사본을 실행 위치로 맞추는 단일 복사기. boot.sh·update.sh·start.sh 가 source 한다.
# 규칙 하나: 실행 위치의 파일은 레포 사본과 바이트 단위로 같아야 한다. 다르면(없음·0바이트·잘림·옛 버전) 교체한다.
# 교체는 같은 폴더 임시 파일 → cmp 대조 → mv. 중간에 끊겨도 잘린 파일이 실행 위치에 남지 않고,
# mv 는 새 inode 라 이미 그 파일을 실행 중인 bash(relay 등)는 옛 내용을 계속 읽는다(제자리 cp 는 실행 중 스크립트를 깨뜨린다).
# 배경: 2026-11-14 다운로드 폴더 정리로 사본이 지워져 11-21 재부팅 뒤 복구 불가 → PR #7.
#   처음엔 "없으면 채우기"로 고쳤으나 -f/-s 판정이 세 곳에 흩어져 잘린 사본·빈 사본 틈이 거듭 나왔다(리뷰 3라운드) → 이 규칙으로 통합.
# 주의: 다운로드 폴더 사본을 손으로 고쳐도 레포와 다르면 되돌아간다 — 배포는 git push(auto_pull) 하나로.

T33A_REPO_SCRIPTS="${T33A_REPO_SCRIPTS:-$HOME/t33a-remapper/scripts}"
T33A_DL_FILES="t33a_boot.sh t33a_relay.sh t33a_start.sh t33a_status.sh T33A_status_wrapper"

_t33a_exec() { case "$1" in *.sh|*/T33A|*/T33A-status) return 0 ;; esac; return 1; }   # 실행 권한이 필요한 대상

# t33a_install <원본> <대상> → 0: 같음(손 안 댐) · 1: 교체함 · 2: 원본 없음/0바이트 · 3: 복사 실패(대상은 그대로)
# 주의: 성공(교체)도 0 이 아니다 — set -e 인 곳에서 단독으로 부르면 거기서 끝난다. 반환을 볼 게 아니면 `|| :` 로 부를 것.
t33a_install() {
    local src="$1" dst="$2" tmp
    [ -s "$src" ] || return 2
    if cmp -s "$src" "$dst" 2>/dev/null; then
        # 내용이 같아도 실행 권한은 확인 — 앞선 chmod 실패·mv 와 chmod 사이 kill 로 644 에 머무르지 않게
        _t33a_exec "$dst" && [ ! -x "$dst" ] && chmod +x "$dst" 2>/dev/null
        return 0
    fi
    tmp="$(dirname "$dst")/.$(basename "$dst").sync.$$"
    if cp "$src" "$tmp" 2>/dev/null && cmp -s "$src" "$tmp" && mv -f "$tmp" "$dst" 2>/dev/null; then
        _t33a_exec "$dst" && chmod +x "$dst" 2>/dev/null
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
        rc=0; t33a_install "$T33A_REPO_SCRIPTS/$f" "$dl/$f" || rc=$?   # || 로 받아야 set -e 인 호출부(setup_phone.sh)가 "교체함(1)"에서 끊기지 않는다
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

# t33a_sync_cleanup <폴더>... — 끊긴 교체가 남긴 임시 파일 청소(시작 때 한 번, 다른 교체가 돌지 않을 때).
# 다운로드 폴더·~/.termux/boot·~/.shortcuts 모두 t33a_install 의 대상이라 셋 다 넘긴다. 이름이 우리 것(.t33a_*·.T33A*)인 .sync. 만 지운다.
# 1분 넘은 것만 지운다 — 같은 순간 update.sh·start.sh 가 교체 중인 임시 파일(수 ms 수명)을 건드리지 않게.
# (지워 버려도 그쪽 t33a_install 이 cmp/mv 실패로 반환 3 → 다음 틱에 다시 맞추지만, 처음부터 피한다)
t33a_sync_cleanup() {
    local d
    for d in "$@"; do
        [ -d "$d" ] || continue
        find "$d" -maxdepth 1 -type f \( -name '.t33a_*.sync.*' -o -name '.T33A_*.sync.*' -o -name '.T33A.sync.*' -o -name '.T33A-status.sync.*' \) \
            -mmin +1 -exec rm -f {} + 2>/dev/null
    done
}
