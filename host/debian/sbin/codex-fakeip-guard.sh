#!/bin/bash
set -euo pipefail

HOSTS_FILE="/etc/hosts"
LOG_FILE="/var/log/codex-fakeip-guard.log"
LOCK_DIR="/run/codex-fakeip-guard.lock"
START_MARK="# codex_no_fakeip_start"
END_MARK="# codex_no_fakeip_end"

# Comma- or space-separated domains can be overridden with env var.
RAW_DOMAINS="${CODEX_FAKEIP_DOMAINS:-chatgpt.com}"
REFRESH_INTERVAL_SEC="${REFRESH_INTERVAL_SEC:-15}"

log() {
  mkdir -p /var/log >/dev/null 2>&1 || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

normalize_domains() {
  echo "$RAW_DOMAINS" | tr ',' ' ' | xargs -n1 | awk 'NF' | sort -u
}

extract_ipv4_from_doh_json() {
  python3 -c '
import json, sys

def valid_ipv4(s: str) -> bool:
    parts = s.strip().split(".")
    if len(parts) != 4:
        return False
    for p in parts:
        if not p.isdigit():
            return False
        n = int(p)
        if n < 0 or n > 255:
            return False
    return True

payload = json.load(sys.stdin)
answers = payload.get("Answer", [])
ips = []
for item in answers:
    if item.get("type") != 1:
        continue
    data = str(item.get("data", "")).strip()
    if valid_ipv4(data):
        ips.append(data)
if not ips:
    raise SystemExit(2)
for ip in sorted(set(ips)):
    print(ip)
'
}

resolve_a_records() {
  local domain="$1"
  local ips

  ips="$(curl -fsS -m 12 "https://dns.google/resolve?name=${domain}&type=A" 2>/dev/null | extract_ipv4_from_doh_json 2>/dev/null || true)"
  if [ -n "$ips" ]; then
    echo "$ips"
    return 0
  fi

  ips="$(curl -fsS -m 12 -H 'accept: application/dns-json' "https://1.1.1.1/dns-query?name=${domain}&type=A" 2>/dev/null | extract_ipv4_from_doh_json 2>/dev/null || true)"
  if [ -n "$ips" ]; then
    echo "$ips"
    return 0
  fi

  return 1
}

apply_hosts_block() {
  local mapping_file="$1"
  local tmp_file
  tmp_file="$(mktemp)"

  awk -v s="$START_MARK" -v e="$END_MARK" '
    $0 == s {skip = 1; next}
    $0 == e {skip = 0; next}
    !skip {print}
  ' "$HOSTS_FILE" > "$tmp_file"

  {
    cat "$tmp_file"
    echo
    echo "$START_MARK"
    cat "$mapping_file"
    echo "$END_MARK"
  } > "$HOSTS_FILE"

  rm -f "$tmp_file"
}

refresh_hosts_once() {
  local mapping_file
  mapping_file="$(mktemp)"

  local domain ips ok
  ok=1

  while read -r domain; do
    [ -n "$domain" ] || continue

    if ! ips="$(resolve_a_records "$domain")"; then
      log "resolve failed for $domain; keep current hosts mapping"
      ok=0
      break
    fi

    while read -r ip; do
      [ -n "$ip" ] || continue
      echo "$ip $domain" >> "$mapping_file"
    done <<EOF_IPS
$ips
EOF_IPS
  done <<EOF_DOMAINS
$(normalize_domains)
EOF_DOMAINS

  if [ "$ok" -eq 1 ] && [ -s "$mapping_file" ]; then
    sort -u "$mapping_file" -o "$mapping_file"
    apply_hosts_block "$mapping_file"
    log "hosts refreshed for: $(normalize_domains | tr '\n' ' ')"
  fi

  rm -f "$mapping_file"
}

acquire_singleton() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "already running, skip"
    exit 0
  fi
  trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT INT TERM
}

run_daemon() {
  acquire_singleton
  while true; do
    refresh_hosts_once || true
    sleep "$REFRESH_INTERVAL_SEC"
  done
}

case "${1:-daemon}" in
  once)
    refresh_hosts_once
    ;;
  daemon)
    run_daemon
    ;;
  *)
    echo "Usage: $0 [once|daemon]"
    exit 1
    ;;
esac
