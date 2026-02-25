#!/usr/bin/env bash
set -euo pipefail

cd /opt/apps/mcsmanager/current/daemon
exec node --max-old-space-size=2048 --enable-source-maps app.js

