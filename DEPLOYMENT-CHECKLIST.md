# Deployment Checklist

Use this checklist to ensure nothing is missed during deployment.

## Pre-Deployment (Local)

### Prerequisites

- [ ] Azure CLI installed (`az --version`)
- [ ] Docker installed (`docker --version`)
- [ ] Git installed (`git --version`)
- [ ] jq installed (`jq --version`)
- [ ] Logged into Azure (`az login` successful)

### Configuration

- [ ] Copied `.env.example` to `.env`
- [ ] Updated `.env` with your values:
  - [ ] `AZURE_SUBSCRIPTION_ID`
  - [ ] `AZURE_RESOURCE_GROUP`
  - [ ] `AZURE_LOCATION`
  - [ ] `AZURE_KEYVAULT_NAME`
  - [ ] `AZURE_ACR_NAME`
  - [ ] `ANTHROPIC_API_KEY`
  - [ ] `GATEWAY_TOKEN` (or will be auto-generated)
- [ ] Loaded environment variables: `source .env`
- [ ] Ran validator: `bash scripts/validate-deployment.sh`
  - [ ] All checks passed (or only warnings)
  - [ ] No blocking errors

### Repository Status

- [ ] Git repository initialized
- [ ] All changes committed: `git status` clean
- [ ] Remote configured: `git remote -v`
- [ ] Branch is correct: `git branch`

## Deployment Phase 1: Azure Setup

### Azure CLI Configuration

- [ ] Correct subscription selected:
  ```bash
  az account set -s "$AZURE_SUBSCRIPTION_ID"
  az account show
  ```
- [ ] Sufficient permissions:
  - [ ] Can create resource groups
  - [ ] Can create container registries
  - [ ] Can create container apps
  - [ ] Can create key vaults

### Resource Group

- [ ] Resource group exists (or will be created):
  ```bash
  az group show -n "$AZURE_RESOURCE_GROUP"
  ```
- [ ] If creating new:
  ```bash
  az group create -n "$AZURE_RESOURCE_GROUP" -l "$AZURE_LOCATION"
  ```

### Key Vault

- [ ] Key Vault exists or ready to create:
  ```bash
  az keyvault show -n "$AZURE_KEYVAULT_NAME"
  ```
- [ ] If creating new:
  ```bash
  az keyvault create \
    -g "$AZURE_RESOURCE_GROUP" \
    -n "$AZURE_KEYVAULT_NAME" \
    -l "$AZURE_LOCATION"
  ```
- [ ] Secrets populated:
  ```bash
  bash scripts/setup-secrets.sh "$AZURE_KEYVAULT_NAME" --file .env
  ```
- [ ] Verify secrets exist:
  ```bash
  az keyvault secret list --vault-name "$AZURE_KEYVAULT_NAME"
  ```

### Container Registry

- [ ] ACR ready to create or already exists:
  ```bash
  az acr show -n "$AZURE_ACR_NAME"
  ```
- [ ] If creating new:
  ```bash
  az acr create \
    -g "$AZURE_RESOURCE_GROUP" \
    -n "$AZURE_ACR_NAME" \
    --sku Basic
  ```
- [ ] Logged into ACR:
  ```bash
  az acr login -n "$AZURE_ACR_NAME"
  ```

## Deployment Phase 2: Docker Image

### Build Docker Image

- [ ] Dockerfile reviewed and valid
- [ ] Image built successfully:
  ```bash
  bash scripts/build-image.sh \
    --registry "$AZURE_ACR_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP"
  ```
- [ ] Image pushed to ACR:
  ```bash
  docker push "$DOCKER_IMAGE"
  ```
- [ ] Image verified in ACR:
  ```bash
  az acr repository show -n "$AZURE_ACR_NAME" --image openclaw:latest
  ```

## Deployment Phase 3: Infrastructure (Bicep)

### Bicep Validation

- [ ] Bicep files reviewed:
  - [ ] `bicep/main.bicep`
  - [ ] `bicep/parameters.bicep`
- [ ] Parameters validated:
  - [ ] `bicep/parameters.${ENVIRONMENT}.json` exists
  - [ ] All required parameters can be provided

### Deploy Infrastructure

- [ ] Deployment command prepared:
  ```bash
  az deployment group create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --template-file bicep/main.bicep \
    --parameters "@bicep/parameters.${AZURE_ENVIRONMENT}.json" \
    --parameters containerImage="$DOCKER_IMAGE" \
    --parameters acrName="$AZURE_ACR_NAME"
  ```
- [ ] Deployment started
- [ ] Deployment completed successfully:
  ```bash
  az deployment group list -g "$AZURE_RESOURCE_GROUP" --query "[0].properties.provisioningState"
  ```

### Post-Deployment Verification

- [ ] Container App created:
  ```bash
  az containerapp show \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT}
  ```
- [ ] Container App URL obtained:
  ```bash
  az containerapp show \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT} \
    --query properties.configuration.ingress.fqdn
  ```
- [ ] Container is running:
  ```bash
  az containerapp show \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT} \
    --query properties.runningStatus
  ```

## Deployment Phase 4: Configuration & Startup

### Container Environment

