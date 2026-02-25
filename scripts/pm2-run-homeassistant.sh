#!/usr/bin/env bash
set -euo pipefail

UV_BIN="/root/.local/bin/uv"
HASS_BIN="/root/.local/bin/hass"
CONFIG_DIR="/opt/data/homeassistant"
RUNTIME_DIR="/opt/apps/homeassistant/current"
LOG_DIR="/opt/logs/homeassistant"
HASS_NICE_LEVEL="${HASS_NICE_LEVEL:-10}"
HASS_OOM_SCORE_ADJ="${HASS_OOM_SCORE_ADJ:-300}"
HASS_ENABLE_CGROUP_GUARD="${HASS_ENABLE_CGROUP_GUARD:-1}"
HASS_CGROUP_PATH="${HASS_CGROUP_PATH:-/sys/fs/cgroup/opt-homeassistant}"
HASS_MEMORY_HIGH_BYTES="${HASS_MEMORY_HIGH_BYTES:-1572864000}"
HASS_MEMORY_MAX_BYTES="${HASS_MEMORY_MAX_BYTES:-2147483648}"
HASS_MEMORY_SWAP_MAX_BYTES="${HASS_MEMORY_SWAP_MAX_BYTES:-0}"

mkdir -p "$CONFIG_DIR" "$RUNTIME_DIR" "$LOG_DIR"
ln -sfn "$LOG_DIR" "${RUNTIME_DIR}/logs"

if [[ ! -x "$HASS_BIN" ]]; then
  if [[ ! -x "$UV_BIN" ]]; then
    echo "ERROR: uv not found at ${UV_BIN}; run /opt/ops/scripts/uv-install-homeassistant.sh first" >&2
    exit 1
  fi
  "$UV_BIN" tool install --upgrade homeassistant
fi

write_cgroup_value() {
  local file="$1"
  local value="$2"
  if [[ ! -e "$file" ]]; then
    return 0
  fi
  if ! printf '%s' "$value" > "$file" 2>/dev/null; then
    echo "WARN: failed to set ${file}=${value}" >&2
  fi
}

setup_cgroup_guard() {
  if [[ "$HASS_ENABLE_CGROUP_GUARD" != "1" ]]; then
    return 0
  fi
  if [[ ! -d /sys/fs/cgroup ]]; then
    echo "WARN: cgroupfs not available; skip HomeAssistant memory guard" >&2
    return 0
  fi
  if ! mkdir -p "$HASS_CGROUP_PATH" 2>/dev/null; then
    echo "WARN: cannot create cgroup path ${HASS_CGROUP_PATH}; skip memory guard" >&2
    return 0
  fi

  write_cgroup_value "${HASS_CGROUP_PATH}/memory.high" "$HASS_MEMORY_HIGH_BYTES"
  write_cgroup_value "${HASS_CGROUP_PATH}/memory.max" "$HASS_MEMORY_MAX_BYTES"
  write_cgroup_value "${HASS_CGROUP_PATH}/memory.swap.max" "$HASS_MEMORY_SWAP_MAX_BYTES"
  write_cgroup_value "${HASS_CGROUP_PATH}/memory.oom.group" "1"

  if [[ -w "${HASS_CGROUP_PATH}/cgroup.procs" ]]; then
    if ! printf '%s' "$$" > "${HASS_CGROUP_PATH}/cgroup.procs" 2>/dev/null; then
      echo "WARN: cannot move HomeAssistant runner into ${HASS_CGROUP_PATH}" >&2
    fi
  fi

  echo "INFO: HomeAssistant cgroup guard enabled: high=${HASS_MEMORY_HIGH_BYTES} max=${HASS_MEMORY_MAX_BYTES} swap.max=${HASS_MEMORY_SWAP_MAX_BYTES}" >&2
}

set_oom_bias() {
  if [[ -w /proc/self/oom_score_adj ]]; then
    if ! printf '%s' "$HASS_OOM_SCORE_ADJ" > /proc/self/oom_score_adj 2>/dev/null; then
      echo "WARN: cannot set oom_score_adj=${HASS_OOM_SCORE_ADJ}" >&2
    fi
  fi
}

setup_cgroup_guard
set_oom_bias

if command -v ionice >/dev/null 2>&1; then
  exec ionice -c3 nice -n "$HASS_NICE_LEVEL" "$HASS_BIN" -c "$CONFIG_DIR"
fi

exec nice -n "$HASS_NICE_LEVEL" "$HASS_BIN" -c "$CONFIG_DIR"
