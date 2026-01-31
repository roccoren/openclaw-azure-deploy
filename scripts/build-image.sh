#!/bin/bash
# ============================================================================
# OpenClaw Container Image Build Script
# ============================================================================
# Build and push OpenClaw container image to Azure Container Registry
# Usage: ./build-image.sh [options]
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
ACR_NAME=""
RESOURCE_GROUP=""
IMAGE_NAME="openclaw"
IMAGE_TAG=""
ENVIRONMENT="dev"
USE_ACR_TASKS=true
PUSH=true
PLATFORM="linux/amd64"
OPENCLAW_VERSION="latest"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_help() {
    cat << EOF
OpenClaw Container Image Build Script

Usage: $(basename "$0") [OPTIONS]

Options:
  -r, --registry NAME       ACR name (required, without .azurecr.io)
  -g, --resource-group NAME Resource group containing ACR
  -n, --name NAME           Image name (default: openclaw)
  -t, --tag TAG             Image tag (default: {env}-{timestamp})
  -e, --env ENV             Environment prefix (default: dev)
  -v, --version VERSION     OpenClaw version to install (default: latest)
  --local                   Build locally with Docker (don't use ACR Tasks)
  --no-push                 Build only, don't push to registry
  --platform PLATFORM       Target platform (default: linux/amd64)
  -h, --help                Show this help message

Examples:
  $(basename "$0") -r myacr -g mygroup
  $(basename "$0") -r myacr -g mygroup -t v1.0.0
  $(basename "$0") -r myacr -g mygroup --local
  $(basename "$0") -r myacr -g mygroup -e prod -v 1.2.3

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--registry)
                ACR_NAME="$2"
                shift 2
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -n|--name)
                IMAGE_NAME="$2"
                shift 2
                ;;
            -t|--tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            -e|--env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -v|--version)
                OPENCLAW_VERSION="$2"
                shift 2
                ;;
            --local)
                USE_ACR_TASKS=false
                shift
                ;;
            --no-push)
                PUSH=false
                shift
                ;;
            --platform)
                PLATFORM="$2"
                shift 2
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

    # Validate required args
    if [[ -z "$ACR_NAME" ]]; then
        log_error "ACR name is required (-r/--registry)"
        exit 1
    fi

    # Generate tag if not provided
    if [[ -z "$IMAGE_TAG" ]]; then
        IMAGE_TAG="${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)"
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Azure CLI always required
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi

    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Run: az login"
        exit 1
    fi

    # Docker required for local builds
    if [[ "$USE_ACR_TASKS" == "false" ]]; then
        if ! command -v docker &> /dev/null; then
            log_error "Docker is not installed (required for local builds)"
            exit 1
        fi

        if ! docker info &> /dev/null; then
            log_error "Docker daemon is not running"
            exit 1
        fi
    fi

    log_success "Prerequisites check passed"
}

validate_acr() {
    log_info "Validating ACR: $ACR_NAME"

    local acr_query="[?name=='$ACR_NAME']"

    if [[ -n "$RESOURCE_GROUP" ]]; then
        if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log_error "ACR not found: $ACR_NAME in resource group: $RESOURCE_GROUP"
            exit 1
        fi
    else
        # Find the ACR in any resource group
        RESOURCE_GROUP=$(az acr list --query "[?name=='$ACR_NAME'].resourceGroup | [0]" -o tsv)
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log_error "ACR not found: $ACR_NAME"
            exit 1
        fi
        log_info "Found ACR in resource group: $RESOURCE_GROUP"
    fi

    log_success "ACR validated: $ACR_NAME"
}

build_with_acr_tasks() {
    log_info "Building with ACR Tasks..."

    local FULL_TAG="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
    local LATEST_TAG="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${ENVIRONMENT}-latest"

    log_info "Image: $FULL_TAG"
    log_info "Also tagging as: $LATEST_TAG"

    az acr build \
        --registry "$ACR_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --image "${IMAGE_NAME}:${IMAGE_TAG}" \
        --image "${IMAGE_NAME}:${ENVIRONMENT}-latest" \
        --file "${PROJECT_DIR}/Dockerfile" \
        --build-arg "OPENCLAW_VERSION=${OPENCLAW_VERSION}" \
        --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --build-arg "VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
        --platform "$PLATFORM" \
        "${PROJECT_DIR}"

    log_success "Image built and pushed: $FULL_TAG"
}

build_local() {
    log_info "Building locally with Docker..."

    local FULL_TAG="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
    local LATEST_TAG="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${ENVIRONMENT}-latest"

    log_info "Image: $FULL_TAG"

    # Build
    docker build \
        --tag "$FULL_TAG" \
        --tag "$LATEST_TAG" \
        --build-arg "OPENCLAW_VERSION=${OPENCLAW_VERSION}" \
        --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --build-arg "VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
        --platform "$PLATFORM" \
        --file "${PROJECT_DIR}/Dockerfile" \
        "${PROJECT_DIR}"

    log_success "Image built: $FULL_TAG"

    if [[ "$PUSH" == "true" ]]; then
        push_to_acr "$FULL_TAG" "$LATEST_TAG"
    fi
}

push_to_acr() {
    local FULL_TAG="$1"
    local LATEST_TAG="$2"

    log_info "Logging into ACR..."
    az acr login --name "$ACR_NAME"

    log_info "Pushing image..."
    docker push "$FULL_TAG"
    docker push "$LATEST_TAG"

    log_success "Image pushed: $FULL_TAG"
}

print_summary() {
    local FULL_TAG="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"

    echo ""
    echo "============================================"
    echo "Build Summary"
    echo "============================================"
    echo ""
    echo "Registry:   $ACR_NAME.azurecr.io"
    echo "Image:      $IMAGE_NAME"
    echo "Tag:        $IMAGE_TAG"
    echo "Full Path:  $FULL_TAG"
    echo "Latest:     ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${ENVIRONMENT}-latest"
    echo ""
    echo "To deploy this image, update your Container App:"
    echo ""
    echo "  az containerapp update \\"
    echo "    --name openclaw-app-${ENVIRONMENT} \\"
    echo "    --resource-group openclaw-${ENVIRONMENT}-rg \\"
    echo "    --image $FULL_TAG"
    echo ""
    echo "============================================"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           OpenClaw Container Image Build                      ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    parse_args "$@"
    check_prerequisites
    validate_acr

    log_info "Configuration:"
    log_info "  ACR:              $ACR_NAME"
    log_info "  Resource Group:   $RESOURCE_GROUP"
    log_info "  Image:            $IMAGE_NAME:$IMAGE_TAG"
    log_info "  OpenClaw Version: $OPENCLAW_VERSION"
    log_info "  Build Method:     $([ "$USE_ACR_TASKS" == "true" ] && echo "ACR Tasks" || echo "Local Docker")"
    log_info "  Push:             $PUSH"
    echo ""

    if [[ "$USE_ACR_TASKS" == "true" ]]; then
        build_with_acr_tasks
    else
        build_local
    fi

    print_summary
}

main "$@"
