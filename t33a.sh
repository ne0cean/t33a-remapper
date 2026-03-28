#!/bin/bash
# T33A Remote Key Remapper — 매일 아침 운동 전 실행
# Usage: ./t33a.sh [start|stop|status]

PHONE="192.168.0.18:5555"
BIN="/data/local/tmp/t33a_remap"

connect() {
    adb connect "$PHONE" 2>/dev/null | grep -q "connected" || {
        echo "Phone not reachable. Check WiFi or re-enable: adb tcpip 5555"
        exit 1
    }
}

case "${1:-start}" in
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
    setup)
        # 재부팅 후 WiFi ADB 재활성화 (USB 연결 필요)
        adb tcpip 5555
        sleep 2
        adb connect "$PHONE"
        echo "WiFi ADB enabled. USB can be disconnected."
        ;;
    *)
        echo "Usage: t33a.sh [start|stop|status|setup]"
        ;;
esac
