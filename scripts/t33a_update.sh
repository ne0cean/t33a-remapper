#!/data/data/com.termux/files/usr/bin/bash
# T33A 폰-내 업데이트 — USB 없이 배포
# Mac에서 git push → 폰 Termux에서 이 스크립트 실행 (또는 T33A_Update 위젯)
# 동작: git pull → 변경 감지 → 필요 시 clang 빌드 → relay 통해 재시작

REPO="$HOME/t33a-remapper"
BIN_DST="/data/local/tmp/t33a_remap"
BIN_SDCARD="/sdcard/Download/t33a_remap"
SCRIPTS_DST="/sdcard/Download"
CMD="/sdcard/Download/t33a.cmd"
LOG="/sdcard/Download/t33a_update.log"

log() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

log "=== t33a update started ==="

# [1] git pull
if [ ! -d "$REPO/.git" ]; then
    log "ERROR: 레포 없음 — setup_phone.sh 먼저 실행해야 함: $REPO"
    exit 1
fi
cd "$REPO"

BEFORE=$(git rev-parse HEAD 2>/dev/null)
git fetch origin main 2>&1 | tee -a "$LOG"
REMOTE=$(git rev-parse origin/main 2>/dev/null)

if [ "$BEFORE" = "$REMOTE" ]; then
    log "이미 최신 ($BEFORE) — 강제 재시작만"
    CHANGED_SRC=0
    CHANGED_SCRIPTS=1   # 재시작은 항상
else
    git reset --hard origin/main 2>&1 | tee -a "$LOG"
    AFTER=$(git rev-parse HEAD)
    log "업데이트: $BEFORE → $AFTER"

    # 변경된 파일 확인
    CHANGED_SRC=$(git diff --name-only "$BEFORE" "$AFTER" 2>/dev/null | grep -c 'src/' || true)
    CHANGED_SCRIPTS=$(git diff --name-only "$BEFORE" "$AFTER" 2>/dev/null | grep -c 'scripts/' || true)
    log "변경: src=${CHANGED_SRC} scripts=${CHANGED_SCRIPTS}"
fi

# [2] C 소스 변경 시 빌드
if [ "$CHANGED_SRC" -gt 0 ]; then
    log "빌드 시작 (clang)..."
    if ! command -v clang > /dev/null 2>&1; then
        log "ERROR: clang 없음 — pkg install clang 필요"
        exit 1
    fi

    # 실행 중인 데몬 정지 (text file busy 방지)
    pkill -x t33a_remap 2>/dev/null || true
    sleep 1

    clang -O2 -o "$BIN_DST" "$REPO/src/t33a_remap.c" 2>&1 | tee -a "$LOG"
    chmod +x "$BIN_DST"
    cp "$BIN_DST" "$BIN_SDCARD"
    log "빌드 완료: $(ls -lh "$BIN_DST" | awk '{print $5}')"
fi

# [3] 스크립트 변경 시 /sdcard/Download로 복사
if [ "$CHANGED_SCRIPTS" -gt 0 ]; then
    for f in boot relay start; do
        src="$REPO/scripts/t33a_${f}.sh"
        dst="$SCRIPTS_DST/t33a_${f}.sh"
        [ -f "$src" ] && cp "$src" "$dst" && chmod +x "$dst"
    done
    log "스크립트 갱신: boot/relay/start"
fi

# [3.5] boot.sh 즉시 활성화 — $BOOT_DIR 설치 + watchdog 재시작
# (기존엔 boot.sh 자체설치가 다음 부팅에야 실행 → 새 로직이 한 부팅 늦게 적용되는 결함)
if [ "$CHANGED_SCRIPTS" -gt 0 ]; then
    BOOT_DIR="$HOME/.termux/boot"
    mkdir -p "$BOOT_DIR"
    cp "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"
    chmod +x "$BOOT_DIR/t33a_boot.sh"
    OLD_BOOT=$(pgrep -f "t33a_boot.sh" 2>/dev/null | head -1)
    if [ -n "$OLD_BOOT" ]; then
        kill "$OLD_BOOT" 2>/dev/null
        sleep 1
    fi
    nohup bash "$BOOT_DIR/t33a_boot.sh" < /dev/null >> /sdcard/Download/t33a_boot.log 2>&1 &
    log "boot.sh 재설치 + watchdog 재시작 (PID $!)"
fi

# [4] relay 통해 데몬 재시작
log "데몬 재시작 (relay cmd)..."
echo "update" > "$CMD"
sleep 4

STATUS=$(cat /data/local/tmp/t33a.status 2>/dev/null || echo "unknown")
HB_AGE="?"
if [ -f /data/local/tmp/t33a.heartbeat ]; then
    MTIME=$(stat -c %Y /data/local/tmp/t33a.heartbeat 2>/dev/null || echo 0)
    HB_AGE=$(( $(date +%s) - MTIME ))
fi

log "완료! daemon=${STATUS} heartbeat=${HB_AGE}s ago"
echo ""
echo "상태: daemon=${STATUS}  heartbeat age=${HB_AGE}s"
