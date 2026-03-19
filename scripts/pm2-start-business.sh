#!/usr/bin/env bash
set -euo pipefail

ECOSYSTEM_FILE="/opt/ops/deploy/pm2/ecosystem.business.config.js"
CADDY_DATA_DIR="/opt/data/caddy"
CADDY_APP_DIR="/opt/apps/caddy/current"
CADDY_TEMPLATE_FILE="/opt/ops/deploy/caddy/Caddyfile"
ENABLE_HOMEASSISTANT="${ENABLE_HOMEASSISTANT:-0}"

command -v pm2 >/dev/null 2>&1 || {
  echo "ERROR: pm2 not found" >&2
  exit 1
}
[[ -f "$ECOSYSTEM_FILE" ]] || {
  echo "ERROR: missing PM2 ecosystem file: $ECOSYSTEM_FILE" >&2
  exit 1
}

ensure_caddy_layout() {
  local data_caddy_file="${CADDY_DATA_DIR}/Caddyfile"
  local data_upstreams_file="${CADDY_DATA_DIR}/upstreams.env"
  local app_caddy_file="${CADDY_APP_DIR}/Caddyfile"
  local app_upstreams_file="${CADDY_APP_DIR}/upstreams.env"

  mkdir -p /opt/logs "$CADDY_DATA_DIR" "$CADDY_APP_DIR"

  if [[ ! -f "$data_caddy_file" ]]; then
    if [[ -f "$CADDY_TEMPLATE_FILE" ]]; then
      cp "$CADDY_TEMPLATE_FILE" "$data_caddy_file"
      echo "INFO: initialized Caddyfile from template ${CADDY_TEMPLATE_FILE}"
    elif [[ -f "$app_caddy_file" && ! -L "$app_caddy_file" ]]; then
      cp "$app_caddy_file" "$data_caddy_file"
      echo "INFO: migrated Caddyfile to ${data_caddy_file}"
    else
      echo "ERROR: missing ${data_caddy_file}" >&2
      exit 1
    fi
  fi

  if [[ ! -f "$data_upstreams_file" ]]; then
    if [[ -f "$app_upstreams_file" && ! -L "$app_upstreams_file" ]]; then
      cp "$app_upstreams_file" "$data_upstreams_file"
      echo "INFO: migrated upstreams.env to ${data_upstreams_file}"
    else
      cat > "$data_upstreams_file" <<'EOF'
# Caddy reverse-proxy upstreams
ASF_UPSTREAM=127.0.0.1:1242
EOF
    fi
  fi

  ln -sfn "$data_caddy_file" "$app_caddy_file"
  ln -sfn "$data_upstreams_file" "$app_upstreams_file"
}

sync_asf_upstream() {
  local upstreams_file="${CADDY_DATA_DIR}/upstreams.env"
  local asf_upstream=""

  if [[ -f /opt/data/asf/config/IPC.config ]]; then
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

  if [[ -n "${asf_upstream}" ]]; then
    if grep -q '^ASF_UPSTREAM=' "$upstreams_file"; then
      sed -i "s#^ASF_UPSTREAM=.*#ASF_UPSTREAM=${asf_upstream}#" "$upstreams_file"
    else
      printf '\nASF_UPSTREAM=%s\n' "$asf_upstream" >> "$upstreams_file"
    fi
  fi
}

ensure_upstream_defaults() {
  local upstreams_file="${CADDY_DATA_DIR}/upstreams.env"

  if ! grep -q '^ASF_UPSTREAM=' "$upstreams_file"; then
    printf '\nASF_UPSTREAM=127.0.0.1:1242\n' >> "$upstreams_file"
  fi
  if ! grep -q '^SYNCTHING_UPSTREAM=' "$upstreams_file"; then
    printf 'SYNCTHING_UPSTREAM=127.0.0.1:8384\n' >> "$upstreams_file"
  fi
  if ! grep -q '^FILEBROWSER_UPSTREAM=' "$upstreams_file"; then
    printf 'FILEBROWSER_UPSTREAM=127.0.0.1:8095\n' >> "$upstreams_file"
  fi
}

ensure_caddy_layout
sync_asf_upstream
ensure_upstream_defaults

PM2_ONLY_APPS="asf,mcs-daemon,mcs-web,aria2,transmission,bt-trackers,syncthing,filebrowser,direct-candidates,caddy,tinyproxy"
if [[ "$ENABLE_HOMEASSISTANT" == "1" ]]; then
  PM2_ONLY_APPS="${PM2_ONLY_APPS},homeassistant"
  echo "INFO: HomeAssistant enabled for this run"
else
  pm2 delete homeassistant >/dev/null 2>&1 || true
  echo "INFO: HomeAssistant disabled by default (set ENABLE_HOMEASSISTANT=1 to enable)"
fi

pm2 start "$ECOSYSTEM_FILE" --only "$PM2_ONLY_APPS" --update-env
pm2 save --force >/dev/null
pm2 ls
