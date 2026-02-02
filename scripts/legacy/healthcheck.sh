#!/bin/bash
# OpenClaw Health Check Script
# Used by Docker HEALTHCHECK and Azure Container Apps probes

set -e

GATEWAY_PORT="${GATEWAY_PORT:-18789}"
HEALTH_ENDPOINT="http://localhost:${GATEWAY_PORT}/health"
TIMEOUT=5

# Try to reach the health endpoint
response=$(curl -sf --max-time ${TIMEOUT} "${HEALTH_ENDPOINT}" 2>/dev/null) || {
    echo "Health check failed: Gateway not responding on port ${GATEWAY_PORT}"
    exit 1
}

# Check if response indicates healthy status
if echo "${response}" | grep -qi "ok\|healthy\|running"; then
    echo "Health check passed"
    exit 0
fi

# If no explicit health endpoint, check if process is running
if pgrep -f "openclaw" > /dev/null; then
    echo "Health check passed: OpenClaw process running"
    exit 0
fi

echo "Health check failed: Unknown state"
exit 1
