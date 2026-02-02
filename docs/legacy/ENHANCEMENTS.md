# Enhancement Summary: Configuration-First Deployment

## What Was Changed

The OpenClaw Azure deployment has been enhanced to solve the **configuration timing problem** where containers would start before the configuration files were ready.

### Changes Made

#### 1. **Enhanced Entrypoint** (`scripts/entrypoint-v2.sh`)

**Old behavior:** Minimal config, starts gateway with fallback mode if config missing

**New behavior:**
- ✅ Reads secrets from Azure Key Vault (via managed identity)
- ✅ Reads secrets from environment variables (fallback)
- ✅ Generates complete `openclaw.json` with all settings
- ✅ Generates `channels.json` from channel env vars
- ✅ Validates configuration before startup
- ✅ Comprehensive logging at every step
- ✅ Auto-generates gateway token if not provided
- ✅ Supports all channel integrations (Teams, Slack, Telegram, Discord, Google Chat)

**Key Features:**
```bash
# Reads from Key Vault securely
read_env_or_keyvault "GATEWAY_TOKEN" "gateway-token"

# Generates full gateway config
generate_gateway_config()

# Generates channel configs dynamically
generate_channels_config()

# Validates everything before startup
validate_configuration()
```

#### 2. **Pre-Deployment Validator** (`scripts/validate-deployment.sh`)

New comprehensive validation script that checks:
- ✅ All prerequisites installed (az, docker, git, jq)
- ✅ Azure authentication configured
- ✅ Resource group accessible
- ✅ Key Vault accessible and populated
- ✅ Docker image available
- ✅ Bicep files valid
- ✅ Configuration files exist and are valid JSON
- ✅ Scripts are executable
- ✅ Dockerfile has all required components
- ✅ Environment variables set
- ✅ Network connectivity to Azure

**Usage:**
```bash
bash scripts/validate-deployment.sh
```

Output shows:
- ✓ Passed checks
- ⚠ Warnings (optional but helpful)
- ✗ Failed checks (blocking issues)

#### 3. **Configuration Templates** (`config/`)

New template files with environment variable substitution:

- `config/gateway-config.template.json` — Gateway settings template
- `config/channels.template.json` — Channel integrations template

These templates show:
- All available options
- Default values
- Environment variable placeholders
- How to customize for your setup

#### 4. **Environment File** (`.env.example`)

Comprehensive `.env.example` that includes:
- All Azure configuration variables
- All OpenClaw gateway settings
- All channel integration tokens
- Production vs. development settings
- Helpful comments for each variable

Users copy this to `.env` and fill in their values.

#### 5. **Comprehensive Documentation**

**`CONFIGURATION.md`** — How configuration works at startup
- Startup flow diagram
- Configuration priority order
- Step-by-step setup guide
- Secret management (env vars vs. Key Vault)
- Environment variable reference
- Troubleshooting guide
- Monitoring setup
- Configuration updates without redeployment

**`DEPLOYMENT-CHECKLIST.md`** — Step-by-step deployment checklist
- Pre-deployment checks
- Azure setup verification
- Docker build verification
- Infrastructure deployment verification
- Configuration and startup verification
- Testing procedures
- Post-deployment tasks
- Channel configuration (Teams, Slack, Telegram, Discord)
- Sign-off section

#### 6. **Updated Dockerfile**

Changed entrypoint from `entrypoint.sh` to `entrypoint-v2.sh`:
```dockerfile
COPY --chown=openclaw:openclaw scripts/entrypoint-v2.sh /usr/local/bin/entrypoint
```

## Startup Flow (Visual)

```
Container Starts (dumb-init handles signals)
        ↓
entrypoint-v2.sh runs as non-root user
        ↓
Ensure /data directories exist and are writable
        ↓
Read secrets from Key Vault (or env vars)
        ↓
Generate /data/config/openclaw.json
        ↓
Generate /data/config/channels.json (if channel tokens set)
        ↓
Validate configuration files
        ↓
✓ Start OpenClaw gateway in foreground
```

## Configuration Priority (What Takes Precedence)

1. **Environment Variables** (highest priority)
   - Set via `az containerapp update --set-env-vars`
   - Useful for secrets and per-instance customization
   - Example: `GATEWAY_TOKEN=abc123...`

2. **Azure Key Vault** (fallback)
   - Secrets stored securely in Azure
   - Container reads via managed identity
   - Enabled if `AZURE_KEYVAULT_NAME` is set
   - Example: Read `gateway-token` secret from KV

3. **Generated Defaults** (lowest priority)
   - Auto-generate gateway token if not provided
   - Use sensible defaults for optional settings
   - Allows containers to start with minimal config

## How to Use

### Simple Setup (Environment Variables)

```bash
# Load your environment
source .env

# Validate everything first
bash scripts/validate-deployment.sh

# Deploy
bash scripts/deploy.sh prod \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --registry "$AZURE_ACR_NAME"
```

### Secure Setup (Key Vault) - Recommended

```bash
# 1. Create Key Vault and populate with secrets
bash scripts/setup-secrets.sh "$AZURE_KEYVAULT_NAME" --file .env

# 2. Validate
bash scripts/validate-deployment.sh

# 3. Deploy
bash scripts/deploy.sh prod \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --registry "$AZURE_ACR_NAME"

# 4. Give container access to Key Vault
IDENTITY_ID=$(az containerapp show \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --query identity.principalId -o tsv)

az keyvault set-policy \
  --name "$AZURE_KEYVAULT_NAME" \
  --object-id "$IDENTITY_ID" \
  --secret-permissions get list
```

