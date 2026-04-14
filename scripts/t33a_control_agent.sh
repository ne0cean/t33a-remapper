#!/data/data/com.termux/files/usr/bin/bash
# T33A Control Agent — Termux 유저 권한으로 임의 명령 실행 (Claude ADB 원격 제어용)
#
# 아키텍처:
#   Claude (ADB shell) → /sdcard/Download/t33a_ctrl.req (명령 작성)
#   Agent (Termux, u0_a533) → 1초 폴링 → 실행 → /sdcard/Download/t33a_ctrl.resp (결과 기록)
#   Claude → resp 파일 읽기 → 다음 명령
#
# 사용법:
#   1회 부트스트랩 (Termux에서 한 줄):
#     bash /data/local/tmp/t33a_control_agent.sh install
#
#   이후 Claude가 ADB로 원격 제어:
#     echo "<UUID>" > /sdcard/Download/t33a_ctrl.req
#     echo "<bash 명령>" >> /sdcard/Download/t33a_ctrl.req
#     # 기다림
#     cat /sdcard/Download/t33a_ctrl.resp

REQ=/sdcard/Download/t33a_ctrl.req
RESP=/sdcard/Download/t33a_ctrl.resp
LOG=/sdcard/Download/t33a_ctrl.log
PID_FILE=/sdcard/Download/t33a_ctrl.pid
SELF="/data/local/tmp/t33a_control_agent.sh"
BOOT_DIR="$HOME/.termux/boot"
BOOT_TARGET="$BOOT_DIR/t33a_control_agent.sh"
SHORTCUT_DIR="$HOME/.shortcuts"

mode="${1:-run}"

# ── 설치 모드: 자기 자신을 ~/.termux/boot/에 복사하고 백그라운드 실행 ──
if [ "$mode" = "install" ]; then
    echo "=== T33A Control Agent 설치 ==="
    mkdir -p "$BOOT_DIR" "$SHORTCUT_DIR"

    # 기존 agent가 돌고 있으면 kill
    if [ -f "$PID_FILE" ]; then
        OLD=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$OLD" ] && kill "$OLD" 2>/dev/null
        sleep 1
    fi

    # ~/.termux/boot/로 복사 (재부팅 자동 시작)
    cp "$SELF" "$BOOT_TARGET"
    chmod +x "$BOOT_TARGET"
    echo "✓ $BOOT_TARGET 설치 완료"

    # 수동 트리거 단축키도 만들기 (선택적, 디버깅용)
    cat > "$SHORTCUT_DIR/t33a_ctrl_restart" << 'SHORTCUT'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f 't33a_control_agent.sh run' 2>/dev/null
sleep 1
nohup bash /data/local/tmp/t33a_control_agent.sh run < /dev/null > /dev/null 2>&1 &
termux-toast "t33a_ctrl restarted"
SHORTCUT
    chmod +x "$SHORTCUT_DIR/t33a_ctrl_restart"
    echo "✓ ~/.shortcuts/t33a_ctrl_restart 설치 완료"

    # 지금 백그라운드로 실행
    nohup bash "$SELF" run < /dev/null > /dev/null 2>&1 &
    AGENT_PID=$!
    sleep 1
    echo "✓ Agent 실행 중 (PID $AGENT_PID)"
    echo ""
    echo "검증 (5초 내):"
    echo "  adb shell cat $LOG"
    exit 0
fi

# ── Run 모드: 폴링 루프 ──
# 중복 실행 방지
if [ -f "$PID_FILE" ]; then
    OLD=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
        echo "$(date): 이미 실행 중 (PID $OLD)" >> "$LOG"
        exit 0
    fi
fi
echo "$$" > "$PID_FILE"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') ctrl: $1" >> "$LOG"; }
log "started (PID $$, Termux uid=$(id -u))"

trap 'log "stopping (SIGTERM)"; exit 0' TERM
trap 'log "stopping (SIGINT)"; exit 0' INT

# 폴링 루프
while true; do
    if [ -f "$REQ" ]; then
        # 요청 읽기 (첫 줄 = request ID, 나머지 = 명령)
        REQ_ID=$(head -1 "$REQ" 2>/dev/null)
        CMD=$(tail -n +2 "$REQ" 2>/dev/null)
        rm -f "$REQ"

        log "exec req=$REQ_ID"

        # 명령 실행 (60초 타임아웃)
        START_TS=$(date +%s)
        RESULT=$(timeout 60 bash -c "$CMD" 2>&1)
        RC=$?
        END_TS=$(date +%s)
        DUR=$((END_TS - START_TS))

        # 응답 쓰기
        {
            echo "$REQ_ID"
            echo "rc=$RC"
            echo "duration=${DUR}s"
            echo "--- output ---"
            echo "$RESULT"
            echo "--- end ---"
        } > "$RESP"

        log "done req=$REQ_ID rc=$RC dur=${DUR}s"
    fi
    sleep 1
done
