#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

prefix_default="/data/data/com.termux/files/usr"
sshd_bin="${PREFIX:-$prefix_default}/bin/sshd"
log_file="$HOME/.termux/boot.log"

mkdir -p "$HOME/.termux"

if command -v pidof >/dev/null 2>&1 && pidof sshd >/dev/null 2>&1; then
  status="already-running"
elif pgrep -f "/bin/sshd" >/dev/null 2>&1; then
  status="already-running"
else
  "$sshd_bin"
  status="started"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] boot script: sshd=$status" >> "$log_file"

# codex_debian_ssh_boot
if command -v su >/dev/null 2>&1; then
  su -c "$HOME/.local/bin/start-debian-root.sh '/usr/local/sbin/codex-start-sshd.sh'" >/dev/null 2>&1 || true
fi

# codex_wakelock_boot
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock >/dev/null 2>&1 || true
fi
