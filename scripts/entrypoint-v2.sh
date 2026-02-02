#!/usr/bin/env bash
# ============================================================================
# Enhanced OpenClaw Container Entrypoint
# ============================================================================
# Reads mandatory configuration from Key Vault / environment variables,
# generates configuration files, validates setup, then starts the gateway.
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

CONFIG_DIR="${OPENCLAW_CONFIG:-/data/config}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE:-/data/workspace}"
LOGS_DIR="${OPENCLAW_LOGS:-/data/logs}"
CACHE_DIR="${OPENCLAW_CACHE:-/data/cache}"
STATE_DIR="${OPENCLAW_STATE_DIR:-/home/openclaw/.openclaw}"

# Gateway config must be in workspace directory for openclaw to find it
GATEWAY_CONFIG="${WORKSPACE_DIR}/openclaw.json"
CHANNELS_CONFIG="${WORKSPACE_DIR}/channels.json"

# Defaults
GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-0.0.0.0}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
LOG_LEVEL="${OPENCLAW_LOG_LEVEL:-info}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-120}"  # seconds

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
}

# ============================================================================
# SETUP & VALIDATION
# ============================================================================

ensure_directories() {
    log_info "Ensuring directories exist..."
    log_info "  Current UID: $(id -u)"
    log_info "  Current user: $(whoami)"
    
    # Create parent directory first
    mkdir -p "$(dirname "$CONFIG_DIR")"
    mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR" "$LOGS_DIR" "$CACHE_DIR"
    
    # Fix ownership and permissions
    # When EmptyDir volumes are mounted in Azure Container Apps, they're often owned by root
    # We need to make them writable by the openclaw user (UID 1001, GID 1001)
    
    # Check if we're running as root
    if [[ "$(id -u)" == "0" ]]; then
        log_info "Running as root, fixing directory ownership to UID 1001:GID 1001..."
        
        # Fix /data and subdirectories
        chown -R 1001:1001 /data && log_success "Changed /data ownership to 1001:1001"
        chmod -R 755 /data && log_success "Changed /data permissions to 755"
        
        # Verify the fix worked
        if [[ -w "$WORKSPACE_DIR" ]]; then
            log_success "Directory ownership fixed and verified as writable"
        else
            log_warn "Directory permissions changed but still reports not writable"
            # List the actual permissions for debugging
            ls -ld "$WORKSPACE_DIR" 2>/dev/null || true
        fi
    else
        log_error "Not running as root (UID $(id -u)), cannot fix directory ownership"
        return 1
    fi
    
    log_success "Directories ready"
}

read_env_or_keyvault() {
    local env_var="$1"
    local kv_secret="$2"
    local required="${3:-false}"

    # Try environment variable first
    local value="${!env_var:-}"

    # If not set and we can access Key Vault, try that
    if [[ -z "$value" ]] && command -v az &> /dev/null; then
        if [[ -n "${AZURE_KEYVAULT_NAME:-}" ]]; then
            log_info "Reading $kv_secret from Key Vault..."
            value=$(az keyvault secret show \
                --vault-name "$AZURE_KEYVAULT_NAME" \
                --name "$kv_secret" \
                --query value \
                --output tsv 2>/dev/null || echo "")
        fi
    fi

    if [[ -z "$value" ]]; then
        if [[ "$required" == "true" ]]; then
            log_error "Required configuration missing: $env_var (or $kv_secret in Key Vault)"
            return 1
        else
            log_warn "Optional configuration not set: $env_var"
            return 0
        fi
    fi

    echo "$value"
}

generate_gateway_token() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    else
        head -c 32 /dev/urandom | xxd -p -c 64
    fi
}

validate_configuration() {
    log_info "Validating configuration..."

    # Just check directories exist - don't fail on permissions
    # The chown in ensure_directories should have fixed them
    for dir in "$CONFIG_DIR" "$WORKSPACE_DIR" "$LOGS_DIR" "$CACHE_DIR"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Directory does not exist: $dir"
            return 1
        fi
    done

    # Don't check port - might not be available in container
    log_success "Configuration validated"
}

# ============================================================================
# CONFIG GENERATION
# ============================================================================

