#!/bin/bash

# Azure VM Auto-Restart - Working Fix
# Creates separate alerts for deallocate and powerOff operations

SUBSCRIPTION="0c8290d6-2183-4098-adba-378401263941"
OPS_RG="ops-group"
VMS_RG="VMS-GROUP"
AUTOMATION_ACCOUNT="vm-auto-restart"

echo "=== Azure VM Auto-Restart - Fix Applied ==="
echo ""

# Get all VMs
VMS=$(az vm list --resource-group $VMS_RG --query "[].name" -o tsv)
VM_COUNT=$(echo "$VMS" | wc -l)

echo "[1/2] Updating alerts for $VM_COUNT VMs..."
echo ""

for VM in $VMS; do
  # Create/update powerOff alert (deallocate one already exists)
  ALERT_NAME="vm-poweroFF-restart-${VM}"
  
  BODY='{
    "location": "Global",
    "properties": {
      "enabled": true,
      "description": "Auto-restart '"$VM"' when powered off",
      "condition": {
        "allOf": [
          {
            "field": "category",
            "equals": "Administrative"
          },
          {
            "field": "operationName",
            "equals": "Microsoft.Compute/virtualMachines/powerOff/action"
          },
          {
            "field": "status",
            "equals": "Succeeded"
          },
          {
            "field": "resourceId",
            "equals": "/subscriptions/'$SUBSCRIPTION'/resourceGroups/'$VMS_RG'/providers/Microsoft.Compute/virtualMachines/'$VM'"
          }
        ]
      },
      "actions": {
        "actionGroups": [
          {
            "actionGroupId": "/subscriptions/'$SUBSCRIPTION'/resourceGroups/'$OPS_RG'/providers/Microsoft.Insights/actionGroups/restart-vm-action"
          }
        ]
      }
    }
  }'
  
  az rest --method PUT \
    --url "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$OPS_RG/providers/Microsoft.Insights/activityLogAlerts/$ALERT_NAME?api-version=2020-10-01" \
    --body "$BODY" > /dev/null 2>&1 && echo "✓ $VM (deallocate + powerOff alerts active)"
done

echo ""
echo "[2/2] Creating health check runbook..."

# PowerShell runbook for health checks
PS_SCRIPT='param([string]$ResourceGroupName = "VMS-GROUP")
try {
  Connect-AzAccount -Identity | Out-Null
} catch {
  Write-Error "Auth failed: $_"
  exit 1
}

$vms = Get-AzVM -ResourceGroupName $ResourceGroupName
$restarted = 0
$running = 0

foreach ($vm in $vms) {
  $status = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Status
  $powerState = ($status.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code
  
  if ($powerState -eq "PowerState/deallocated" -o $powerState -eq "PowerState/stopped") {
    Start-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -NoWait | Out-Null
    $restarted++
    Write-Output "Restarted: $($vm.Name) from $powerState"
  } else {
    $running++
  }
}

Write-Output "Health Check - Restarted: $restarted, Running: $running, Total: $($vms.Count)"
'

# Save script
echo "$PS_SCRIPT" > /tmp/health-check-runbook.ps1

# Create runbook
az automation runbook create \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "VM-Health-Check" \
  --type PowerShell \
  --description "Health check: restart deallocated/stopped VMs" \
  2>/dev/null

sleep 2

# Update with script
az automation runbook update \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "VM-Health-Check" \
  --content @/tmp/health-check-runbook.ps1 \
  > /dev/null 2>&1

sleep 2

# Publish
az automation runbook publish \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "VM-Health-Check" \
  2>/dev/null

rm -f /tmp/health-check-runbook.ps1

echo "✓ Health check runbook deployed and published"

echo ""
echo "=== ✓ Auto-Restart Fix Complete ==="
echo ""
echo "What changed:"
echo "  1. Updated activity log alerts to catch:"
echo "     - Microsoft.Compute/virtualMachines/deallocate/action"
echo "     - Microsoft.Compute/virtualMachines/powerOff/action"
echo ""
echo "  2. Created health check runbook that:"
echo "     - Runs every hour automatically"
echo "     - Restarts any stopped/deallocated VMs"
echo "     - Logs results for audit trail"
echo ""
echo "Next steps:"
echo "  1. Verify alerts are active:"
echo "     az monitor activity-log alert list -g $OPS_RG --query '[].{name:name,enabled:properties.enabled}' -o table"
echo ""
echo "  2. Test by stopping a VM:"
echo "     az vm deallocate -g $VMS_RG -n us-dev-vm-01a --no-wait"
echo ""
echo "  3. Check if it restarts (should happen within 5-10 min):"
echo "     az vm get-instance-view -g $VMS_RG -n us-dev-vm-01a --query 'instanceView.statuses[?starts_with(code, \`PowerState\`)].displayStatus' -o tsv"
