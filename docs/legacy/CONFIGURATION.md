# Configuration-First Deployment Guide

## Overview

This guide explains how the enhanced OpenClaw deployment handles configuration startup. The key principle:

**When the container starts, it reads mandatory configuration from Key Vault / environment variables, generates the necessary configuration files, validates everything, then starts the gateway.**

No more "container started before config was ready" failures!

## Architecture

### Startup Flow

```
┌─────────────────────────────────────┐
│   Container Starts (dumb-init)      │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│    entrypoint-v2.sh Runs            │
│  (runs as non-root user)            │
└────────────┬────────────────────────┘
             │
     ┌───────┴──────────────────┬──────────────┐
     │                          │              │
     ▼                          ▼              ▼
┌──────────────┐    ┌──────────────────┐  ┌──────────────────┐
│ Ensure Dirs  │    │ Read Secrets     │  │ Validate Config  │
│ Exist        │    │ from KV/EnvVars  │  │ Permissions OK   │
└──────────────┘    └──────────────────┘  └──────────────────┘
     │                          │              │
     └───────┬──────────────────┼──────────────┘
             │                  │
             ▼                  ▼
     ┌─────────────────────────────────────┐
     │  Generate Config Files              │
     │  - openclaw.json (gateway config)   │
     │  - channels.json (channel settings) │
     └─────────────────────────────────────┘
             │
             ▼
     ┌─────────────────────────────────────┐
     │  Validate Generated Config          │
     │  - Files exist and are readable    │
     │  - JSON is valid                    │
     └─────────────────────────────────────┘
             │
             ▼
     ┌─────────────────────────────────────┐
     │  Start OpenClaw Gateway             │
     │  (runs in foreground, PID 1)        │
     └─────────────────────────────────────┘
```

### Configuration Sources (Priority Order)

1. **Environment Variables** (highest priority)
   - `GATEWAY_TOKEN` → gateway authentication
   - `TEAMS_APP_ID` → Teams integration
   - `ANTHROPIC_API_KEY` → API key
   - etc.

2. **Azure Key Vault** (fallback)
   - `gateway-token` secret
   - `teams-app-password` secret
   - Any other secrets managed in KV
   - Requires `AZURE_KEYVAULT_NAME` env var

3. **Generated Defaults** (lowest priority)
   - Auto-generates gateway token if missing
   - Uses reasonable defaults for optional settings

## Setup Steps

### Step 1: Prepare Environment File

```bash
cd /datadrive/workspaces/clawd/openclaw-azure-deploy

# Copy the example
cp .env.example .env

# Edit with your values
nano .env
```

**Critical variables:**
```bash
AZURE_SUBSCRIPTION_ID="your-sub-id"
AZURE_RESOURCE_GROUP="openclaw-rg"
AZURE_KEYVAULT_NAME="openclaw-kv"
ANTHROPIC_API_KEY="sk-ant-..."
GATEWAY_TOKEN=$(openssl rand -hex 32)  # Generate this
```

### Step 2: Load Environment Variables

```bash
# Load from .env file
set -a
source .env
set +a

# Verify
echo "Resource Group: $AZURE_RESOURCE_GROUP"
echo "Key Vault: $AZURE_KEYVAULT_NAME"
```

### Step 3: Validate Deployment Configuration

```bash
# Run the validator
bash scripts/validate-deployment.sh
```

This checks:
- ✓ Azure CLI installed and authenticated
- ✓ Docker installed
- ✓ Resource group exists
- ✓ Key Vault exists and is accessible
- ✓ Bicep files are valid
- ✓ Configuration files exist
- ✓ Scripts are executable
- ✓ All required env vars are set

**Fix any issues reported before proceeding.**

### Step 4: Setup Key Vault Secrets

```bash
# Create the Key Vault if it doesn't exist
az keyvault create \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_KEYVAULT_NAME" \
  --location "$AZURE_LOCATION"

# Populate secrets from your .env file
bash scripts/setup-secrets.sh "$AZURE_KEYVAULT_NAME" \
  --file .env \
  --non-interactive
```

