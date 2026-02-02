#!/usr/bin/env bash
# ============================================================================
# Grant ACR Pull Permission to Container App Managed Identity
# ============================================================================
# This script grants AcrPull role to the managed identity so it can
# pull images from the Azure Container Registry.
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# CONFIGURATION
# ============================================================================

RESOURCE_GROUP="${1:-}"
ENVIRONMENT="${2:-staging}"
ACR_NAME="${3:-}"
CONTAINER_APP_NAME="openclaw-app-${ENVIRONMENT}"
MANAGED_IDENTITY_NAME="openclaw-identity-${ENVIRONMENT}"

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

show_usage() {
    cat << EOF
Grant ACR Pull Permission to Container App Managed Identity

Usage: $(basename "$0") <resource-group> [environment] [acr-name]

Arguments:
  resource-group    Azure Resource Group name
  environment       Environment name (staging, prod) - default: staging
  acr-name          ACR registry name (e.g., openclawpreacr)

Examples:
  $(basename "$0") openclaw-pre-group
  $(basename "$0") openclaw-pre-group prod myacr
  $(basename "$0") openclaw-pre-group staging openclawpreacr

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource group is required"
        show_usage
        exit 1
    fi

    log_info "Granting ACR pull permission"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Managed Identity: $MANAGED_IDENTITY_NAME"
    log_info "  ACR: $ACR_NAME"
    echo ""

    # Get the managed identity object ID
    log_info "Getting managed identity object ID..."
    IDENTITY_ID=$(az identity show \
        -g "$RESOURCE_GROUP" \
        -n "$MANAGED_IDENTITY_NAME" \
        --query principalId \
        --output tsv 2>/dev/null || echo "")

    if [[ -z "$IDENTITY_ID" ]]; then
        log_error "Could not find managed identity: $MANAGED_IDENTITY_NAME"
        log_info "Try checking if the resource group exists:"
        log_info "  az group show -n $RESOURCE_GROUP"
        log_info "Or listing identities:"
        log_info "  az identity list -g $RESOURCE_GROUP"
        exit 1
    fi

    log_success "Managed Identity ID: $IDENTITY_ID"
    echo ""

    # Get ACR resource ID
    if [[ -n "$ACR_NAME" ]]; then
        log_info "Getting ACR resource ID..."
        ACR_RESOURCE_ID=$(az acr show \
            -n "$ACR_NAME" \
            --query id \
            --output tsv 2>/dev/null || echo "")

        if [[ -z "$ACR_RESOURCE_ID" ]]; then
            log_error "Could not find ACR: $ACR_NAME"
            log_info "Try listing ACRs:"
            log_info "  az acr list"
            exit 1
        fi

        log_success "ACR Resource ID: $ACR_RESOURCE_ID"
        echo ""

    # Grant AcrPull role (safe to run multiple times)
        log_info "Assigning AcrPull role to managed identity..."
        az role assignment create \
            --assignee-object-id "$IDENTITY_ID" \
            --assignee-principal-type ServicePrincipal \
            --role "AcrPull" \
            --scope "$ACR_RESOURCE_ID" \
            --output none 2>&1 || {
            EXIT_CODE=$?
            if [[ $EXIT_CODE -eq 1 ]] && grep -q "RoleAssignmentExists\|already exists" <<< "$OUTPUT" 2>/dev/null; then
                log_warn "Role assignment already exists (this is OK)"
            else
                log_error "Failed to assign role (exit code: $EXIT_CODE)"
                exit 1
            fi
        }

        log_success "AcrPull role assigned!"
    else
        log_warn "ACR name not provided, skipping ACR role assignment"
    fi

    echo ""
    log_success "All permissions granted!"
    echo ""
    echo "Next: Redeploy the Container App:"
    echo "  az deployment group create \\"
    echo "    -g $RESOURCE_GROUP \\"
    echo "    -f bicep/main.bicep \\"
    echo "    -p @bicep/parameters.${ENVIRONMENT}.json \\"
    echo "    -p containerImage=... \\"
    echo "    -p acrName=$ACR_NAME"
    echo ""
}

main "$@"
