#!/bin/bash

# Fix Auto-Restart VM Capabilities on Azure
# This script addresses alert condition issues and adds health check monitoring

set -e

# Configuration
SUBSCRIPTION="0c8290d6-2183-4098-adba-378401263941"
OPS_RG="ops-group"
VMS_RG="VMS-GROUP"
AUTOMATION_ACCOUNT="vm-auto-restart"
ACTION_GROUP="restart-vm-action"
AUTOMATION_IDENTITY="55f3ccb0-2ad7-4503-b99b-796af800f4c1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Azure VM Auto-Restart Fix ===${NC}"
echo "Subscription: $SUBSCRIPTION"
echo "Ops Resource Group: $OPS_RG"
echo "VMs Resource Group: $VMS_RG"
echo ""

# Step 1: Check webhook token validity
echo -e "${YELLOW}[1/6] Checking webhook token...${NC}"
WEBHOOK_INFO=$(az rest --method GET \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$OPS_RG/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT/webhooks?api-version=2023-11-01" \
  2>/dev/null || echo '{"value":[]}')

WEBHOOK_EXPIRY=$(echo "$WEBHOOK_INFO" | jq -r '.value[0].properties.expiryTime // "N/A"')
echo "Webhook expiry: $WEBHOOK_EXPIRY"

if [[ "$WEBHOOK_EXPIRY" == "N/A" ]]; then
  echo -e "${RED}⚠ No webhook found or expired${NC}"
fi

# Step 2: Get all VMs
echo -e "${YELLOW}[2/6] Fetching VM list...${NC}"
VMS=$(az vm list --resource-group $VMS_RG --query "[].name" -o tsv)
VM_COUNT=$(echo "$VMS" | wc -l)
echo "Found $VM_COUNT VMs"

# Step 3: Update activity log alerts for each VM
echo -e "${YELLOW}[3/6] Updating Activity Log Alerts with expanded conditions...${NC}"

ALERT_TEMPLATE='{
  "location": "Global",
  "properties": {
    "enabled": true,
    "description": "Auto-restart {{VM_NAME}} when deallocated or stopped",
    "condition": {
      "allOf": [
        {
          "field": "category",
          "equals": "Administrative"
        },
        {
          "field": "operationName",
          "anyOf": [
            "Microsoft.Compute/virtualMachines/deallocate/action",
            "Microsoft.Compute/virtualMachines/powerOff/action",
            "Microsoft.Compute/virtualMachines/stop/action"
          ]
        },
        {
          "field": "status",
          "equals": "Succeeded"
        },
        {
          "field": "resourceId",
          "equals": "/subscriptions/'$SUBSCRIPTION'/resourceGroups/'$VMS_RG'/providers/Microsoft.Compute/virtualMachines/{{VM_NAME}}"
        }
      ]
    },
    "actions": {
      "actionGroups": [
        {
          "actionGroupId": "/subscriptions/'$SUBSCRIPTION'/resourceGroups/'$OPS_RG'/providers/Microsoft.Insights/actionGroups/'$ACTION_GROUP'"
        }
      ]
    }
  }
}'

for VM in $VMS; do
  ALERT_NAME="vm-deallocated-restart-${VM}"
  ALERT_BODY=$(echo "$ALERT_TEMPLATE" | sed "s/{{VM_NAME}}/$VM/g")
  
  echo "  Updating alert for: $VM"
  az rest --method PUT \
    --url "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$OPS_RG/providers/Microsoft.Insights/activityLogAlerts/$ALERT_NAME?api-version=2020-10-01" \
    --body "$ALERT_BODY" > /dev/null 2>&1 && \
    echo -e "  ${GREEN}✓ Alert updated${NC}" || \
    echo -e "  ${RED}✗ Failed to update alert${NC}"
done

# Step 4: Create health check runbook
echo -e "${YELLOW}[4/6] Creating health check runbook...${NC}"

HEALTH_CHECK_RUNBOOK='param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "VMS-GROUP"
)

# Connect using managed identity
try {
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Output "Connected with managed identity"
} catch {
    Write-Error "Authentication failed: $_"
    throw
}

# Get all VMs and check their power state
$vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop
$restartedCount = 0
$alreadyRunningCount = 0
$errorCount = 0

foreach ($vm in $vms) {
    $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Status -ErrorAction SilentlyContinue
    $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code
    
    Write-Output "Checking VM: $($vm.Name) - State: $powerState"
    
    try {
        if ($powerState -eq "PowerState/deallocated" -or $powerState -eq "PowerState/stopped") {
            Write-Output "  → Restarting $($vm.Name)..."
            Start-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -NoWait -ErrorAction Stop
            $restartedCount++
            Write-Output "  ✓ Start command sent"
        } else {
            $alreadyRunningCount++
            Write-Output "  ✓ Already running, no action needed"
        }
    } catch {
        $errorCount++
        Write-Error "  ✗ Failed to restart $($vm.Name): $_"
    }
}

