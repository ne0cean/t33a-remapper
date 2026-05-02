#!/data/data/com.termux/files/usr/bin/bash
# T33A 폰 최초 설치 — Termux에서 1회 실행
# 이후 코드 변경은 Mac에서 git push → 폰이 5분 내 자동 감지+반영
#
# 사용법:
#   curl -fsSL https://raw.githubusercontent.com/ne0cean/t33a-remapper/main/scripts/t33a_setup_phone.sh | bash
#   또는 Termux에서: bash /sdcard/Download/t33a_setup_phone.sh

set -e

REPO="$HOME/t33a-remapper"
SHORTCUT_DIR="$HOME/.shortcuts"
BOOT_DIR="$HOME/.termux/boot"

echo "=== T33A 폰 설치 시작 ==="

# [1] 패키지 설치
echo "[1/4] 패키지 설치 (git, clang)..."
pkg update -y 2>&1 | tail -3
pkg install -y git clang linux-api-headers 2>&1 | tail -5

# [2] 레포 클론 또는 업데이트
echo "[2/4] 레포 설정..."
if [ -d "$REPO/.git" ]; then
    echo "  이미 있음 — pull"
    git -C "$REPO" fetch origin main
    git -C "$REPO" reset --hard origin/main
else
    git clone https://github.com/ne0cean/t33a-remapper.git "$REPO"
fi
echo "  레포: $(git -C "$REPO" rev-parse --short HEAD)"

# [3] 위젯 숏컷 설치
echo "[3/4] 위젯 숏컷 설치..."
mkdir -p "$SHORTCUT_DIR" "$BOOT_DIR"

# T33A_Update 위젯 — 수동 즉시 업데이트
cat > "$SHORTCUT_DIR/T33A_Update" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash ~/t33a-remapper/scripts/t33a_update.sh 2>&1 | termux-toast -s
EOF
chmod +x "$SHORTCUT_DIR/T33A_Update"

# boot.sh를 Termux:Boot에 등록
if [ -f "$REPO/scripts/t33a_boot.sh" ]; then
    cp "$REPO/scripts/t33a_boot.sh" "$BOOT_DIR/t33a_boot.sh"
    chmod +x "$BOOT_DIR/t33a_boot.sh"
    echo "  Termux:Boot 등록 완료"
fi

# [4] 초기 바이너리 빌드
echo "[4/4] 초기 빌드 (clang)..."
mkdir -p /sdcard/Download
clang -O2 -o /data/local/tmp/t33a_remap "$REPO/src/t33a_remap.c"
chmod +x /data/local/tmp/t33a_remap
cp /data/local/tmp/t33a_remap /sdcard/Download/t33a_remap
echo "  바이너리: $(ls -lh /data/local/tmp/t33a_remap | awk '{print $5}')"

# 스크립트 /sdcard/Download에도 복사 (relay/boot가 거기서 읽음)
for f in boot relay start; do
    cp "$REPO/scripts/t33a_${f}.sh" "/sdcard/Download/t33a_${f}.sh"
    chmod +x "/sdcard/Download/t33a_${f}.sh"
done
cp "$REPO/t33a.conf" /sdcard/Download/t33a.conf 2>/dev/null || true

echo ""
echo "=== 설치 완료 ==="
echo ""
echo "이제부터 코드 변경 방법:"
echo "  Mac에서: git push origin main"
echo "  → 폰이 5분 내 자동 감지 후 업데이트"
echo ""
echo "즉시 업데이트:"
echo "  Termux:Widget → 'T33A_Update' 탭"
echo "  또는: bash ~/t33a-remapper/scripts/t33a_update.sh"
echo ""
echo "다음 재부팅부터 auto_pull 자동 시작됨"
echo "(지금 당장 시작: bash ~/t33a-remapper/scripts/t33a_boot.sh &)"
