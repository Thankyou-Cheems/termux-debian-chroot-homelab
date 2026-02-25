#!/usr/bin/env bash
set -euo pipefail

UV_BIN="${UV_BIN:-/root/.local/bin/uv}"
HASS_BIN="/root/.local/bin/hass"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl not found; install curl first" >&2
  exit 1
fi

if [[ ! -x "$UV_BIN" ]]; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

if [[ ! -x "$UV_BIN" ]]; then
  echo "ERROR: uv install failed: ${UV_BIN}" >&2
  exit 1
fi

"$UV_BIN" tool install --upgrade homeassistant

if [[ -x "$HASS_BIN" ]]; then
  "$HASS_BIN" --version
else
  echo "ERROR: hass binary not found after install: ${HASS_BIN}" >&2
  exit 1
fi