- [ ] Environment variables configured in Container App:
  - [ ] `GATEWAY_TOKEN` (or auto-generated)
  - [ ] `ANTHROPIC_API_KEY` (if not in Key Vault)
  - [ ] `AZURE_KEYVAULT_NAME` (if using Key Vault)
  - [ ] `OPENCLAW_LOG_LEVEL`
  - [ ] Channel tokens (Teams, Slack, etc.) if needed

### Managed Identity

- [ ] Managed identity assigned:
  ```bash
  az containerapp identity assign \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT}
  ```
- [ ] Key Vault access granted:
  ```bash
  IDENTITY_ID=$(az containerapp show \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT} \
    --query identity.principalId -o tsv)

  az keyvault set-policy \
    --name "$AZURE_KEYVAULT_NAME" \
    --object-id "$IDENTITY_ID" \
    --secret-permissions get list
  ```

### Container Startup

- [ ] Container logs checked:
  ```bash
  az containerapp logs show \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT} \
    --follow
  ```
- [ ] Startup completed without errors:
  - [ ] "OpenClaw Container Entrypoint" message appears
  - [ ] "Generating gateway configuration" appears
  - [ ] "Starting OpenClaw gateway" appears
  - [ ] Gateway logs show successful startup

## Testing Phase

### Health Check

- [ ] Gateway responds to health endpoint:
  ```bash
  URL=$(az containerapp show \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT} \
    --query properties.configuration.ingress.fqdn -o tsv)

  curl -i "https://$URL/health" \
    -H "X-Gateway-Token: $GATEWAY_TOKEN"
  ```
- [ ] Response is `200 OK`

### Configuration Files

- [ ] Files generated inside container:
  ```bash
  az containerapp exec \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT}

  # Inside container:
  ls -la /data/config/
  cat /data/config/openclaw.json
  cat /data/config/channels.json
  ```
- [ ] `openclaw.json` contains correct settings
- [ ] `channels.json` contains channel configs (if configured)

### Gateway API

- [ ] Gateway metrics endpoint works:
  ```bash
  curl "https://$URL/metrics" \
    -H "X-Gateway-Token: $GATEWAY_TOKEN"
  ```
- [ ] Response includes Prometheus metrics

### Application Insights

- [ ] Application Insights monitoring enabled
- [ ] Telemetry appearing:
  - [ ] Check Azure Portal → Application Insights → Live Metrics
  - [ ] Requests are being logged
  - [ ] Exceptions (if any) are visible

## Post-Deployment

### Scaling Configuration

- [ ] Auto-scaling configured correctly:
  ```bash
  az containerapp show \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT} \
    --query properties.template.scale
  ```
- [ ] Min/max replicas set as intended

### Monitoring & Alerts

- [ ] Application Insights dashboard set up
- [ ] Alerts configured for:
  - [ ] Container restarts
  - [ ] High CPU/memory usage
  - [ ] Gateway errors
  - [ ] Health check failures

### Backup Strategy

- [ ] Azure Files backup enabled (if using persistent storage)
- [ ] Data retention policies configured

### Documentation

- [ ] Deployment notes recorded:
  - [ ] Date and time deployed
  - [ ] Resource group created
  - [ ] Gateway token (securely stored)
  - [ ] Container App URL
  - [ ] Any custom configurations applied
- [ ] Changes committed to git:
  ```bash
  git add .
  git commit -m "Deploy OpenClaw to Azure - Production"
  git push
  ```

## Channel Configuration (Optional)

### Microsoft Teams

- [ ] Teams app registered in Azure AD
- [ ] Bot credentials configured:
  - [ ] `TEAMS_APP_ID` set
  - [ ] `TEAMS_APP_PASSWORD` set in Key Vault
- [ ] Webhook endpoint registered in Teams
- [ ] Test message sent to Teams

### Slack

- [ ] Slack bot created at https://api.slack.com/apps
- [ ] Bot tokens obtained:
  - [ ] Bot token (`xoxb-...`)
  - [ ] App token (`xapp-...`)
- [ ] Tokens set in Key Vault
- [ ] Socket Mode enabled in Slack app
- [ ] Test message sent to Slack

### Telegram

- [ ] Bot created with @BotFather
- [ ] Bot token obtained
- [ ] Token set in Key Vault
- [ ] Webhook URL configured in Telegram
- [ ] Test message sent to Telegram

### Discord

- [ ] Bot application created at Discord Developer Portal
- [ ] Bot token obtained
- [ ] Token set in Key Vault
- [ ] Bot invited to test server
- [ ] Test message sent to Discord

## Rollback Plan

- [ ] Previous container image tag noted
- [ ] Previous configuration backed up
- [ ] Rollback procedure documented:
  ```bash
  # Activate previous revision
  az containerapp revision activate \
    -g "$AZURE_RESOURCE_GROUP" \
    -n openclaw-app-${AZURE_ENVIRONMENT} \
    --revision <previous-revision-name>
  ```

## Sign-Off

- [ ] Deployment tested and verified
- [ ] All critical components working
- [ ] Monitoring and alerts active
- [ ] Documentation complete
- [ ] Stakeholders notified

**Deployment Date:** _______________

**Deployed By:** _______________

**Notes:** 

_______________________________________________________________

_______________________________________________________________

---

**If anything is missing, do not proceed with the next phase. Return to the previous phase and complete all checks first.**
