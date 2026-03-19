#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

TRACKER_DIR="${DATA_ROOT}/bt-trackers"
TRACKER_FILE="${TRACKER_DIR}/trackers-best.txt"
TRACKER_SHA_FILE="${TRACKER_DIR}/trackers-best.sha256"
TRANSMISSION_APPLY_SHA_FILE="${TRACKER_DIR}/transmission-applied.sha256"
ARIA2_CONF_FILE="${DATA_ROOT}/aria2/config/aria2.conf"
ARIA2_RPC_SECRET_FILE="${DATA_ROOT}/aria2/config/rpc-secret.txt"
ARIA2_CONF_WRITE_FILE="${SECRETS_ROOT}/aria2/aria2.conf"
TRANSMISSION_SETTINGS_FILE="${DATA_ROOT}/transmission/config/settings.json"
TRANSMISSION_USER_FILE="${SECRETS_ROOT}/transmission/rpc-username.txt"
TRANSMISSION_PASSWORD_FILE="${SECRETS_ROOT}/transmission/rpc-password.txt"
TRANSMISSION_RPC_URL="http://127.0.0.1:9091/transmission/rpc"
ARIA2_RPC_URL="http://127.0.0.1:6800/jsonrpc"

TRACKER_SOURCES=(
  "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt"
  "https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/best.txt"
)

require_cmd curl
require_cmd awk
require_cmd sha256sum
require_cmd ss

mkdir -p "${TRACKER_DIR}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

fetch_ok=0
for idx in "${!TRACKER_SOURCES[@]}"; do
  source_url="${TRACKER_SOURCES[$idx]}"
  target_file="${tmp_dir}/source-${idx}.txt"
  if curl -fsSL --connect-timeout 15 --max-time 60 "${source_url}" -o "${target_file}"; then
    fetch_ok=1
  else
    log "tracker source failed: ${source_url}"
  fi
done

if [[ "${fetch_ok}" -ne 1 ]]; then
  die "all tracker sources failed"
fi

cat "${tmp_dir}"/source-*.txt 2>/dev/null \
  | tr '\r' '\n' \
  | sed 's/[[:space:]]*$//' \
  | awk '
      NF == 0 { next }
      $0 ~ /^[[:space:]]*#/ { next }
      $0 !~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\// { next }
      !seen[$0]++ { print }
    ' > "${tmp_dir}/trackers-best.txt"

if [[ ! -s "${tmp_dir}/trackers-best.txt" ]]; then
  die "merged tracker list is empty"
fi

install -m 0644 "${tmp_dir}/trackers-best.txt" "${TRACKER_FILE}"

tracker_count="$(wc -l < "${TRACKER_FILE}")"
tracker_csv="$(paste -sd, "${TRACKER_FILE}")"
tracker_json="$(
  awk '
    BEGIN { first = 1 }
    {
      gsub(/\\/,"\\\\");
      gsub(/"/,"\\\"");
      if (!first) {
        printf "\\n";
      }
      printf "%s", $0;
      first = 0;
    }
  ' "${TRACKER_FILE}"
)"
tracker_sha="$(sha256sum "${TRACKER_FILE}" | awk '{print $1}')"
printf '%s  %s\n' "${tracker_sha}" "${TRACKER_FILE}" > "${TRACKER_SHA_FILE}"

if [[ ! -f "${ARIA2_CONF_WRITE_FILE}" ]]; then
  ARIA2_CONF_WRITE_FILE="${ARIA2_CONF_FILE}"
fi

if [[ -f "${ARIA2_CONF_WRITE_FILE}" ]]; then
  awk -v tracker_csv="${tracker_csv}" '
    BEGIN { updated = 0 }
    /^bt-tracker=/ {
      print "bt-tracker=" tracker_csv
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print ""
        print "# 动态 tracker 列表（由 update-bt-trackers.sh 维护）"
        print "bt-tracker=" tracker_csv
      }
    }
  ' "${ARIA2_CONF_WRITE_FILE}" > "${tmp_dir}/aria2.conf"
  install -m 0600 "${tmp_dir}/aria2.conf" "${ARIA2_CONF_WRITE_FILE}"

  if [[ -s "${ARIA2_RPC_SECRET_FILE}" ]]; then
    aria2_secret="$(tr -d '\r\n' < "${ARIA2_RPC_SECRET_FILE}")"
    curl -fsS \
      -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":\"tracker-refresh\",\"method\":\"aria2.changeGlobalOption\",\"params\":[\"token:${aria2_secret}\",{\"bt-tracker\":\"${tracker_csv}\"}]}" \
      "${ARIA2_RPC_URL}" >/dev/null 2>&1 || true
  fi
