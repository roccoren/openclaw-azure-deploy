# Key Vault Purge Protection Issue - Solution

## Problem

You got this error during deployment:

```
DeploymentFailed: The property "enablePurgeProtection" cannot be set to false. 
Enabling the purge protection for a vault is an irreversible action.
```

## Why This Happens

Azure Key Vault has a **one-way switch**: once purge protection is enabled, **it can never be disabled**. This is intentional for security/compliance.

If your Key Vault (`openclaw-kv-prod`) already has purge protection enabled from a previous deployment, you **cannot set it to false** even if you wanted to.

## Solutions

### Option 1: Use the Existing Key Vault (Fastest)

If your Key Vault still exists and is working, just skip the Bicep deployment and manually configure the container:

```bash
# Don't redeploy the Key Vault, just verify it exists
az keyvault show -n openclaw-kv-prod

# Make sure secrets are set
az keyvault secret list -n openclaw-kv-prod

# Deploy only the Container App resources
az deployment group create \
  -g openclaw-pre-group \
  -f bicep/main.bicep \
  -p @bicep/parameters.prod.json \
  -p containerImage="openclawacr.azurecr.io/openclaw:latest" \
  -p acrName="openclawacr" \
  --parameters 'recoverKeyVault=false' \
  --skip-kv=true  # (if supported by your Bicep version)
```

### Option 2: Recover the Soft-Deleted Key Vault

If the Key Vault was deleted within the last 90 days, recover it:

```bash
# List soft-deleted Key Vaults
az keyvault list-deleted

# If you see openclaw-kv-prod in the list, recover it
az keyvault purge \
  --location westus2 \
  --name openclaw-kv-prod \
  --no-wait

# Or use recovery mode in deployment
az deployment group create \
  -g openclaw-pre-group \
  -f bicep/main.bicep \
  -p @bicep/parameters.prod.json \
  -p containerImage="openclawacr.azurecr.io/openclaw:latest" \
  -p acrName="openclawacr" \
  --parameters 'recoverKeyVault=true'
```

### Option 3: Use a New Key Vault Name

Change the Key Vault name to deploy a fresh one:

```bash
# Current: openclaw-kv-prod
# Use a new name: openclaw-kv-prod-2

az deployment group create \
  -g openclaw-pre-group \
  -f bicep/main.bicep \
  -p @bicep/parameters.prod.json \
  -p containerImage="openclawacr.azurecr.io/openclaw:latest" \
  -p acrName="openclawacr" \
  -p baseName="openclaw-kv-prod-2"
```

Then update the container to use the new vault:

```bash
az containerapp update \
  -g openclaw-pre-group \
  -n openclaw-app-prod \
  --set-env-vars AZURE_KEYVAULT_NAME="openclaw-kv-prod-2"
```

### Option 4: Manually Fix the Existing Deployment (Recommended for Production)

If you want to keep the existing Key Vault:

```bash
# 1. Verify the Key Vault exists and has the right secrets
az keyvault show -n openclaw-kv-prod

# 2. Manually populate secrets if needed
az keyvault secret set \
  -n openclaw-kv-prod \
  --name gateway-token \
  --value "your-token-value"

# 3. Create Container App environment separately
az containerapp environment create \
  -g openclaw-pre-group \
  -n openclaw-env-prod \
  -l westus2

# 4. Create Container App
az containerapp create \
  -g openclaw-pre-group \
  -n openclaw-app-prod \
  --image openclawacr.azurecr.io/openclaw:latest \
  --environment openclaw-env-prod \
  --env-vars \
    AZURE_KEYVAULT_NAME="openclaw-kv-prod" \
    OPENCLAW_LOG_LEVEL="info" \
    ANTHROPIC_API_KEY="from-keyvault"
```

## Recommended Solution

**I recommend Option 1 or Option 2:**

### Quick Fix (Option 1 - 2 minutes):
```bash
# Just verify KV exists
az keyvault show -n openclaw-kv-prod

# Populate/verify secrets
bash scripts/setup-secrets.sh openclaw-kv-prod --file .env

# Skip Bicep KV creation, deploy only Container App
# (You'll need to manually create the Container App environment first, or modify the Bicep)
```

### Clean Fix (Option 2 - 5 minutes):
```bash
# 1. Delete the Key Vault (if you want a fresh one)
az keyvault delete -n openclaw-kv-prod

# 2. Wait for purge (immediate for most cases)
sleep 5

# 3. Deploy everything fresh
bash scripts/deploy.sh prod \
  --resource-group openclaw-pre-group \
  --registry openclawacr
```

## Preventing This in the Future

The Bicep file has been updated to **always enable purge protection** (set to `true`). This prevents the "can't set to false" error because we never try to disable it.

If you need to update an existing deployment:

```bash
# Option A: Don't touch the Key Vault
# - Keep recoverKeyVault=false
# - Manually manage KV separately

# Option B: Use recovery mode for soft-deleted vaults
# - Set recoverKeyVault=true during deployment
# - This handles recovered vaults correctly
```

## Long-Term Solution

Going forward, the Bicep template:
- ✅ Always enables purge protection (no try-to-disable issue)
- ✅ Supports recovery mode for soft-deleted vaults
- ✅ Gracefully handles existing vaults

**What Changed in the Bicep:**
```bicep
// OLD (caused the error):
enablePurgeProtection: environment == 'prod'

// NEW (safe):
enablePurgeProtection: true
```

This ensures we never try to set purge protection to `false`, which is the actual error.

## Debugging Steps

If you still get errors:

```bash
# Check what Key Vaults exist (including soft-deleted)
az keyvault list -g openclaw-pre-group
az keyvault list-deleted

# Check the Key Vault properties
az keyvault show -n openclaw-kv-prod -g openclaw-pre-group

# Check deployment operations for detailed error
az deployment operation list \
  -g openclaw-pre-group \
  --name main \
  --query "[?properties.provisioningState=='Failed'].properties.statusMessage"
```

---

## Next Steps

**Choose one approach above:**
1. Use existing KV + skip Bicep KV creation (Option 1)
2. Delete and redeploy fresh (Option 2)
3. Use new KV name (Option 3)
4. Manual Container App creation (Option 4)

Then try deployment again:

```bash
bash scripts/deploy.sh prod \
  --resource-group openclaw-pre-group \
  --registry openclawacr
```

Let me know which option you chose and if you need help!
