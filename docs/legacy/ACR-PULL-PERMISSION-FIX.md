# ACR Pull Permission Issue - Solution

## Problem

Your deployment is still failing with:
```
unable to pull image using Managed identity ... for registry openclawpreacr.azurecr.io
```

## Root Cause

The Bicep role assignment might not be working correctly, or the timing might be off. The managed identity needs **AcrPull** permission on the ACR before the Container App tries to pull the image.

## Solution

Use the new `grant-acr-pull.sh` script to manually assign the role:

```bash
cd /datadrive/workspaces/clawd/openclaw-azure-deploy

# Grant ACR pull permission
bash scripts/grant-acr-pull.sh openclaw-pre-group staging openclawpreacr
```

This script:
1. Gets the managed identity object ID
2. Gets the ACR resource ID
3. Assigns the **AcrPull** role directly
4. Provides next steps

### Expected Output

```
[INFO] Granting ACR pull permission
[INFO]   Resource Group: openclaw-pre-group
[INFO]   Environment: staging
[INFO]   Managed Identity: openclaw-identity-staging
[INFO]   ACR: openclawpreacr

[INFO] Getting managed identity object ID...
[SUCCESS] Managed Identity ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

[INFO] Getting ACR resource ID...
[SUCCESS] ACR Resource ID: /subscriptions/.../resourceGroups/.../providers/Microsoft.ContainerRegistry/registries/openclawpreacr

[INFO] Assigning AcrPull role to managed identity...
[SUCCESS] AcrPull role assigned!

[SUCCESS] All permissions granted!

Next: Redeploy the Container App:
  az deployment group create \
    -g openclaw-pre-group \
    -f bicep/main.bicep \
    -p @bicep/parameters.staging.json \
    -p containerImage=openclawpreacr.azurecr.io/openclaw:staging-latest \
    -p acrName=openclawpreacr
```

## Then Redeploy

After granting the permissions, redeploy:

```bash
bash scripts/deploy.sh staging \
  --resource-group openclaw-pre-group \
  --registry openclawpreacr
```

Or manually:

```bash
az deployment group create \
  -g openclaw-pre-group \
  -f bicep/main.bicep \
  -p @bicep/parameters.staging.json \
  -p containerImage="openclawpreacr.azurecr.io/openclaw:staging-latest" \
  -p acrName="openclawpreacr"
```

## Verify Permission Was Granted

```bash
# Check role assignments
az role assignment list \
  --assignee-object-id $(az identity show -g openclaw-pre-group -n openclaw-identity-staging --query principalId -o tsv) \
  --query "[?roleDefinitionName=='AcrPull']"

# Or check on the ACR directly
az role assignment list \
  --scope $(az acr show -n openclawpreacr --query id -o tsv)
```

You should see an `AcrPull` assignment for `openclaw-identity-staging`.

## Step-by-Step

1. **Grant permissions:**
   ```bash
   bash scripts/grant-acr-pull.sh openclaw-pre-group staging openclawpreacr
   ```

2. **Wait a moment** (Azure propagates role assignments):
   ```bash
   sleep 10
   ```

3. **Redeploy:**
   ```bash
   bash scripts/deploy.sh staging \
     --resource-group openclaw-pre-group \
     --registry openclawpreacr
   ```

4. **Monitor:**
   ```bash
   az containerapp logs show \
     -g openclaw-pre-group \
     -n openclaw-app-staging \
     --follow
   ```

## If Still Failing

Check that:

1. **Managed identity exists:**
   ```bash
   az identity show \
     -g openclaw-pre-group \
     -n openclaw-identity-staging
   ```

2. **ACR exists:**
   ```bash
   az acr show -n openclawpreacr
   ```

3. **Image exists in ACR:**
   ```bash
   az acr repository show-images \
     -n openclawpreacr \
     --query "[?tags[?contains(@, 'staging')]]"
   ```

4. **Role assignment is present:**
   ```bash
   az role assignment list \
     --scope $(az acr show -n openclawpreacr --query id -o tsv) \
     --query "[?principalName=='openclaw-identity-staging']"
   ```

---

## What Changed

**Commit:** `508a329` (fixed role ID) + new script

**Files:**
- ✅ `bicep/main.bicep` — Fixed role ID
- ✅ `scripts/grant-acr-pull.sh` — NEW (manual role assignment)

**Next Steps:**
1. Run `bash scripts/grant-acr-pull.sh openclaw-pre-group staging openclawpreacr`
2. Wait ~10 seconds
3. Redeploy with `bash scripts/deploy.sh staging`
4. Monitor logs

Let me know if that works!
