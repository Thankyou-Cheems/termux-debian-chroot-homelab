#!/bin/bash
set -euo pipefail
mkdir -p /run/sshd /opt/logs

# Keep codex domains out of fake-ip mappings and auto-refresh on route changes.
if [ -x /usr/local/sbin/codex-fakeip-guard.sh ]; then
  if ! pgrep -f '/usr/local/sbin/codex-fakeip-guard.sh daemon' >/dev/null 2>&1; then
    nohup /usr/local/sbin/codex-fakeip-guard.sh daemon >/dev/null 2>&1 &
  fi
fi

# Keep PM2 business stack up after each Debian chroot bootstrap.
if [ -x /opt/ops/scripts/pm2-start-business.sh ]; then
  nohup /opt/ops/scripts/pm2-start-business.sh >/opt/logs/pm2-start-business.boot.log 2>&1 &
fi

/usr/sbin/sshd -t -f /etc/ssh/sshd_config
if [ -f /run/sshd.pid ]; then
  old_pid="$(cat /run/sshd.pid 2>/dev/null || true)"
  if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" || true
    sleep 1
  fi
fi
exec /usr/sbin/sshd -f /etc/ssh/sshd_config