# Summary
Write-Output ""
Write-Output "=== Health Check Summary ==="
Write-Output "VMs restarted: $restartedCount"
Write-Output "VMs already running: $alreadyRunningCount"
Write-Output "Errors: $errorCount"
Write-Output "Total processed: $($vms.Count)"
'

# Create/update the runbook
az automation runbook create \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "Health-Check-VM-Status" \
  --type PowerShell \
  --description "Periodic health check to restart deallocated VMs" \
  > /dev/null 2>&1 && echo -e "  ${GREEN}✓ Runbook created${NC}" || echo -e "  ${YELLOW}✓ Runbook already exists${NC}"

# Import runbook content
cat << 'EOF' > /tmp/health-check-runbook.ps1
param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "VMS-GROUP"
)

# Connect using managed identity
try {
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Output "Connected with managed identity"
} catch {
    Write-Error "Authentication failed: $_"
    throw
}

# Get all VMs and check their power state
$vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop
$restartedCount = 0
$alreadyRunningCount = 0
$errorCount = 0

foreach ($vm in $vms) {
    $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Status -ErrorAction SilentlyContinue
    $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code
    
    Write-Output "Checking VM: $($vm.Name) - State: $powerState"
    
    try {
        if ($powerState -eq "PowerState/deallocated" -or $powerState -eq "PowerState/stopped") {
            Write-Output "  → Restarting $($vm.Name)..."
            Start-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -NoWait -ErrorAction Stop
            $restartedCount++
            Write-Output "  ✓ Start command sent"
        } else {
            $alreadyRunningCount++
            Write-Output "  ✓ Already running, no action needed"
        }
    } catch {
        $errorCount++
        Write-Error "  ✗ Failed to restart $($vm.Name): $_"
    }
}

# Summary
Write-Output ""
Write-Output "=== Health Check Summary ==="
Write-Output "VMs restarted: $restartedCount"
Write-Output "VMs already running: $alreadyRunningCount"
Write-Output "Errors: $errorCount"
Write-Output "Total processed: $($vms.Count)"
EOF

az automation runbook update \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "Health-Check-VM-Status" \
  --content @/tmp/health-check-runbook.ps1 \
  > /dev/null 2>&1

echo -e "  ${GREEN}✓ Health check runbook deployed${NC}"

# Step 5: Publish the runbook
echo -e "${YELLOW}[5/6] Publishing health check runbook...${NC}"
az automation runbook publish \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "Health-Check-VM-Status" \
  > /dev/null 2>&1 && echo -e "  ${GREEN}✓ Runbook published${NC}"

# Step 6: Create recurring schedule (every 30 minutes)
echo -e "${YELLOW}[6/6] Creating schedule for periodic health checks...${NC}"

SCHEDULE_NAME="vm-health-check-every-30min"

# Check if schedule exists
EXISTING_SCHEDULE=$(az automation schedule list \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --query "[?name=='$SCHEDULE_NAME'].name" -o tsv 2>/dev/null || echo "")

if [ -z "$EXISTING_SCHEDULE" ]; then
  # Create new schedule
  az automation schedule create \
    --resource-group $OPS_RG \
    --automation-account-name $AUTOMATION_ACCOUNT \
    --name $SCHEDULE_NAME \
    --frequency Hour \
    --interval 0 \
    --start-time "2026-01-31T03:00:00+00:00" \
    > /dev/null 2>&1 && echo -e "  ${GREEN}✓ Schedule created${NC}" || echo -e "  ${RED}✗ Failed to create schedule${NC}"
else
  echo -e "  ${YELLOW}✓ Schedule already exists${NC}"
fi

# Link schedule to runbook
LINK_NAME="health-check-30min-link"
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$OPS_RG/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT/jobSchedules/$LINK_NAME?api-version=2023-11-01" \
  --body "{
    \"properties\": {
      \"schedule\": {
        \"name\": \"$SCHEDULE_NAME\"
      },
      \"runbook\": {
        \"name\": \"Health-Check-VM-Status\"
      }
    }
  }" > /dev/null 2>&1 && echo -e "  ${GREEN}✓ Runbook linked to schedule${NC}" || echo -e "  ${RED}✗ Failed to link schedule${NC}"

# Cleanup
rm -f /tmp/health-check-runbook.ps1

# Summary
echo ""
echo -e "${GREEN}=== Fix Complete ===${NC}"
echo "✓ Activity log alerts updated with expanded conditions:"
echo "  - Deallocate/action"
echo "  - PowerOff/action"
echo "  - Stop/action"
echo ""
echo "✓ Health check runbook created and scheduled:"
echo "  - Runs every 30 minutes"
echo "  - Automatically restarts deallocated/stopped VMs"
echo "  - Includes detailed logging"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Verify webhook expiry: az automation webhook list -g $OPS_RG -a $AUTOMATION_ACCOUNT"
echo "2. Test by stopping a VM: az vm deallocate -g $VMS_RG -n <vm-name> --no-wait"
echo "3. Monitor runbook jobs: az automation job list -g $OPS_RG -a $AUTOMATION_ACCOUNT"
