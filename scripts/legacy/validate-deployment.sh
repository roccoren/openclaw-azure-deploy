#!/usr/bin/env bash
# ============================================================================
# Pre-Deployment Validator for OpenClaw Azure Deployment
# ============================================================================
# Validates all prerequisites and configuration before deployment
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Tracking
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNINGS=0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNINGS++))
}

section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

show_summary() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Validation Summary${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
    echo -e "${GREEN}Passed:${NC}  $CHECKS_PASSED"
    echo -e "${YELLOW}Warnings:${NC} $CHECKS_WARNINGS"
    echo -e "${RED}Failed:${NC}  $CHECKS_FAILED"
    echo ""

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All validation checks passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Validation failed. Please fix the issues above.${NC}"
        return 1
    fi
}

# ============================================================================
# VALIDATION CHECKS
# ============================================================================

check_prerequisites() {
    section "Checking Prerequisites"

    # Azure CLI
    if command -v az &> /dev/null; then
        check_pass "Azure CLI installed: $(az --version | head -n1)"
    else
        check_fail "Azure CLI not installed. Get it: https://docs.microsoft.com/cli/azure/install-azure-cli"
    fi

    # Docker
    if command -v docker &> /dev/null; then
        check_pass "Docker installed: $(docker --version)"
    else
        check_fail "Docker not installed. Get it: https://docs.docker.com/get-docker"
    fi

    # Git
    if command -v git &> /dev/null; then
        check_pass "Git installed: $(git --version)"
    else
        check_warn "Git not installed (optional for version control)"
    fi

    # jq (for JSON parsing)
    if command -v jq &> /dev/null; then
        check_pass "jq installed (JSON parser)"
    else
        check_warn "jq not installed (optional, useful for JSON validation)"
    fi
}

check_azure_auth() {
    section "Checking Azure Authentication"

    # Check if logged in
    if az account show &> /dev/null; then
        local account_info
        account_info=$(az account show --query "{name:name, id:id}" -o json)
        local account_name
        account_name=$(echo "$account_info" | jq -r '.name' 2>/dev/null || echo "unknown")
        check_pass "Authenticated to Azure: $account_name"
    else
        check_fail "Not authenticated to Azure. Run: az login"
    fi

    # Check subscription
    if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
        az account set --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null || check_fail "Cannot switch to subscription: $AZURE_SUBSCRIPTION_ID"
        check_pass "Using subscription: $AZURE_SUBSCRIPTION_ID"
    else
        local default_sub
        default_sub=$(az account show --query id -o tsv 2>/dev/null || echo "unknown")
        check_warn "No AZURE_SUBSCRIPTION_ID set, using default: $default_sub"
    fi
}

check_resource_group() {
    section "Checking Resource Group"

    if [[ -z "${AZURE_RESOURCE_GROUP:-}" ]]; then
        check_warn "AZURE_RESOURCE_GROUP not set (needed for deployment)"
        return
    fi

    if az group show -n "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        check_pass "Resource group exists: $AZURE_RESOURCE_GROUP"
    else
        check_warn "Resource group does not exist: $AZURE_RESOURCE_GROUP (will be created during deployment)"
    fi
}

check_keyvault() {
    section "Checking Key Vault"

    if [[ -z "${AZURE_KEYVAULT_NAME:-}" ]]; then
        check_warn "AZURE_KEYVAULT_NAME not set (secrets will be read from env vars)"
        return
    fi

    if az keyvault show -n "$AZURE_KEYVAULT_NAME" &> /dev/null; then
        check_pass "Key Vault exists: $AZURE_KEYVAULT_NAME"
        
        # Check secrets
        local secrets
        secrets=$(az keyvault secret list --vault-name "$AZURE_KEYVAULT_NAME" --query "length([*])" -o tsv)
        check_pass "Key Vault has $secrets secrets"
        
        # Check critical secrets
        if az keyvault secret show --vault-name "$AZURE_KEYVAULT_NAME" -n "gateway-token" &> /dev/null; then
            check_pass "gateway-token secret exists"
        else
            check_warn "gateway-token secret missing (will be generated at startup)"
        fi
    else
        check_fail "Key Vault not found: $AZURE_KEYVAULT_NAME"
    fi
}

check_docker_image() {
    section "Checking Docker Image"

    if [[ -z "${DOCKER_IMAGE:-}" ]]; then
        check_warn "DOCKER_IMAGE not set (using default openclaw:latest)"
        return
    fi

    # Check if image exists locally
    if docker image inspect "$DOCKER_IMAGE" &> /dev/null; then
        check_pass "Docker image exists locally: $DOCKER_IMAGE"
    else
        check_warn "Docker image not found locally: $DOCKER_IMAGE (will need to be built)"
    fi
}