## Example: Configuration Files Generated

### At Container Startup

Container reads these env vars:
```bash
GATEWAY_TOKEN="abc123..."
ANTHROPIC_API_KEY="sk-ant-..."
OPENCLAW_LOG_LEVEL="info"
TEAMS_APP_ID="00000000-0000-0000-0000-000000000000"
TEAMS_APP_PASSWORD="...from Key Vault..."
```

Generates `/data/config/openclaw.json`:
```json
{
  "gateway": {
    "bind": "0.0.0.0",
    "port": 18789,
    "logLevel": "info",
    "cors": {
      "enabled": true,
      "origins": ["*"],
      "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    },
    "auth": {
      "mode": "token",
      "token": "abc123..."
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/data/workspace",
      "model": {
        "primary": "github-copilot/claude-haiku-4.5"
      }
    }
  },
  "browser": {
    "enabled": true,
    "executablePath": "/usr/bin/chromium",
    "headless": true
  },
  "azure": {
    "enabled": true,
    "useManagedIdentity": true,
    "keyVaultIntegration": true,
    "applicationInsights": {
      "enabled": true
    }
  }
}
```

Generates `/data/config/channels.json`:
```json
{
  "teams": {
    "appId": "00000000-0000-0000-0000-000000000000",
    "appPassword": "...from Key Vault...",
    "enabled": true
  }
}
```

Gateway starts with complete, validated configuration!

## Benefits

### ✅ Reliability
- No more "configuration not found" startup failures
- Complete validation before startup
- Clear error messages if configuration is missing

### ✅ Security
- Secrets stored in Azure Key Vault (not in code)
- Managed identity authentication (no API keys in env)
- Secrets redacted from logs
- Non-root container user

### ✅ Flexibility
- Supports both env vars and Key Vault
- Supports all channel integrations
- Configuration can be changed without redeploying
- Auto-generates gateway token if needed

### ✅ Observability
- Comprehensive startup logging
- Configuration printed to logs (secrets redacted)
- Pre-deployment validator catches issues early
- Health checks and metrics endpoints

### ✅ Operations
- One-command deployment: `bash scripts/deploy.sh`
- Configuration checklist prevents mistakes
- Easy to troubleshoot with detailed logs
- Easy rollback via Container App revisions

## Troubleshooting

### Container won't start?

1. **Check logs:**
   ```bash
   az containerapp logs show \
     -g "$AZURE_RESOURCE_GROUP" \
     -n openclaw-app-prod \
     --follow
   ```

2. **Look for error messages:**
   - `ERROR: Required configuration missing: ANTHROPIC_API_KEY`
   - `ERROR: Key Vault not accessible: openclaw-kv`
   - `ERROR: Port 18789 is already in use`

3. **Validate configuration:**
   ```bash
   bash scripts/validate-deployment.sh
   ```

### Configuration not being read from Key Vault?

1. **Check managed identity is assigned:**
   ```bash
   az containerapp show \
     -g "$AZURE_RESOURCE_GROUP" \
     -n openclaw-app-prod \
     --query identity
   ```

2. **Check Key Vault permissions:**
   ```bash
   az keyvault show --name "$AZURE_KEYVAULT_NAME"
   ```

3. **Check AZURE_KEYVAULT_NAME env var is set:**
   ```bash
   az containerapp show \
     -g "$AZURE_RESOURCE_GROUP" \
     -n openclaw-app-prod \
     --query properties.template.containers[0].env
   ```

## Files Changed/Added

```
openclaw-azure-deploy/
├── scripts/
│   ├── entrypoint-v2.sh ..................... [NEW] Enhanced entrypoint with KV support
│   ├── validate-deployment.sh ............... [NEW] Pre-deployment validator
│   └── entrypoint.sh ........................ [OLD] Original (kept for reference)
├── config/
│   ├── gateway-config.template.json ......... [NEW] Gateway config template
│   ├── channels.template.json .............. [NEW] Channel config template
│   └── (existing configs)
├── .env.example ............................. [NEW] Environment variables template
├── Dockerfile ............................... [UPDATED] Uses entrypoint-v2.sh
├── CONFIGURATION.md ......................... [NEW] Configuration guide
├── DEPLOYMENT-CHECKLIST.md .................. [NEW] Step-by-step checklist
├── README.md ............................... [EXISTING] Main documentation
└── QUICKSTART.md ........................... [EXISTING] Quick start guide
```

## Next Steps

1. **Read CONFIGURATION.md** — Understand how configuration works
2. **Copy .env.example to .env** — Set up your environment
3. **Run validate-deployment.sh** — Check everything is in place
4. **Run setup-secrets.sh** — Populate Azure Key Vault
5. **Deploy!** — `bash scripts/deploy.sh prod`
6. **Follow DEPLOYMENT-CHECKLIST.md** — Verify each step

## Questions?

See the comprehensive guides:
- **How configuration works:** `CONFIGURATION.md`
- **Step-by-step deployment:** `DEPLOYMENT-CHECKLIST.md`
- **Quick start:** `QUICKSTART.md`
- **Full documentation:** `README.md`

Or check the logs:
```bash
az containerapp logs show \
  -g "$AZURE_RESOURCE_GROUP" \
  -n openclaw-app-prod \
  --follow
```

---

**Version:** 2.0 (Configuration-First)  
**Date:** 2026-02-02  
**Status:** Ready to Deploy
