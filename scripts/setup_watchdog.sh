#!/data/data/com.termux/files/usr/bin/bash
# Setup T33A watchdog cron job
# Run once in Termux

set -e

# Install crond if missing
command -v crond >/dev/null || pkg install -y cronie

# Copy watchdog script
mkdir -p ~/.local/bin
cp /sdcard/Download/t33a_watchdog.sh ~/.local/bin/t33a_watchdog.sh
chmod +x ~/.local/bin/t33a_watchdog.sh

# Add cron job (every minute)
CRON_LINE="* * * * * $HOME/.local/bin/t33a_watchdog.sh"
(crontab -l 2>/dev/null | grep -v t33a_watchdog; echo "$CRON_LINE") | crontab -

# Start crond
crond -b 2>/dev/null || true

echo "Watchdog cron installed. Runs every minute."
echo "Check: crontab -l"
