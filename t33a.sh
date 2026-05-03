#!/bin/bash
# T33A Remote Key Remapper — Mac 원클릭 빌드+배포+실행
# Usage: ./t33a.sh [start|stop|status|setup|deploy|watchdog]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG="$HOME/tools/zig-macos-aarch64-0.14.0/zig"
SRC="$SCRIPT_DIR/src/t33a_remap.c"
BUILD="$SCRIPT_DIR/build/t33a_remap"
PHONE="192.168.0.18:5555"
BIN="/data/local/tmp/t33a_remap"
CONF="$SCRIPT_DIR/t33a.conf"
REMOTE_CONF="/data/local/tmp/t33a.conf"
WATCHDOG_SCRIPT="/data/data/com.termux/files/home/t33a-remapper/scripts/t33a_watchdog.sh"

connect() {
    adb connect "$PHONE" 2>/dev/null | grep -q "connected" || {
        echo "Phone not reachable. Check WiFi or re-enable: adb tcpip 5555"
        exit 1
    }
}

build() {
    echo "Building (zig cc → aarch64-linux-musl)..."
    mkdir -p "$SCRIPT_DIR/build"
    "$ZIG" cc -target aarch64-linux-musl -static -o "$BUILD" "$SRC"
    echo "Built: $(file "$BUILD" | cut -d: -f2)"
}

deploy() {
    connect
    # 기존 데몬 정지
    adb -s "$PHONE" shell "$BIN stop" 2>/dev/null || true
    # 바이너리 및 설정 전송
    adb -s "$PHONE" push "$BUILD" "$BIN"
    adb -s "$PHONE" push "$CONF" "$REMOTE_CONF"
    adb -s "$PHONE" shell "chmod +x $BIN"
    # 새 데몬 시작
    adb -s "$PHONE" shell "$BIN"
    sleep 1
    adb -s "$PHONE" shell "$BIN status"
    echo "Deploy complete. Config loaded: $REMOTE_CONF"
}

case "${1:-start}" in
    push)
        # git push + 폰 즉시 update 트리거
        # relay의 cmd 파일 감시를 활용: "update" 쓰면 relay가 t33a_update.sh 실행
        git push origin main
        ADB_DEV=$(adb devices 2>/dev/null | grep -E 'device$' | grep -v 'List' | awk '{print $1}' | head -1)
        if [ -n "$ADB_DEV" ]; then
            adb -s "$ADB_DEV" shell "echo update > /sdcard/Download/t33a_update.trigger"
            echo "폰 update 트리거 전송 완료"
        else
            echo "ADB 없음 — 폰이 1분 내 자동 감지"
        fi
        ;;
    start)
        connect
        STATUS=$(adb -s "$PHONE" shell "$BIN status" 2>/dev/null)
        if echo "$STATUS" | grep -q "Running"; then
            echo "Already running. $STATUS"
        else
            adb -s "$PHONE" shell "$BIN"
            echo "T33A remapper started."
        fi
        ;;
    stop)
        connect
        adb -s "$PHONE" shell "$BIN stop"
        ;;
    status)
        connect
        adb -s "$PHONE" shell "$BIN status"
        ;;
    deploy)
        # 빌드 + 배포 + 시작 원클릭
        build
        deploy
        ;;
    setup)
        # 재부팅 후 WiFi ADB 재활성화 (USB 연결 필요)
        adb tcpip 5555
        sleep 2
        adb connect "$PHONE"
        echo "WiFi ADB enabled. USB can be disconnected."
        ;;
    watchdog)
        connect
        echo "Restarting watchdog on Termux..."
        adb -s "$PHONE" shell "bash $WATCHDOG_SCRIPT daemon"
        ;;
    *)
        echo "Usage: t33a.sh [start|stop|status|deploy|setup|watchdog]"
        ;;
esac