generate_gateway_config() {
    log_info "Generating gateway configuration..."

    # Read required secrets
    local gateway_token
    gateway_token=$(read_env_or_keyvault "GATEWAY_TOKEN" "gateway-token" false)

    # Generate token if not provided
    if [[ -z "$gateway_token" ]]; then
        log_info "Generating gateway token (no token provided)..."
        gateway_token=$(generate_gateway_token)
        log_warn "Generated token - save this for client configuration: $gateway_token"
    fi

    # Build auth block
    local auth_block=""
    if [[ -n "$gateway_token" ]]; then
        auth_block="\"auth\": {\"mode\": \"token\", \"token\": \"${gateway_token}\"}"
    else
        auth_block="\"auth\": {\"mode\": \"anonymous\"}"
    fi

    # Build gateway config
    local model_primary="${OPENCLAW_MODEL_PRIMARY:-github-copilot/claude-haiku-4.5}"
    local model_backup="${OPENCLAW_MODEL_BACKUP:-}"

    # Create gateway configuration file
    cat > "$GATEWAY_CONFIG" <<'EOFCONFIG'
{
  "gateway": {
    "mode": "local",
    "bind": "OPENCLAW_GATEWAY_BIND",
    "port": OPENCLAW_GATEWAY_PORT,
    "logLevel": "OPENCLAW_LOG_LEVEL",
    "cors": {
      "enabled": true,
      "origins": ["*"],
      "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
      "headers": ["Content-Type", "Authorization", "X-Gateway-Token"]
    },
    OPENCLAW_AUTH_BLOCK
  },
  "agents": {
    "defaults": {
      "workspace": "OPENCLAW_WORKSPACE_DIR",
      "model": {
        "primary": "OPENCLAW_MODEL_PRIMARY"
        OPENCLAW_MODEL_BACKUP_BLOCK
      }
    }
  },
  "workspace": "OPENCLAW_WORKSPACE_DIR",
  "channels": "OPENCLAW_CHANNELS_CONFIG",
  "browser": {
    "enabled": true,
    "executablePath": "/usr/bin/chromium",
    "headless": true,
    "args": [
      "--no-sandbox",
      "--disable-setuid-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--disable-software-rasterizer"
    ]
  },
  "memory": {
    "enabled": true
  },
  "logging": {
    "format": "json",
    "timestamps": true,
    "includeRequestId": true,
    "redactSecrets": true,
    "level": "OPENCLAW_LOG_LEVEL"
  }
}
EOFCONFIG

    # Apply substitutions
    sed -i "s|OPENCLAW_GATEWAY_BIND|$GATEWAY_BIND|g" "$GATEWAY_CONFIG"
    sed -i "s|OPENCLAW_GATEWAY_PORT|$GATEWAY_PORT|g" "$GATEWAY_CONFIG"
    sed -i "s|OPENCLAW_LOG_LEVEL|$LOG_LEVEL|g" "$GATEWAY_CONFIG"
    sed -i "s|OPENCLAW_WORKSPACE_DIR|$WORKSPACE_DIR|g" "$GATEWAY_CONFIG"
    sed -i "s|OPENCLAW_MODEL_PRIMARY|$model_primary|g" "$GATEWAY_CONFIG"
    # Note: OPENCLAW_AUTH_BLOCK is unquoted in template, so replace without quotes
    sed -i "s|OPENCLAW_AUTH_BLOCK|$auth_block|g" "$GATEWAY_CONFIG"

    # Handle optional backup model (also unquoted in template)
    if [[ -n "$model_backup" ]]; then
        sed -i "s|OPENCLAW_MODEL_BACKUP_BLOCK|, \"backup\": \"$model_backup\"|g" "$GATEWAY_CONFIG"
    else
        sed -i 's|OPENCLAW_MODEL_BACKUP_BLOCK||g' "$GATEWAY_CONFIG"
    fi

    # Handle channels config
    if [[ -f "$CHANNELS_CONFIG" ]]; then
        sed -i "s|\"OPENCLAW_CHANNELS_CONFIG\"|\"$CHANNELS_CONFIG\"|g" "$GATEWAY_CONFIG"
    else
        sed -i 's|"OPENCLAW_CHANNELS_CONFIG"|{}|g' "$GATEWAY_CONFIG"
    fi

    log_success "Gateway configuration generated: $GATEWAY_CONFIG"
}

generate_channels_config() {
    log_info "Generating channels configuration..."

    # Only generate if file doesn't exist
    if [[ -f "$CHANNELS_CONFIG" ]]; then
        log_info "Channels config already exists, skipping generation"
        return
    fi

    # Try to read channel configs from environment/Key Vault
    local teams_config=""
    local slack_config=""
    local telegram_config=""

    # Teams configuration
    if [[ -n "${TEAMS_APP_ID:-}" ]]; then
        local teams_app_id="$TEAMS_APP_ID"
        local teams_app_password="${TEAMS_APP_PASSWORD:-}"
        
        if [[ -z "$teams_app_password" ]] && [[ -n "${AZURE_KEYVAULT_NAME:-}" ]]; then
            teams_app_password=$(az keyvault secret show \
                --vault-name "$AZURE_KEYVAULT_NAME" \
                --name "teams-app-password" \
                --query value \
                --output tsv 2>/dev/null || echo "")
        fi

        if [[ -n "$teams_app_password" ]]; then
            teams_config=$(cat <<EOF
  "teams": {
    "appId": "$teams_app_id",
    "appPassword": "$teams_app_password",
    "enabled": true
  }
EOF
            )
        fi
    fi

    # Slack configuration
    if [[ -n "${SLACK_BOT_TOKEN:-}" ]]; then
        slack_config=$(cat <<EOF
  "slack": {
    "botToken": "$SLACK_BOT_TOKEN",
    "enabled": true
  }
EOF
        )
    fi

    # Telegram configuration
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        telegram_config=$(cat <<EOF
  "telegram": {
    "botToken": "$TELEGRAM_BOT_TOKEN",
    "enabled": true
  }
EOF
        )
    fi

    # Build channels config
    local channels_json="{"
    if [[ -n "$teams_config" ]]; then
        channels_json="${channels_json}${teams_config},"
    fi
    if [[ -n "$slack_config" ]]; then
        channels_json="${channels_json}${slack_config},"
    fi
    if [[ -n "$telegram_config" ]]; then
        channels_json="${channels_json}${telegram_config},"
    fi
    
    # Remove trailing comma if configs exist
    if [[ "$channels_json" != "{" ]]; then
        channels_json="${channels_json%,}"
    fi
    channels_json="${channels_json}}"

    echo "$channels_json" > "$CHANNELS_CONFIG"
    log_success "Channels configuration generated: $CHANNELS_CONFIG"
}

