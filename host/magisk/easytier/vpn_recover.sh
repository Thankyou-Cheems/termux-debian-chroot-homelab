#!/system/bin/sh
MODDIR=${0%/*}
CFG="$MODDIR/config/config.toml"
LOG="$MODDIR/log.log"
CORE="$MODDIR/easytier-core"
HOTSPOT="$MODDIR/hotspot_iprule.sh"
NAT_TS="$MODDIR/.nat_refresh.ts"

EVENT_DEBOUNCE_SEC="${EVENT_DEBOUNCE_SEC:-2}"
NAT_REFRESH_MIN_INTERVAL="${NAT_REFRESH_MIN_INTERVAL:-20}"

log() {
  echo "[VPN-RECOVER] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

ensure_singleton() {
  self="$$"
  for pid in $(pgrep -f '[v]pn_recover.sh monitor' 2>/dev/null); do
    [ "$pid" = "$self" ] && continue
    log "another monitor exists (pid=$pid), exit"
    exit 0
  done
}

get_dev() {
  awk -F'"' '/^[[:space:]]*dev_name[[:space:]]*=/{print $2; exit}' "$CFG"
}

get_cidr() {
  awk -F'"' '/^[[:space:]]*ipv4[[:space:]]*=/{print $2; exit}' "$CFG"
}

get_peer_hosts() {
  awk -F'"' '/^[[:space:]]*uri[[:space:]]*=/{print $2}' "$CFG" \
    | sed -E 's#^[a-zA-Z0-9+.-]+://##; s#/.*$##; s#:[0-9]+$##' \
    | awk 'NF && $0 !~ /^\[/' \
    | sort -u
}

get_uplink() {
  for table in wlan0 rmnet_data0 rmnet_data1 eth0; do
    line="$(ip -4 route show table "$table" 2>/dev/null | awk '/^default /{print; exit}')"
    [ -n "$line" ] || continue

    dev="$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    gw="$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')"

    if [ -n "$dev" ]; then
      echo "$dev $gw"
      return 0
    fi
  done
  return 1
}

start_core() {
  if [ -f "$MODDIR/config/command_args" ]; then
    TZ=Asia/Shanghai "$CORE" $(cat "$MODDIR/config/command_args") --hostname "$(getprop ro.product.brand)-$(getprop ro.product.model)" >> "$LOG" 2>&1 &
  else
    TZ=Asia/Shanghai "$CORE" -c "$CFG" --hostname "$(getprop ro.product.brand)-$(getprop ro.product.model)" >> "$LOG" 2>&1 &
  fi
}

ensure_core() {
  if ! pgrep -f '[e]asytier-core' >/dev/null 2>&1; then
    log "easytier-core not running, starting"
    start_core
    sleep 3
  fi
}

pin_peer_routes() {
  uplink="$(get_uplink || true)"
  [ -n "$uplink" ] || return 0

  up_dev="$(echo "$uplink" | awk '{print $1}')"
  up_gw="$(echo "$uplink" | awk '{print $2}')"
  [ -n "$up_dev" ] || return 0

  for host in $(get_peer_hosts); do
    case "$host" in
      ""|*:* )
        continue
        ;;
    esac

    cur="$(ip -4 route show "$host/32" table main 2>/dev/null | head -n1)"
    if [ -n "$up_gw" ]; then
      echo "$cur" | grep -q " dev $up_dev" && echo "$cur" | grep -q " via $up_gw" && continue
      ip route replace "$host/32" via "$up_gw" dev "$up_dev" table main metric 5 >/dev/null 2>&1 || continue
      log "peer route pinned: $host/32 via $up_gw dev $up_dev"
    else
      echo "$cur" | grep -q " dev $up_dev" && continue
      ip route replace "$host/32" dev "$up_dev" table main metric 5 >/dev/null 2>&1 || continue
      log "peer route pinned: $host/32 via direct dev $up_dev"
    fi
  done
}

repair_route() {
  ET_IF="$(get_dev)"
  ET_CIDR="$(get_cidr)"

  [ -n "$ET_IF" ] || return 0
  [ -n "$ET_CIDR" ] || return 0

  if ! ip link show "$ET_IF" >/dev/null 2>&1; then
    log "interface not ready: $ET_IF"
    return 0
  fi

  cur="$(ip -4 route show "$ET_CIDR" 2>/dev/null | head -n1)"
  if echo "$cur" | grep -q " dev $ET_IF"; then
    return 0
  fi

  ip route replace "$ET_CIDR" dev "$ET_IF" table main >/dev/null 2>&1 || true
  ip route flush cache >/dev/null 2>&1 || true
  log "route repaired: $ET_CIDR -> $ET_IF"
}

should_refresh_nat() {
  now="$(date +%s)"
  last=0

  if [ -f "$NAT_TS" ]; then
    last="$(cat "$NAT_TS" 2>/dev/null || echo 0)"
  fi

  [ $((now - last)) -ge "$NAT_REFRESH_MIN_INTERVAL" ]
}

repair_nat() {
  [ -f "$MODDIR/enable_IP_rule" ] || return 0

  if should_refresh_nat; then
    "$HOTSPOT" add_once >/dev/null 2>&1 || true
    date +%s > "$NAT_TS"
    log "nat rules refreshed (throttled)"
  fi
}

repair_all() {
  ensure_core
  pin_peer_routes
  repair_route
  repair_nat
}

case "${1:-monitor}" in
  once)
    repair_all
    ;;
  monitor)
    ensure_singleton
    repair_all
    last_run=0
    ip monitor route link addr 2>/dev/null | while read -r _; do
      now="$(date +%s)"
      if [ $((now - last_run)) -lt "$EVENT_DEBOUNCE_SEC" ]; then
        continue
      fi
      last_run="$now"
      repair_all
    done
    ;;
  *)
    echo "Usage: $0 [once|monitor]"
    exit 1
    ;;
esac