fi

transmission_running=0
if ss -tnl 2>/dev/null | grep -q ':9091 '; then
  transmission_running=1
fi

transmission_auth=""
if [[ -s "${TRANSMISSION_USER_FILE}" && -s "${TRANSMISSION_PASSWORD_FILE}" ]]; then
  transmission_auth="$(tr -d '\r\n' < "${TRANSMISSION_USER_FILE}"):$(tr -d '\r\n' < "${TRANSMISSION_PASSWORD_FILE}")"
fi

transmission_session_id() {
  local headers
  headers="$(curl -sS -u "${transmission_auth}" -D - -o /dev/null "${TRANSMISSION_RPC_URL}" || true)"
  printf '%s\n' "${headers}" \
    | awk -F': ' 'tolower($1) == "x-transmission-session-id" { gsub(/\r/, "", $2); print $2; exit }'
}

transmission_rpc() {
  local payload="$1"
  local sid

  sid="$(transmission_session_id)"
  [[ -n "${sid}" ]] || return 1

  curl -fsS \
    -u "${transmission_auth}" \
    -H "X-Transmission-Session-Id: ${sid}" \
    -H 'Content-Type: application/json' \
    -d "${payload}" \
    "${TRANSMISSION_RPC_URL}"
}

update_transmission_settings_file() {
  [[ -f "${TRANSMISSION_SETTINGS_FILE}" ]] || return 0
  awk -v tracker_json="${tracker_json}" '
    BEGIN { updated = 0; inserted = 0 }
    {
      if ($0 ~ /"default-trackers":/) {
        print "    \"default-trackers\": \"" tracker_json "\","
        updated = 1
        next
      }
      print
      if (!updated && !inserted && $0 ~ /^[[:space:]]*\{[[:space:]]*$/) {
        print "    \"default-trackers\": \"" tracker_json "\","
        inserted = 1
      }
    }
  ' "${TRANSMISSION_SETTINGS_FILE}" > "${tmp_dir}/settings.json"
  install -m 0600 "${tmp_dir}/settings.json" "${TRANSMISSION_SETTINGS_FILE}"
}

if [[ -n "${transmission_auth}" ]]; then
  if [[ "${transmission_running}" -eq 1 ]]; then
    transmission_rpc "{\"method\":\"session-set\",\"arguments\":{\"default-trackers\":\"${tracker_json}\"}}" >/dev/null 2>&1 || true

    previous_apply_sha=""
    if [[ -f "${TRANSMISSION_APPLY_SHA_FILE}" ]]; then
      previous_apply_sha="$(tr -d '\r\n' < "${TRANSMISSION_APPLY_SHA_FILE}")"
    fi

    if [[ "${tracker_sha}" != "${previous_apply_sha}" ]]; then
      mapfile -t torrent_ids < <(
        transmission-remote 127.0.0.1:9091 -n "${transmission_auth}" -l 2>/dev/null \
          | awk '
              NR <= 1 { next }
              $1 == "Sum:" { next }
              {
                gsub(/\*/, "", $1);
                if ($1 ~ /^[0-9]+$/) {
                  print $1;
                }
              }
            '
      )

      if [[ "${#torrent_ids[@]}" -gt 0 ]]; then
        while IFS= read -r tracker; do
          [[ -n "${tracker}" ]] || continue
          for torrent_id in "${torrent_ids[@]}"; do
            transmission-remote 127.0.0.1:9091 -n "${transmission_auth}" -t "${torrent_id}" -td "${tracker}" >/dev/null 2>&1 || true
          done
        done < "${TRACKER_FILE}"

        for torrent_id in "${torrent_ids[@]}"; do
          transmission-remote 127.0.0.1:9091 -n "${transmission_auth}" -t "${torrent_id}" --reannounce >/dev/null 2>&1 || true
        done
      fi

      printf '%s\n' "${tracker_sha}" > "${TRANSMISSION_APPLY_SHA_FILE}"
    fi
  else
    update_transmission_settings_file
  fi
fi

log "bt trackers refreshed: ${tracker_count} entries"
