#!/bin/bash
# ============================================================================
# OpenClaw Key Vault Secrets Setup Script
# ============================================================================
# Populates Azure Key Vault with required secrets for OpenClaw
# Usage: ./setup-secrets.sh <key-vault-name> [options]
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script configuration
KEY_VAULT_NAME="${1:-}"
INTERACTIVE=true
ENV_FILE=""

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_help() {
    cat << EOF
OpenClaw Key Vault Secrets Setup

Usage: $(basename "$0") <KEY_VAULT_NAME> [OPTIONS]

Arguments:
  KEY_VAULT_NAME    Name of the Azure Key Vault

Options:
  -f, --file FILE   Read secrets from .env file
  -n, --non-interactive   Don't prompt for input
  -h, --help        Show this help message

Examples:
  $(basename "$0") openclaw-kv-dev
  $(basename "$0") openclaw-kv-prod --file secrets.env
  $(basename "$0") openclaw-kv-dev --non-interactive

Secrets File Format (.env):
  ANTHROPIC_API_KEY=sk-ant-...
  GATEWAY_TOKEN=abc123...
  TELEGRAM_BOT_TOKEN=123456:ABC...

EOF
}

check_prerequisites() {
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi

    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Run: az login"
        exit 1
    fi
}

validate_key_vault() {
    log_info "Validating Key Vault: $KEY_VAULT_NAME"

    if ! az keyvault show --name "$KEY_VAULT_NAME" &> /dev/null; then
        log_error "Key Vault not found: $KEY_VAULT_NAME"
        log_error "Make sure the Key Vault exists and you have access."
        exit 1
    fi

    log_success "Key Vault validated"
}

set_secret() {
    local name="$1"
    local value="$2"
    local description="${3:-}"

    if [[ -z "$value" ]]; then
        log_warning "Skipping empty secret: $name"
        return
    fi

    log_info "Setting secret: $name"

    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "$name" \
        --value "$value" \
        --description "$description" \
        --output none

    log_success "Secret set: $name"
}

prompt_secret() {
    local name="$1"
    local description="$2"
    local required="${3:-false}"
    local default_value="${4:-}"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$name${NC}"
    echo -e "  $description"
    if [[ "$required" == "true" ]]; then
        echo -e "  ${RED}(Required)${NC}"
    else
        echo -e "  ${YELLOW}(Optional - press Enter to skip)${NC}"
    fi
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local value=""
    read -sp "Enter value: " value
    echo ""

    if [[ -z "$value" && -n "$default_value" ]]; then
        value="$default_value"
        log_info "Using default/generated value"
    fi

    if [[ -z "$value" ]]; then
        if [[ "$required" == "true" ]]; then
            log_error "This secret is required!"
            return 1
        fi
        return 0
    fi

    set_secret "$name" "$value" "$description"
}

generate_gateway_token() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 32
    else
        head -c 32 /dev/urandom | xxd -p -c 64
    fi
}

load_from_env_file() {
    local env_file="$1"

    if [[ ! -f "$env_file" ]]; then
        log_error "Environment file not found: $env_file"
        exit 1
    fi

    log_info "Loading secrets from: $env_file"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ -z "$key" || "$key" =~ ^# ]] && continue

        # Remove quotes from value
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        # Map env var names to Key Vault secret names
        case "$key" in
            ANTHROPIC_API_KEY)
                set_secret "anthropic-api-key" "$value" "Anthropic API Key"
                ;;
            GATEWAY_TOKEN)
                set_secret "gateway-token" "$value" "Gateway authentication token"
                ;;
            TELEGRAM_BOT_TOKEN)
                set_secret "telegram-bot-token" "$value" "Telegram Bot API token"
                ;;
            SLACK_BOT_TOKEN)
                set_secret "slack-bot-token" "$value" "Slack Bot OAuth token"
                ;;
            SLACK_APP_TOKEN)
                set_secret "slack-app-token" "$value" "Slack App-level token"
                ;;
            TEAMS_APP_ID)
                set_secret "teams-app-id" "$value" "Microsoft Teams App ID"
                ;;
            TEAMS_APP_PASSWORD)
                set_secret "teams-app-password" "$value" "Microsoft Teams App Password"
                ;;
            DISCORD_BOT_TOKEN)
                set_secret "discord-bot-token" "$value" "Discord Bot token"
                ;;
            *)
                # Set any other secrets as-is
                set_secret "${key,,}" "$value" "Custom secret"
                ;;
        esac
    done < "$env_file"

    log_success "Secrets loaded from file"
}

interactive_setup() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           OpenClaw Secrets Setup (Interactive)                ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Key Vault: $KEY_VAULT_NAME"
    echo ""

    # Required secrets
    echo -e "\n${GREEN}=== Required Secrets ===${NC}\n"

    prompt_secret "anthropic-api-key" \
        "Your Anthropic API key for Claude access.\n  Get one at: https://console.anthropic.com/settings/keys" \
        "true"

    # Generate gateway token
    local gateway_token
    gateway_token=$(generate_gateway_token)
    echo ""
    log_info "Generating gateway token..."
    set_secret "gateway-token" "$gateway_token" "Gateway authentication token"
    echo ""
    echo -e "${GREEN}Gateway token generated and saved!${NC}"
    echo -e "${YELLOW}Save this token for client configuration:${NC}"
    echo -e "${CYAN}$gateway_token${NC}"
    echo ""

    # Optional secrets
    echo -e "\n${YELLOW}=== Optional Secrets (Channel Integrations) ===${NC}\n"

    prompt_secret "telegram-bot-token" \
        "Telegram Bot API token.\n  Create a bot: https://t.me/BotFather" \
        "false"

    prompt_secret "slack-bot-token" \
        "Slack Bot OAuth token (xoxb-...).\n  Create app: https://api.slack.com/apps" \
        "false"

    prompt_secret "slack-app-token" \
        "Slack App-level token (xapp-...).\n  For Socket Mode connections" \
        "false"

    prompt_secret "teams-app-id" \
        "Microsoft Teams App ID.\n  From Azure Bot registration" \
        "false"

    prompt_secret "teams-app-password" \
        "Microsoft Teams App Password.\n  From Azure Bot registration" \
        "false"

    prompt_secret "discord-bot-token" \
        "Discord Bot token.\n  Create app: https://discord.com/developers/applications" \
        "false"

    echo ""
    log_success "Secrets setup complete!"
}

list_secrets() {
    log_info "Current secrets in Key Vault:"
    echo ""

    az keyvault secret list \
        --vault-name "$KEY_VAULT_NAME" \
        --query "[].{Name:name, Enabled:attributes.enabled}" \
        --output table
}

# ============================================================================
# MAIN
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                ENV_FILE="$2"
                INTERACTIVE=false
                shift 2
                ;;
            -n|--non-interactive)
                INTERACTIVE=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$KEY_VAULT_NAME" ]]; then
                    KEY_VAULT_NAME="$1"
                fi
                shift
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    if [[ -z "$KEY_VAULT_NAME" ]]; then
        log_error "Key Vault name is required"
        show_help
        exit 1
    fi

    check_prerequisites
    validate_key_vault

    if [[ -n "$ENV_FILE" ]]; then
        load_from_env_file "$ENV_FILE"
    elif [[ "$INTERACTIVE" == "true" ]]; then
        interactive_setup
    else
        log_error "No secrets source specified. Use --file or run interactively."
        exit 1
    fi

    echo ""
    list_secrets
    echo ""
    log_success "All done! Your OpenClaw secrets are configured."
}

main "$@"
