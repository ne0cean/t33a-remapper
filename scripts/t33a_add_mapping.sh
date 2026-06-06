#!/bin/bash
# T33A 버튼 매핑 원클릭 추가 스크립트 (Mac에서 실행)
# 사용법: bash t33a_add_mapping.sh
# 사전 조건: USB 연결 상태, daemon=active

set -e

ADB=$(which adb)
CONFIG=/sdcard/Download/t33a_config.conf
LOG=/sdcard/Download/t33a.log

echo "=== T33A 매핑 추가 ==="
echo ""

# ── 1. pre-flight ──────────────────────────────────────────────
echo "[1/5] 시스템 상태 확인..."
STATUS=$($ADB shell "cat /data/local/tmp/t33a.status 2>/dev/null | tr -d '\n'" 2>/dev/null)
HB_AGE=$($ADB shell "NOW=\$(date +%s); MTIME=\$(stat -c %Y /data/local/tmp/t33a.relay_hb 2>/dev/null || echo 0); echo \$((NOW-MTIME))" 2>/dev/null | tr -d '\r')

if [ "$STATUS" != "active" ] || [ "${HB_AGE:-999}" -gt 30 ]; then
    echo "❌ 데몬 미실행 (status=$STATUS, relay_hb=${HB_AGE}s)"
    echo "   위젯 탭 또는 T33A 재시작 후 다시 실행하세요"
    exit 1
fi
echo "✓ 데몬 active, relay_hb=${HB_AGE}s"

# ── 2. 버튼 키코드 확인 ─────────────────────────────────────────
echo ""
echo "[2/5] 버튼 키코드 확인"
echo "   BLE 리모컨의 원하는 버튼을 누르세요 (5초 대기)..."
$ADB shell "tail -f $LOG" &
TAIL_PID=$!
sleep 5
kill $TAIL_PID 2>/dev/null
echo ""
read -p "   로그에서 확인한 keycode 입력 (예: 114): " KEYCODE
[ -z "$KEYCODE" ] && { echo "❌ 취소"; exit 1; }

# ── 3. 좌표 확인 ───────────────────────────────────────────────
echo ""
echo "[3/5] 탭 좌표 확인"
$ADB shell settings put system pointer_location 1
echo "   폰 화면을 터치해 좌표 확인 (상단에 X,Y 표시됨)"
read -p "   X 좌표: " TAP_X
read -p "   Y 좌표: " TAP_Y
$ADB shell settings put system pointer_location 0

# ── 4. 기존 설정 확인 + 추가 ──────────────────────────────────
echo ""
echo "[4/5] 현재 매핑:"
$ADB shell "cat $CONFIG 2>/dev/null || echo '(없음)'"
echo ""
read -p "   동작 타입 [tap/double/long] (기본: tap): " ACTION_TYPE
ACTION_TYPE=${ACTION_TYPE:-tap}

NEW_LINE="${KEYCODE} ${ACTION_TYPE} ${TAP_X} ${TAP_Y}"
echo "   추가할 매핑: $NEW_LINE"
read -p "   확인 [y/N]: " CONFIRM
[ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && { echo "취소"; exit 0; }

$ADB shell "echo '$NEW_LINE' >> $CONFIG"
echo "✓ 설정 추가 완료"

# ── 5. daemon restart ──────────────────────────────────────────
echo ""
echo "[5/5] 데몬 재시작..."
$ADB shell "echo restart > /sdcard/Download/t33a.cmd"
sleep 3

STATUS_NEW=$($ADB shell "cat /data/local/tmp/t33a.status 2>/dev/null | tr -d '\n'" 2>/dev/null)
echo ""
if [ "$STATUS_NEW" = "active" ]; then
    echo "✅ 완료! 매핑 적용됨 (status=$STATUS_NEW)"
    echo "   버튼 눌러서 동작 확인하세요"
else
    echo "⚠️  재시작 중 (status=$STATUS_NEW) — 잠시 후 위젯 탭으로 확인"
fi
