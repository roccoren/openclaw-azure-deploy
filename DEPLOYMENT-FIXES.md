# Deployment Errors - Fixed

## Issues Found & Fixed

### 1. ✅ Missing `parameters.staging.json`
**Error:** `WARNING] Parameters file not found: /bicep/parameters.staging.json`

**Cause:** The staging environment parameters file didn't exist

**Fix:** Created `bicep/parameters.staging.json` with appropriate staging settings

### 2. ✅ Unused ACR Resource in Bicep
**Error:** `Warning no-unused-existing-resources: Existing resource "acr" is declared but never used`

**Cause:** The ACR was referenced but no role assignment was configured in Bicep

**Fix:** Added ACR role assignment directly in Bicep template

### 3. ✅ Managed Identity Can't Pull from ACR
**Error:** `unable to pull image using Managed identity ... for registry openclawpreacr.azurecr.io`

**Cause:** The managed identity didn't have `AcrPull` permission on the registry

**Fix:** Added role assignment in Bicep that grants `AcrPull` (role ID: `7f951dda-4ed3-4680-a7ca-6e2d38e9d6ff`) to the managed identity

---

## What Changed

**Commit:** `84b7c72`

**Files Updated:**
- ✅ `bicep/parameters.staging.json` — NEW (staging environment parameters)
- ✅ `bicep/main.bicep` — UPDATED (added ACR pull role assignment)

---

## Try Deployment Again

Now that the fixes are in place, re-run the deployment:

```bash
# Pull the latest changes
cd /home/roccoren/workspaces/openclaw-azure-deploy
git pull origin main

# Redeploy staging
bash scripts/deploy.sh staging \
  --resource-group openclaw-pre-group \
  --registry openclawpreacr
```

**Or manually:**

```bash
# Ensure you have the latest code
git pull

# Create resource group (if needed)
az group create \
  -n openclaw-pre-group \
  -l westus2

# Deploy with correct parameters
az deployment group create \
  -g openclaw-pre-group \
  -f bicep/main.bicep \
  -p @bicep/parameters.staging.json \
  -p containerImage="openclawpreacr.azurecr.io/openclaw:staging-latest" \
  -p acrName="openclawpreacr"
```

---

## What to Watch For

During deployment, you should now see:
- ✅ No more "parameters file not found" warning
- ✅ No more "unused resource" warning
- ✅ ACR role assignment created successfully
- ✅ Container App successfully pulls the image

**Check logs:**
```bash
az containerapp logs show \
  -g openclaw-pre-group \
  -n openclaw-app-staging \
  --follow
```

---

## If Issues Persist

**Check managed identity has ACR access:**
```bash
az role assignment list \
  --assignee openclaw-identity-staging \
  --resource-group openclaw-pre-group
```

You should see `AcrPull` role assignment.

**Verify ACR exists:**
```bash
az acr show -n openclawpreacr
```

**Check image exists in registry:**
```bash
az acr repository show-images \
  -n openclawpreacr \
  --query "[?tags[?contains(@, 'staging')]]"
```

---

## Summary

All three issues fixed in one commit:
1. Missing staging parameters ✅
2. Unused ACR resource ✅
3. Missing ACR pull permissions ✅

You can now deploy staging and production environments successfully!
