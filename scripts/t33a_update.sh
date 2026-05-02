#!/data/data/com.termux/files/usr/bin/bash
# T33A 폰-내 업데이트 — USB 없이 배포
# Mac에서 push → 폰 Termux에서 이 스크립트 실행 (또는 T33A_Update 위젯 탭)
set -e

REPO="$HOME/t33a-remapper"
BIN="/data/local/tmp/t33a_remap"
BIN_SDCARD="/sdcard/Download/t33a_remap"
CMD="/sdcard/Download/t33a.cmd"

echo "[1/3] git pull..."
cd "$REPO"
git pull origin main

echo "[2/3] 컴파일 (clang)..."
clang -O2 -o "$BIN" src/t33a_remap.c
chmod +x "$BIN"
cp "$BIN" "$BIN_SDCARD"  # boot.sh 자동 설치 경로에도 복사
echo "  빌드 OK: $(ls -lh "$BIN" | awk '{print $5, $9}')"

echo "[3/3] 데몬 재시작 (relay 통해)..."
echo "update" > "$CMD"
sleep 4

STATUS=$(cat /data/local/tmp/t33a.status 2>/dev/null || echo "unknown")
echo "완료! 데몬 상태: $STATUS"
