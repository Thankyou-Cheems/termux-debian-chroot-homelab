#!/usr/bin/env bash
set -euo pipefail

mkdir -p /opt/data/aria2/config /opt/data/aria2/data /opt/logs/aria2
touch /opt/data/aria2/config/aria2.session
exec aria2c --conf-path=/opt/data/aria2/config/aria2.conf --daemon=false
