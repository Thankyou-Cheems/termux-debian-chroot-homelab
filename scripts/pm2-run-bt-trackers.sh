#!/usr/bin/env bash
set -euo pipefail

UPDATE_INTERVAL_SEC="${BT_TRACKER_UPDATE_INTERVAL_SEC:-21600}"

mkdir -p /opt/logs/bt-trackers

while true; do
  if ! /opt/ops/scripts/update-bt-trackers.sh; then
    printf '[%s] tracker refresh failed\n' "$(date '+%F %T')" >&2
  fi
  sleep "${UPDATE_INTERVAL_SEC}"
done
