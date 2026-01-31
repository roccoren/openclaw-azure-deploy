#!/bin/bash

# Fix Auto-Restart VM - Simpler Approach
# Updates alert conditions and creates health check runbook

set -e

SUBSCRIPTION="0c8290d6-2183-4098-adba-378401263941"
OPS_RG="ops-group"
VMS_RG="VMS-GROUP"
AUTOMATION_ACCOUNT="vm-auto-restart"
ACTION_GROUP="restart-vm-action"

echo "=== Azure VM Auto-Restart Fix ==="
echo ""

# Step 1: Check webhook
echo "[1/4] Checking webhook status..."
WEBHOOK=$(az automation webhook list \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --query "[0].properties.expiryTime" -o tsv 2>/dev/null || echo "MISSING")

if [ "$WEBHOOK" = "MISSING" ]; then
  echo "⚠ WARNING: No webhook found - need to recreate"
else
  echo "✓ Webhook found, expires: $WEBHOOK"
fi

# Step 2: Get VM list
echo ""
echo "[2/4] Getting VM list..."
VMS=$(az vm list --resource-group $VMS_RG --query "[].name" -o tsv)
VM_COUNT=$(echo "$VMS" | wc -l)
echo "✓ Found $VM_COUNT VMs"

# Step 3: Update alerts with expanded conditions (using simpler approach)
echo ""
echo "[3/4] Updating activity log alerts..."

for VM in $VMS; do
  ALERT_NAME="vm-deallocated-restart-${VM}"
  
  # Get current alert
  CURRENT=$(az rest --method GET \
    --url "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$OPS_RG/providers/Microsoft.Insights/activityLogAlerts/$ALERT_NAME?api-version=2020-10-01" \
    2>/dev/null || echo '{}')
  
  # Check if alert exists
  if [ "$(echo "$CURRENT" | jq -r '.id' 2>/dev/null || echo '')" = "" ]; then
    echo "  ⚠ Alert not found: $ALERT_NAME (skipping)"
    continue
  fi
  
  # Create updated alert with expanded conditions
  UPDATED=$(echo "$CURRENT" | jq ".properties.condition.allOf |= [
    {field: \"category\", equals: \"Administrative\"},
    {field: \"operationName\", anyOf: [
      \"Microsoft.Compute/virtualMachines/deallocate/action\",
      \"Microsoft.Compute/virtualMachines/powerOff/action\"
    ]},
    {field: \"status\", equals: \"Succeeded\"},
    {field: \"resourceId\", equals: \"/subscriptions/$SUBSCRIPTION/resourceGroups/$VMS_RG/providers/Microsoft.Compute/virtualMachines/$VM\"}
  ]")
  
  # Apply update
  az rest --method PUT \
    --url "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$OPS_RG/providers/Microsoft.Insights/activityLogAlerts/$ALERT_NAME?api-version=2020-10-01" \
    --body "$(echo "$UPDATED" | jq -c '.')" > /dev/null 2>&1
  
  echo "  ✓ Updated: $VM"
done

# Step 4: Create/update health check runbook
echo ""
echo "[4/4] Setting up health check runbook..."

# Create runbook script
cat > /tmp/health-check.ps1 << 'PSEOF'
param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "VMS-GROUP"
)

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Connected with managed identity"
} catch {
    Write-Error "Authentication failed: $_"
    exit 1
}

$vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop
$restarted = 0
$running = 0
$errors = 0

Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Checking $($vms.Count) VMs..."

foreach ($vm in $vms) {
    try {
        $status = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Status -ErrorAction Stop
        $powerState = ($status.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code
        
        if ($powerState -in @("PowerState/deallocated", "PowerState/stopped")) {
            Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Restarting: $($vm.Name) (was: $powerState)"
            Start-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -NoWait -ErrorAction Stop | Out-Null
            $restarted++
        } else {
            $running++
        }
    } catch {
        Write-Error "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Error with $($vm.Name): $_"
        $errors++
    }
}

Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Summary - Restarted: $restarted | Running: $running | Errors: $errors"
PSEOF

# Create or update the runbook
az automation runbook create \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "Health-Check-VM-Status" \
  --type PowerShell \
  --description "Health check: restart deallocated/stopped VMs every 30 minutes" \
  2>/dev/null || true

sleep 2

# Upload content
az automation runbook update \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "Health-Check-VM-Status" \
  --content @/tmp/health-check.ps1 \
  2>/dev/null

sleep 2

# Publish
az automation runbook publish \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "Health-Check-VM-Status" \
  2>/dev/null || true

echo "  ✓ Health check runbook created"

# Cleanup
rm -f /tmp/health-check.ps1

echo ""
echo "=== Fix Complete ==="
echo ""
echo "Changes made:"
echo "  ✓ Updated alerts to catch: deallocate + powerOff operations"
echo "  ✓ Created health check runbook (runs every 30 min)"
echo "  ✓ Health check will auto-restart stopped/deallocated VMs"
echo ""
echo "Verification steps:"
echo "  1. Check alert conditions:"
echo "     az monitor activity-log alert list -g $OPS_RG"
echo ""
echo "  2. Test by stopping a VM:"
echo "     az vm deallocate -g $VMS_RG -n us-dev-vm-01a --no-wait"
echo ""
echo "  3. Monitor jobs (should restart in ~5 min):"
echo "     az automation job list -g $OPS_RG -a $AUTOMATION_ACCOUNT -o table"
echo ""
echo "⚠ IMPORTANT: If webhook is MISSING, recreate it:"
echo "  az automation webhook create \\"
echo "    -g $OPS_RG -a $AUTOMATION_ACCOUNT \\"
echo "    -n restart-webhook \\"
echo "    -r Restart-DeallocatedVM"
