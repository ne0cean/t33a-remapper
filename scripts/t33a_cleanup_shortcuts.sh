#!/data/data/com.termux/files/usr/bin/bash
# T33A 위젯 정리 — 불필요한 shortcuts 삭제, T33A 1개만 남김
# 사용: Termux 터미널에서 bash /sdcard/Download/t33a_cleanup_shortcuts.sh

SHORTCUT_DIR="$HOME/.shortcuts"
WRAPPER=/sdcard/Download/T33A_wrapper
LOG=/sdcard/Download/t33a_boot.log

echo "=== T33A 위젯 정리 $(date) ==="
echo "현재 shortcuts:"
ls -la "$SHORTCUT_DIR/" 2>/dev/null || echo "(없음)"

echo ""
echo "T33A 외 삭제 중..."
removed=0
ls "$SHORTCUT_DIR/" 2>/dev/null | while read f; do
    [ "$f" = "T33A" ] && continue
    rm -f "$SHORTCUT_DIR/$f"
    echo "  삭제: $f"
    removed=$((removed+1))
done

# T33A 최신 버전으로 교체
if [ -f "$WRAPPER" ]; then
    cp "$WRAPPER" "$SHORTCUT_DIR/T33A" && chmod +x "$SHORTCUT_DIR/T33A"
    echo "T33A 위젯 최신화 완료"
fi

echo ""
echo "정리 후 shortcuts:"
ls -la "$SHORTCUT_DIR/" 2>/dev/null

echo "$(date): shortcut cleanup done" >> "$LOG"
echo ""
echo "완료. Termux Widget 앱 갱신하면 T33A 1개만 표시됨."
