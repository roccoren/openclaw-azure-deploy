#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="/data/config/openclaw.json"

# Ensure directories exist
mkdir -p /data/config /data/workspace /data/logs /data/cache

# Create minimal config if missing (best-effort self-healing)
if [[ ! -f "$CONFIG_PATH" ]]; then
  GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-loopback}"
  GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
  LOG_LEVEL="${OPENCLAW_LOG_LEVEL:-info}"
  MODEL_PRIMARY="${OPENCLAW_MODEL_PRIMARY:-github-copilot/gpt-5.2-codex}"

  if [[ -n "${GATEWAY_TOKEN:-}" ]]; then
    AUTH_BLOCK="\"auth\": {\"mode\": \"token\", \"token\": \"${GATEWAY_TOKEN}\"}"
  else
    # Generate a token if not provided
    if command -v openssl >/dev/null 2>&1; then
      GENERATED_TOKEN=$(openssl rand -hex 32)
    else
      GENERATED_TOKEN=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
    fi
    AUTH_BLOCK="\"auth\": {\"mode\": \"token\", \"token\": \"${GENERATED_TOKEN}\"}"
  fi

  cat > "$CONFIG_PATH" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "${GATEWAY_BIND}",
    "port": ${GATEWAY_PORT},
    "logLevel": "${LOG_LEVEL}",
    ${AUTH_BLOCK}
  },
  "agents": {
    "defaults": {
      "workspace": "/data/workspace",
      "model": { "primary": "${MODEL_PRIMARY}" }
    }
  },
  "workspace": "/data/workspace",
  "channels": {},
  "memory": {
    "enabled": true
  }
}
EOF
fi

# Start gateway (foreground).
# If config exists, run normally; otherwise allow unconfigured fallback.
if [[ -f "$CONFIG_PATH" ]]; then
  exec openclaw gateway run
else
  exec openclaw gateway run --allow-unconfigured
fi
