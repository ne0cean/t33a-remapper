#!/data/data/com.termux/files/usr/bin/bash
# T33A 폰 최초 설치 — Termux에서 1회 실행
# git + clang 설치, 레포 클론, 위젯 업데이트 숏컷 설치
set -e

REPO="$HOME/t33a-remapper"

echo "[1/3] 패키지 설치..."
pkg update -y
pkg install -y git clang linux-api-headers

echo "[2/3] 레포 클론..."
if [ -d "$REPO/.git" ]; then
    echo "  이미 있음 — pull"
    cd "$REPO" && git pull origin main
else
    git clone https://github.com/ne0cean/t33a-remapper.git "$REPO"
fi

echo "[3/3] 위젯 업데이트 숏컷 설치..."
mkdir -p "$HOME/.shortcuts"
cat > "$HOME/.shortcuts/T33A_Update" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash ~/t33a-remapper/scripts/t33a_update.sh
EOF
chmod +x "$HOME/.shortcuts/T33A_Update"

echo ""
echo "완료! 이제부터 업데이트 방법:"
echo "  Termux:Widget에서 'T33A_Update' 탭"
echo "  또는 Termux에서: bash ~/t33a-remapper/scripts/t33a_update.sh"
