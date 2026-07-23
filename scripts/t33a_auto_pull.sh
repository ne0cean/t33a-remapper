#!/data/data/com.termux/files/usr/bin/bash
# T33A Auto Pull — GitHub 변경 감지 → 자동 업데이트
# boot.sh에서 백그라운드로 상주
# 5분마다 git fetch로 새 커밋 확인 → 있으면 t33a_update.sh 실행

REPO="$HOME/t33a-remapper"
LOG="/sdcard/Download/t33a_boot.log"
LAST_COMMIT_FILE="/sdcard/Download/t33a_last_commit"
TRIGGER_FILE="/sdcard/Download/t33a_update.trigger"
# 배터리(2026-07-23): 트리거 폴링과 네트워크 fetch 분리.
#   배포는 트리거 파일로 ≤30s 반응(기존 ≤60s보다 개선), passive fetch는 30분 안전망.
#   기존 60s fetch = 하루 1440회 라디오 웨이크업 → 48회.
CHECK_INTERVAL=1800   # passive GitHub fetch (안전망)
TRIGGER_POLL=30       # Mac ADB 트리거 파일 감지

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') auto_pull: $*" >> "$LOG"; }

log "started (PID $$)"

# 네트워크 대기 (부팅 직후 WiFi 연결 전)
sleep 30

elapsed=$CHECK_INTERVAL   # 시작 직후 1회 fetch
while true; do
    if [ ! -d "$REPO/.git" ]; then
        log "레포 없음 — 대기 ($REPO)"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # Mac ADB 즉시 트리거 감지 (30s 주기)
    if [ -f "$TRIGGER_FILE" ]; then
        rm -f "$TRIGGER_FILE"
        log "즉시 트리거 감지 — 업데이트 시작"
        bash "$REPO/scripts/t33a_update.sh"
        REMOTE=$(git -C "$REPO" rev-parse HEAD 2>/dev/null)
        echo "$REMOTE" > "$LAST_COMMIT_FILE"
        log "업데이트 완료"
        elapsed=0
        sleep "$TRIGGER_POLL"
        continue
    fi

    # 주기적 fetch (CHECK_INTERVAL마다)
    if [ "$elapsed" -ge "$CHECK_INTERVAL" ]; then
        elapsed=0
        if timeout 30 git -C "$REPO" fetch origin main > /dev/null 2>&1; then
            LOCAL=$(git -C "$REPO" rev-parse HEAD 2>/dev/null)
            REMOTE=$(git -C "$REPO" rev-parse origin/main 2>/dev/null)
            LAST=$(cat "$LAST_COMMIT_FILE" 2>/dev/null || echo "")

            if [ "$LOCAL" != "$REMOTE" ] || [ "$LAST" != "$REMOTE" ]; then
                log "새 커밋 감지: local=$LOCAL remote=$REMOTE — 업데이트 시작"
                bash "$REPO/scripts/t33a_update.sh"
                echo "$REMOTE" > "$LAST_COMMIT_FILE"
                log "업데이트 완료"
            fi
        else
            log "fetch 실패 (네트워크 없음?)"
        fi
    fi

    sleep "$TRIGGER_POLL"
    elapsed=$((elapsed + TRIGGER_POLL))
done