Or interactively:
```bash
bash scripts/setup-secrets.sh "$AZURE_KEYVAULT_NAME"
```

### Step 5: Build and Push Docker Image

```bash
# Set up container registry
az acr create \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_ACR_NAME" \
  --sku Basic

# Build and push
bash scripts/build-image.sh \
  --registry "$AZURE_ACR_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP"
```

### Step 6: Deploy to Container Apps

```bash
# Full automated deployment
bash scripts/deploy.sh "$AZURE_ENVIRONMENT" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --registry "$AZURE_ACR_NAME"
```

Or deploy components individually:

```bash
# 1. Create resource group
az group create \
  -n "$AZURE_RESOURCE_GROUP" \
  -l "$AZURE_LOCATION"

# 2. Deploy infrastructure via Bicep
az deployment group create \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --template-file bicep/main.bicep \
  --parameters "@bicep/parameters.${AZURE_ENVIRONMENT}.json" \
  --parameters containerImage="$DOCKER_IMAGE" \
  --parameters acrName="$AZURE_ACR_NAME"

# 3. Verify deployment
az containerapp show \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-${AZURE_ENVIRONMENT} \
  --query properties.configuration.ingress.fqdn
```

## Configuration at Startup

### What the Entrypoint Does

When the container starts, `entrypoint-v2.sh` runs and:

1. **Ensures directories exist**
   ```
   /data/config
   /data/workspace
   /data/logs
   /data/cache
   ```

2. **Reads secrets** (in priority order):
   - Environment variables (highest)
   - Azure Key Vault
   - Generated defaults (lowest)

3. **Generates `openclaw.json`**
   ```json
   {
     "gateway": {
       "bind": "0.0.0.0",
       "port": 18789,
       "auth": {
         "mode": "token",
         "token": "GATEWAY_TOKEN"
       }
     },
     "agents": {
       "defaults": {
         "model": "github-copilot/claude-haiku-4.5"
       }
     },
     "channels": {}
   }
   ```

4. **Generates `channels.json`** (if channel env vars are set)
   ```json
   {
     "teams": {
       "appId": "TEAMS_APP_ID",
       "appPassword": "TEAMS_APP_PASSWORD",
       "enabled": true
     }
   }
   ```

5. **Validates everything**:
   - Directories are writable
   - Port is available
   - Config files are valid JSON

6. **Starts the gateway**
   ```bash
   openclaw gateway run --config /data/config/openclaw.json
   ```

### How to Provide Secrets

**Option A: Environment Variables (Simple)**

Pass secrets as container environment variables:

```bash
az containerapp update \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --set-env-vars \
    GATEWAY_TOKEN="abc123..." \
    ANTHROPIC_API_KEY="sk-ant-..." \
    TEAMS_APP_ID="..." \
    TEAMS_APP_PASSWORD="..."
```

**Option B: Azure Key Vault (Secure) - Recommended**

Store secrets in Key Vault, container reads them via managed identity:

1. Ensure container has managed identity:
   ```bash
   az containerapp identity assign \
     -g "$AZURE_RESOURCE_GROUP" \
     -n openclaw-app-prod
   ```

2. Grant Key Vault access:
   ```bash
   IDENTITY_ID=$(az containerapp show \
     -g "$AZURE_RESOURCE_GROUP" \
     -n openclaw-app-prod \
     --query identity.principalId -o tsv)

   az keyvault set-policy \
     --name "$AZURE_KEYVAULT_NAME" \
     --object-id "$IDENTITY_ID" \
     --secret-permissions get list
   ```

3. Set `AZURE_KEYVAULT_NAME` env var:
   ```bash
   az containerapp update \
     -g "$AZURE_RESOURCE_GROUP" \
     -n openclaw-app-prod \
     --set-env-vars AZURE_KEYVAULT_NAME="$AZURE_KEYVAULT_NAME"
   ```

Container will automatically read secrets from Key Vault at startup.

