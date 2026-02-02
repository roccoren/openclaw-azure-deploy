#!/bin/bash
# ============================================================================
# OpenClaw Azure Deployment Script
# ============================================================================
# Full deployment workflow for OpenClaw on Azure Container Apps
# Usage: ./deploy.sh [dev|staging|prod] [options]
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BICEP_DIR="${PROJECT_DIR}/bicep"

# Default values
ENVIRONMENT="${1:-dev}"
RESOURCE_GROUP=""
LOCATION="westus2"
BASE_NAME="openclaw"
ACR_NAME=""
SKIP_BUILD=false
SKIP_SECRETS=false
DRY_RUN=false

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    cat << EOF
OpenClaw Azure Deployment Script

Usage: $(basename "$0") [ENVIRONMENT] [OPTIONS]

Environments:
  dev         Development environment (default)
  staging     Staging environment
  prod        Production environment

Options:
  -g, --resource-group NAME   Resource group name (default: openclaw-{env}-rg)
  -l, --location REGION       Azure region (default: westus2)
  -n, --name NAME             Base name for resources (default: openclaw)
  -r, --registry NAME         ACR name (default: {name}acr{env})
  --skip-build                Skip container image build
  --skip-secrets              Skip Key Vault secrets setup
  --dry-run                   Show what would be done without executing
  -h, --help                  Show this help message

Examples:
  $(basename "$0") dev
  $(basename "$0") prod -g my-rg -l eastus2
  $(basename "$0") staging --skip-build

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run: az login"
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it: apt-get install jq"
        exit 1
    fi

    # Check Docker (if not skipping build)
    if [[ "$SKIP_BUILD" == "false" ]]; then
        if ! command -v docker &> /dev/null; then
            log_warning "Docker is not installed. Image build will use ACR Tasks."
        fi
    fi

    log_success "Prerequisites check passed"
}

parse_args() {
    shift # Remove the environment argument
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -n|--name)
                BASE_NAME="$2"
                shift 2
                ;;
            -r|--registry)
                ACR_NAME="$2"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-secrets)
                SKIP_SECRETS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Set defaults based on environment
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP="${BASE_NAME}-${ENVIRONMENT}-rg"
    fi

    if [[ -z "$ACR_NAME" ]]; then
        ACR_NAME="${BASE_NAME}acr${ENVIRONMENT}"
    fi
}

validate_environment() {
    case $ENVIRONMENT in
        dev|staging|prod)
            log_info "Deploying to: $ENVIRONMENT"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            log_error "Valid options: dev, staging, prod"
            exit 1
            ;;
    esac
}

# ============================================================================
# DEPLOYMENT FUNCTIONS
# ============================================================================

create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return
    fi

    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags environment="$ENVIRONMENT" application="OpenClaw" \
        --output none

    log_success "Resource group created: $RESOURCE_GROUP"
}

create_container_registry() {
    log_info "Creating Azure Container Registry: $ACR_NAME"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create ACR: $ACR_NAME"
        return
    fi

    # Check if ACR exists
    if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "ACR already exists: $ACR_NAME"
    else
        az acr create \
            --name "$ACR_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --sku Basic \
            --admin-enabled false \
            --output none

        log_success "ACR created: $ACR_NAME"
    fi
}

build_and_push_image() {
    if [[ "$SKIP_BUILD" == "true" ]]; then
        log_info "Skipping image build (--skip-build)"
        return
    fi

    log_info "Building and pushing container image..."

    local IMAGE_TAG="${ACR_NAME}.azurecr.io/openclaw:${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)"
    local IMAGE_LATEST="${ACR_NAME}.azurecr.io/openclaw:${ENVIRONMENT}-latest"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would build and push: $IMAGE_TAG"
        return
    fi

    # Use ACR Tasks for cloud build
    az acr build \
        --registry "$ACR_NAME" \
        --image "openclaw:${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)" \
        --image "openclaw:${ENVIRONMENT}-latest" \
        --file "${PROJECT_DIR}/Dockerfile" \
        "${PROJECT_DIR}"

    log_success "Image built and pushed: $IMAGE_LATEST"

    # Export for Bicep deployment
    export CONTAINER_IMAGE="$IMAGE_LATEST"
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Bicep..."

    local PARAMS_FILE="${BICEP_DIR}/parameters.${ENVIRONMENT}.json"
    local CONTAINER_IMAGE="${ACR_NAME}.azurecr.io/openclaw:${ENVIRONMENT}-latest"

    if [[ ! -f "$PARAMS_FILE" ]]; then
        log_warning "Parameters file not found: $PARAMS_FILE, using defaults"
        PARAMS_FILE=""
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Bicep template"
        log_info "  Resource Group: $RESOURCE_GROUP"
        log_info "  Parameters File: $PARAMS_FILE"
        log_info "  Container Image: $CONTAINER_IMAGE"
        return
    fi

    # Grant ACR pull permission before deployment
    if [[ -n "$ACR_NAME" ]]; then
        log_info "Granting ACR pull permission to managed identity..."
        if bash "${SCRIPT_DIR}/grant-acr-pull.sh" "$RESOURCE_GROUP" "$ENVIRONMENT" "$ACR_NAME" 2>&1 | tail -5; then
            log_success "ACR permissions configured"
        else
            log_warning "Could not auto-grant ACR permissions, will attempt deployment anyway"
        fi
    fi

    local DEPLOY_CMD=(
        az deployment group create
        --resource-group "$RESOURCE_GROUP"
        --template-file "${BICEP_DIR}/main.bicep"
    )

    # Apply parameters file first, then override with explicit values
    if [[ -n "$PARAMS_FILE" ]]; then
        DEPLOY_CMD+=(--parameters "@${PARAMS_FILE}")
    fi

    DEPLOY_CMD+=(
        --parameters environment="$ENVIRONMENT"
        --parameters baseName="$BASE_NAME"
        --parameters containerImage="$CONTAINER_IMAGE"
        --parameters acrName="$ACR_NAME"
    )

    "${DEPLOY_CMD[@]}" --output json > /tmp/deployment-output.json

    log_success "Infrastructure deployed successfully"

    # Extract outputs
    CONTAINER_APP_URL=$(jq -r '.properties.outputs.containerAppUrl.value' /tmp/deployment-output.json)
    KEY_VAULT_NAME=$(jq -r '.properties.outputs.keyVaultName.value' /tmp/deployment-output.json)
    MANAGED_IDENTITY_ID=$(jq -r '.properties.outputs.managedIdentityClientId.value' /tmp/deployment-output.json)

    log_info "Container App URL: $CONTAINER_APP_URL"
    log_info "Key Vault: $KEY_VAULT_NAME"
    log_info "Managed Identity: $MANAGED_IDENTITY_ID"
}