# ============================================================================
# STARTUP
# ============================================================================

start_gateway() {
    log_info "Starting OpenClaw gateway..."
    log_info "  Bind: $GATEWAY_BIND"
    log_info "  Port: $GATEWAY_PORT"
    log_info "  Config file: $GATEWAY_CONFIG"
    log_info "  State dir: $STATE_DIR"
    log_info "  Workspace: $WORKSPACE_DIR"
    echo ""

    # Check config exists
    if [[ ! -f "$GATEWAY_CONFIG" ]]; then
        log_error "Gateway config not found: $GATEWAY_CONFIG"
        return 1
    fi

    # Copy config to the openclaw home directory where it expects it
    local OPENCLAW_HOME="/home/openclaw/.openclaw"
    mkdir -p "$OPENCLAW_HOME"
    cp "$GATEWAY_CONFIG" "$OPENCLAW_HOME/openclaw.json"
    if [[ -f "$CHANNELS_CONFIG" ]]; then
        cp "$CHANNELS_CONFIG" "$OPENCLAW_HOME/channels.json"
    fi
    chown -R 1001:1001 "$OPENCLAW_HOME"
    log_success "Config copied to $OPENCLAW_HOME/openclaw.json"

    # Switch to non-root user for security (openclaw user, UID 1001)
    # Run gateway in foreground (dumb-init handles signals)
    # 
    # IMPORTANT: Use 'su' without '-' to avoid login shell which resets environment
    # The login shell (-) sources profile scripts that may clear our env vars
    # 
    # Also explicitly pass --config to ensure OpenClaw finds the config file
    
    cd "${WORKSPACE_DIR}"
    
    # Export environment variables that openclaw needs
    export HOME="/home/openclaw"
    export OPENCLAW_STATE_DIR="${OPENCLAW_HOME}"
    export OPENCLAW_GATEWAY_PORT="${GATEWAY_PORT}"
    
    log_info "Environment for openclaw:"
    log_info "  HOME=$HOME"
    log_info "  OPENCLAW_STATE_DIR=$OPENCLAW_STATE_DIR"
    log_info "  Config file: ${OPENCLAW_HOME}/openclaw.json"
    
    # Verify config exists before starting
    if [[ ! -f "${OPENCLAW_HOME}/openclaw.json" ]]; then
        log_error "Config file missing at ${OPENCLAW_HOME}/openclaw.json"
        exit 1
    fi
    log_success "Config file verified"
    
    # Debug: Show what config file contains
    log_info "Config file contents (first 20 lines):"
    head -20 "${OPENCLAW_HOME}/openclaw.json" || true
    echo ""
    
    # Run as openclaw user
    # OpenClaw looks for config at ~/.openclaw/openclaw.json (which is /home/openclaw/.openclaw/openclaw.json)
    exec su openclaw -s /bin/bash -c "
        cd '${WORKSPACE_DIR}'
        export HOME='/home/openclaw'
        export OPENCLAW_STATE_DIR='${OPENCLAW_HOME}'
        echo 'DEBUG: Running as user:' \$(whoami)
        echo 'DEBUG: HOME='\$HOME
        echo 'DEBUG: OPENCLAW_STATE_DIR='\$OPENCLAW_STATE_DIR
        echo 'DEBUG: Config exists:' && ls -la '${OPENCLAW_HOME}/openclaw.json' 2>&1 || echo 'Config NOT FOUND'
        echo 'DEBUG: Starting gateway...'
        openclaw gateway run --verbose --bind lan --port '${GATEWAY_PORT}'
    "
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_info "OpenClaw Container Entrypoint v2"
    log_info "Starting up..."
    echo ""

    # Setup
    ensure_directories
    validate_configuration || exit 1

    # Generate configuration
    generate_gateway_config
    generate_channels_config

    # Start
    echo ""
    start_gateway
}

main "$@"
