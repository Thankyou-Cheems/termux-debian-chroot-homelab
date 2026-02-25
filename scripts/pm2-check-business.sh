#!/usr/bin/env bash
set -euo pipefail

fail=0
CHECK_TIMEOUT_SEC="${CHECK_TIMEOUT_SEC:-30}"
CHECK_HOMEASSISTANT="${CHECK_HOMEASSISTANT:-auto}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "FAIL missing command: $1"
    fail=1
  fi
}

check_symlink() {
  local link_path="$1"
  local expected_target="$2"
  local name="$3"
  if [[ ! -L "$link_path" ]]; then
    echo "FAIL symlink ${name} missing: ${link_path}"
    fail=1
    return
  fi
  if [[ "$(readlink "$link_path")" == "$expected_target" ]]; then
    echo "OK   symlink ${name} ${link_path} -> ${expected_target}"
  else
    echo "FAIL symlink ${name} ${link_path} -> $(readlink "$link_path")"
    fail=1
  fi
}

check_port() {
  local p="$1"
  local name="$2"
  local deadline=$((SECONDS + CHECK_TIMEOUT_SEC))
  while (( SECONDS <= deadline )); do
    if ss -tnlp 2>/dev/null | grep -q ":${p} "; then
      echo "OK   port ${p} (${name})"
      return
    fi
    sleep 1
  done
  echo "FAIL port ${p} (${name})"
  fail=1
}

check_http() {
  local url="$1"
  local name="$2"
  local code
  local deadline=$((SECONDS + CHECK_TIMEOUT_SEC))
  while (( SECONDS <= deadline )); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' "$url" || true)"
    if [[ "$code" =~ ^(200|301|302|307|308|401|403)$ ]]; then
      echo "OK   http ${name} ${url} -> ${code}"
      return
    fi
    sleep 1
  done
  echo "FAIL http ${name} ${url} -> ${code:-ERR}"
  fail=1
}

require_cmd pm2
require_cmd ss
require_cmd curl
require_cmd awk

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "Business stack health check: FAIL"
  exit 1
fi

echo "== Layout checks =="
check_symlink "/opt/apps/caddy/current/Caddyfile" "/opt/data/caddy/Caddyfile" "caddy-caddyfile"
check_symlink "/opt/apps/caddy/current/upstreams.env" "/opt/data/caddy/upstreams.env" "caddy-upstreams"

if [[ ! -f /opt/data/caddy/Caddyfile ]]; then
  echo "FAIL missing /opt/data/caddy/Caddyfile"
  fail=1
else
  echo "OK   file /opt/data/caddy/Caddyfile"
fi

if [[ ! -f /opt/data/caddy/upstreams.env ]]; then
  echo "FAIL missing /opt/data/caddy/upstreams.env"
  fail=1
else
  echo "OK   file /opt/data/caddy/upstreams.env"
fi

echo
asf_upstream="$(awk -F= '/^ASF_UPSTREAM=/{print $2; exit}' /opt/data/caddy/upstreams.env 2>/dev/null || true)"
if [[ -z "$asf_upstream" && -f /opt/data/asf/config/IPC.config ]]; then
  asf_upstream="$(
    awk -F'"' '
      /"Url"/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^http:\/\//) {
            sub(/^http:\/\//, "", $i);
            print $i;
            exit;
          }
        }
      }
    ' /opt/data/asf/config/IPC.config
  )"
fi
if [[ -z "$asf_upstream" ]]; then
  asf_upstream="127.0.0.1:1242"
fi
asf_port="${asf_upstream##*:}"

echo "== PM2 process list =="
pm2 ls

echo
echo "== Port checks =="
check_port 6800 "aria2-rpc"
check_port 8384 "syncthing-gui"
check_port 8080 "caddy"
check_port 23333 "mcs-web"
check_port 24444 "mcs-daemon"
check_port "$asf_port" "asf-web"

echo
echo "== HTTP checks =="
check_http "http://127.0.0.1:8080/" "caddy-root"
check_http "http://127.0.0.1:8080/mcs/" "caddy-mcs"
check_http "http://127.0.0.1:8080/asf/" "caddy-asf"
check_http "http://127.0.0.1:8080/aria2/" "caddy-aria2"
check_http "http://127.0.0.1:8080/syncthing/" "caddy-syncthing"
check_http "http://${asf_upstream}/" "asf-web"
check_http "http://127.0.0.1:8384/" "syncthing-gui"

ha_enabled=0
if [[ "$CHECK_HOMEASSISTANT" == "1" ]]; then
  ha_enabled=1
elif [[ "$CHECK_HOMEASSISTANT" == "auto" ]]; then
  ha_pid="$(pm2 pid homeassistant 2>/dev/null || true)"
  if [[ "$ha_pid" =~ ^[0-9]+$ ]] && [[ "$ha_pid" -gt 0 ]]; then
    ha_enabled=1
  fi
fi

if [[ "$ha_enabled" -eq 1 ]]; then
  check_port 8123 "homeassistant-web"
  check_http "http://127.0.0.1:8123/" "homeassistant-web"
  if [[ -f /sys/fs/cgroup/opt-homeassistant/memory.current ]]; then
    echo "INFO homeassistant cgroup: current=$(cat /sys/fs/cgroup/opt-homeassistant/memory.current) high=$(cat /sys/fs/cgroup/opt-homeassistant/memory.high) max=$(cat /sys/fs/cgroup/opt-homeassistant/memory.max) swap.max=$(cat /sys/fs/cgroup/opt-homeassistant/memory.swap.max)"
  fi
else
  echo "SKIP homeassistant checks (set CHECK_HOMEASSISTANT=1 to force)"
fi

echo
echo "== Aria2 RPC check =="
rpc_secret="$(awk -F= '/^rpc-secret=/{print $2; exit}' /opt/data/aria2/config/aria2.conf || true)"
if [[ -n "$rpc_secret" ]]; then
  rpc_res="$(curl -sS -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":\"health\",\"method\":\"aria2.getVersion\",\"params\":[\"token:${rpc_secret}\"]}" \
    http://127.0.0.1:6800/jsonrpc || true)"
  if echo "$rpc_res" | grep -q '"result"'; then
    echo "OK   aria2 rpc responded"
  else
    echo "FAIL aria2 rpc check failed: ${rpc_res:-EMPTY}"
    fail=1
  fi
else
  echo "FAIL missing rpc-secret in /opt/data/aria2/config/aria2.conf"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo
  echo "Business stack health check: PASS"
else
  echo
  echo "Business stack health check: FAIL"
  exit 1
fi