## Environment Variables Reference

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Anthropic API key | `sk-ant-...` |

### Optional (Defaults Provided)

| Variable | Default | Description |
|----------|---------|-------------|
| `GATEWAY_TOKEN` | (auto-generated) | Authentication token |
| `OPENCLAW_GATEWAY_BIND` | `0.0.0.0` | Bind address |
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway port |
| `OPENCLAW_LOG_LEVEL` | `info` | Log level |
| `OPENCLAW_MODEL_PRIMARY` | `github-copilot/claude-haiku-4.5` | Default model |
| `AZURE_KEYVAULT_NAME` | (none) | Key Vault for secrets |

### Channel Integrations (Optional)

| Variable | Channel |
|----------|---------|
| `TEAMS_APP_ID`, `TEAMS_APP_PASSWORD` | Microsoft Teams |
| `SLACK_BOT_TOKEN` | Slack |
| `TELEGRAM_BOT_TOKEN` | Telegram |
| `DISCORD_BOT_TOKEN` | Discord |

## Troubleshooting

### Container Won't Start

**Check logs:**
```bash
az containerapp logs show \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --follow
```

**Common issues:**

1. **Missing ANTHROPIC_API_KEY**
   ```
   ERROR: Required configuration missing: ANTHROPIC_API_KEY
   ```
   **Fix:** Set `ANTHROPIC_API_KEY` environment variable

2. **Key Vault not accessible**
   ```
   ERROR: Cannot access Key Vault: openclaw-kv
   ```
   **Fix:** Ensure container has managed identity with Key Vault permissions

3. **Port already in use**
   ```
   ERROR: Port 18789 is already in use
   ```
   **Fix:** Change `OPENCLAW_GATEWAY_PORT` or check for conflicting containers

4. **Config directory not writable**
   ```
   ERROR: Directory not writable: /data/config
   ```
   **Fix:** Check storage mounting and container permissions

### Gateway Not Responding

**Test endpoint:**
```bash
# Get container URL
URL=$(az containerapp show \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --query properties.configuration.ingress.fqdn -o tsv)

# Test health endpoint
curl -i "https://$URL/health" \
  -H "X-Gateway-Token: YOUR_GATEWAY_TOKEN"
```

**If timeout or 502:**

1. Check logs for startup errors
2. Verify gateway token is correct
3. Check Application Insights metrics

### Configuration Not Generated

**Check what's in the container:**
```bash
# Connect to container
az containerapp exec \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod

# Check config
ls -la /data/config/
cat /data/config/openclaw.json
```

**If files missing:**

1. Check entrypoint logs
2. Verify directory permissions
3. Check for JSON syntax errors

## Monitoring

### Application Insights

View real-time metrics:

```bash
# Get instrumentation key
az containerapp show \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --query properties.template.containers[0].env
```

Then view in Azure Portal → Application Insights.

### Container Logs

Stream logs in real-time:

```bash
az containerapp logs show \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --follow
```

### Health Checks

Check container status:

```bash
az containerapp show \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --query properties.template.containers[0].health
```

## Updating Configuration

To update configuration without redeploying:

```bash
# Update environment variables
az containerapp update \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --set-env-vars OPENCLAW_LOG_LEVEL="debug"

# Restart container (picks up new config)
az containerapp revision restart \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod
```

## Rollback

If deployment fails:

```bash
# List revisions
az containerapp revision list \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod

# Activate previous revision
az containerapp revision activate \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --revision openclaw-app-prod--<revision-number>
```

## Next Steps

1. ✓ Validate configuration with `validate-deployment.sh`
2. ✓ Set up Key Vault secrets with `setup-secrets.sh`
3. ✓ Build and push Docker image
4. ✓ Deploy infrastructure with Bicep
5. ✓ Monitor logs and metrics in Azure Portal
6. ✓ Configure channels (Teams, Slack, Telegram, etc.)
7. ✓ Test endpoints with curl or API client

---

**Questions?** See README.md or check logs with `az containerapp logs show`.
