#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="/data/config/openclaw.json"

# Ensure directories exist
mkdir -p /data/config /data/workspace /data/logs /data/cache

# Create minimal config if missing (best-effort self-healing)
if [[ ! -f "$CONFIG_PATH" ]]; then
  cat > "$CONFIG_PATH" <<'EOF'
{
  "gateway": {
    "mode": "local",
    "bind": "loopback"
  },
  "agents": {
    "defaults": {
      "workspace": "/data/workspace"
    }
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
