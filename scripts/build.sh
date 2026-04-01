#!/data/data/com.termux/files/usr/bin/bash
# Build t33a_remap from sdcard source
# Run this in Termux after: pkg install clang

set -e

SRC="/sdcard/Download/t33a_remap.c"
OUT="/data/local/tmp/t33a_remap_new"
BIN="/data/local/tmp/t33a_remap"

# Install clang if missing
command -v clang >/dev/null || pkg install -y clang

# Stop existing daemon
"$BIN" stop 2>/dev/null || true

# Build static binary
clang -o "$OUT" "$SRC"
chmod +x "$OUT"

# Replace old binary
cp "$OUT" "$BIN"
rm "$OUT"

# Start new daemon
"$BIN"
"$BIN" status

echo "Done. New binary deployed."