grant_acr_pull() {
    log_info "Granting ACR pull permissions to managed identity..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would grant AcrPull role"
        return
    fi

    local IDENTITY_PRINCIPAL_ID=$(jq -r '.properties.outputs.managedIdentityPrincipalId.value' /tmp/deployment-output.json)
    local ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)

    az role assignment create \
        --assignee "$IDENTITY_PRINCIPAL_ID" \
        --role "AcrPull" \
        --scope "$ACR_ID" \
        --output none 2>/dev/null || true

    log_success "ACR pull permissions granted"
}

setup_secrets() {
    if [[ "$SKIP_SECRETS" == "true" ]]; then
        log_info "Skipping secrets setup (--skip-secrets)"
        return
    fi

    local KEY_VAULT_NAME=$(jq -r '.properties.outputs.keyVaultName.value' /tmp/deployment-output.json)

    log_info "Setting up Key Vault secrets..."
    log_warning "You will need to populate the following secrets in: $KEY_VAULT_NAME"

    cat << EOF

Required Secrets:
-----------------
1. anthropic-api-key    - Your Anthropic API key (sk-ant-...)
2. gateway-token        - Random token for gateway auth (generate with: openssl rand -hex 32)

Optional Secrets (for channel integrations):
--------------------------------------------
3. telegram-bot-token   - Telegram Bot API token
4. slack-bot-token      - Slack Bot OAuth token (xoxb-...)
5. slack-app-token      - Slack App-level token (xapp-...)
6. teams-app-id         - Microsoft Teams App ID
7. teams-app-password   - Microsoft Teams App Password
8. discord-bot-token    - Discord Bot token

Run the secrets setup script:
  ./scripts/setup-secrets.sh $KEY_VAULT_NAME

Or manually:
  az keyvault secret set --vault-name $KEY_VAULT_NAME --name anthropic-api-key --value "YOUR_KEY"
  az keyvault secret set --vault-name $KEY_VAULT_NAME --name gateway-token --value "\$(openssl rand -hex 32)"

EOF
}

print_summary() {
    log_success "Deployment complete!"
    echo ""
    echo "============================================"
    echo "OpenClaw Deployment Summary"
    echo "============================================"
    echo ""
    echo "Environment:     $ENVIRONMENT"
    echo "Resource Group:  $RESOURCE_GROUP"
    echo "Location:        $LOCATION"
    echo ""

    if [[ -f /tmp/deployment-output.json ]]; then
        echo "Resources:"
        echo "  Container App:  $(jq -r '.properties.outputs.containerAppUrl.value' /tmp/deployment-output.json)"
        echo "  Key Vault:      $(jq -r '.properties.outputs.keyVaultName.value' /tmp/deployment-output.json)"
        echo "  Storage:        $(jq -r '.properties.outputs.storageAccountName.value' /tmp/deployment-output.json)"
        echo ""
    fi

    echo "Next Steps:"
    echo "  1. Configure secrets in Key Vault (see above)"
    echo "  2. Copy workspace files to Azure Files share"
    echo "  3. Configure channel integrations (Teams, Slack, etc.)"
    echo "  4. Test the deployment: curl <container-app-url>/health"
    echo ""
    echo "Documentation: ${PROJECT_DIR}/docs/DEPLOYMENT.md"
    echo "============================================"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           OpenClaw Azure Deployment                           ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    # Validate environment first
    validate_environment

    # Parse remaining arguments
    parse_args "$@"

    # Show configuration
    log_info "Configuration:"
    log_info "  Environment:     $ENVIRONMENT"
    log_info "  Resource Group:  $RESOURCE_GROUP"
    log_info "  Location:        $LOCATION"
    log_info "  Base Name:       $BASE_NAME"
    log_info "  ACR Name:        $ACR_NAME"
    log_info "  Skip Build:      $SKIP_BUILD"
    log_info "  Skip Secrets:    $SKIP_SECRETS"
    log_info "  Dry Run:         $DRY_RUN"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Execute deployment steps
    create_resource_group
    create_container_registry
    build_and_push_image
    deploy_infrastructure
    grant_acr_pull
    setup_secrets
    print_summary
}

# Run main with all arguments
main "$@"