check_bicep_files() {
    section "Checking Bicep Files"

    local bicep_dir="${BICEP_DIR:-.}/bicep"

    if [[ ! -d "$bicep_dir" ]]; then
        check_fail "Bicep directory not found: $bicep_dir"
        return
    fi

    # Check main.bicep
    if [[ -f "$bicep_dir/main.bicep" ]]; then
        check_pass "main.bicep found"
    else
        check_fail "main.bicep not found: $bicep_dir/main.bicep"
    fi

    # Check parameters
    if [[ -f "$bicep_dir/parameters.bicep" ]]; then
        check_pass "parameters.bicep found"
    else
        check_fail "parameters.bicep not found: $bicep_dir/parameters.bicep"
    fi

    # Check environment parameters
    if [[ -f "$bicep_dir/parameters.prod.json" ]]; then
        check_pass "parameters.prod.json found"
    else
        check_warn "parameters.prod.json not found (production parameters)"
    fi

    if [[ -f "$bicep_dir/parameters.dev.json" ]]; then
        check_pass "parameters.dev.json found"
    else
        check_warn "parameters.dev.json not found (development parameters)"
    fi
}

check_config_files() {
    section "Checking Configuration Files"

    local config_dir="${CONFIG_DIR:-.}/config"

    if [[ ! -d "$config_dir" ]]; then
        check_fail "Config directory not found: $config_dir"
        return
    fi

    # Check gateway config
    if [[ -f "$config_dir/gateway-config.json" ]]; then
        check_pass "gateway-config.json found"
        
        # Try to validate JSON
        if command -v jq &> /dev/null; then
            if jq empty "$config_dir/gateway-config.json" 2>/dev/null; then
                check_pass "gateway-config.json is valid JSON"
            else
                check_fail "gateway-config.json is invalid JSON"
            fi
        fi
    else
        check_warn "gateway-config.json not found (will be generated at startup)"
    fi

    # Check channels config
    if [[ -f "$config_dir/channels.json" ]]; then
        check_pass "channels.json found"
        
        if command -v jq &> /dev/null; then
            if jq empty "$config_dir/channels.json" 2>/dev/null; then
                check_pass "channels.json is valid JSON"
            else
                check_fail "channels.json is invalid JSON"
            fi
        fi
    else
        check_warn "channels.json not found (will be generated at startup)"
    fi
}

check_scripts() {
    section "Checking Scripts"

    local scripts_dir="${SCRIPTS_DIR:-.}/scripts"

    if [[ ! -d "$scripts_dir" ]]; then
        check_fail "Scripts directory not found: $scripts_dir"
        return
    fi

    # Check key scripts
    local required_scripts=(
        "entrypoint-v2.sh"
        "deploy.sh"
        "build-image.sh"
        "setup-secrets.sh"
        "healthcheck.sh"
    )

    for script in "${required_scripts[@]}"; do
        if [[ -f "$scripts_dir/$script" ]]; then
            if [[ -x "$scripts_dir/$script" ]]; then
                check_pass "$script found and executable"
            else
                check_warn "$script found but not executable"
            fi
        else
            check_warn "$script not found"
        fi
    done
}

check_dockerfile() {
    section "Checking Dockerfile"

    if [[ -f "Dockerfile" ]]; then
        check_pass "Dockerfile found"
        
        # Check for critical components
        if grep -q "Node.js" Dockerfile; then
            check_pass "Dockerfile includes Node.js"
        else
            check_warn "Dockerfile doesn't mention Node.js (check manually)"
        fi

        if grep -q "chromium" Dockerfile; then
            check_pass "Dockerfile includes Chromium"
        else
            check_warn "Dockerfile doesn't include Chromium (browser automation will fail)"
        fi

        if grep -q "dumb-init" Dockerfile; then
            check_pass "Dockerfile uses dumb-init (signal handling)"
        else
            check_warn "Dockerfile doesn't use dumb-init (signal handling may be broken)"
        fi
    else
        check_fail "Dockerfile not found"
    fi
}

check_environment_vars() {
    section "Checking Environment Variables"

    echo "Required environment variables:"
    
    local required_vars=(
        "AZURE_SUBSCRIPTION_ID"
        "AZURE_RESOURCE_GROUP"
        "AZURE_KEYVAULT_NAME"
        "DOCKER_IMAGE"
    )

    for var in "${required_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            check_pass "$var = ${!var}"
        else
            check_warn "$var not set"
        fi
    done

    echo ""
    echo "Optional environment variables:"
    
    local optional_vars=(
        "OPENCLAW_MODEL_PRIMARY"
        "OPENCLAW_LOG_LEVEL"
        "GATEWAY_TOKEN"
        "TEAMS_APP_ID"
        "SLACK_BOT_TOKEN"
    )

    for var in "${optional_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            check_pass "$var is set"
        else
            check_warn "$var not set (optional)"
        fi
    done
}

check_connectivity() {
    section "Checking Connectivity"

    # Check internet connectivity
    if ping -c 1 8.8.8.8 &> /dev/null; then
        check_pass "Internet connectivity OK"
    else
        check_warn "Cannot reach public DNS (may affect Azure operations)"
    fi

    # Check Azure endpoints
    if timeout 5 bash -c 'exec 3<>/dev/tcp/management.azure.com/443' &> /dev/null; then
        check_pass "Can reach Azure management endpoint"
    else
        check_warn "Cannot reach Azure management (may indicate connectivity issues)"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  OpenClaw Azure Deployment - Pre-Deployment Validator     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Run checks
    check_prerequisites
    check_azure_auth
    check_resource_group
    check_keyvault
    check_docker_image
    check_bicep_files
    check_config_files
    check_scripts
    check_dockerfile
    check_environment_vars
    check_connectivity

    # Summary
    show_summary
}

main "$@"
