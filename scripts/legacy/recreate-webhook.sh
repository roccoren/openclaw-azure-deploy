#!/bin/bash

# Recreate the webhook for the restart automation

SUBSCRIPTION="0c8290d6-2183-4098-adba-378401263941"
OPS_RG="ops-group"
AUTOMATION_ACCOUNT="vm-auto-restart"

echo "=== Recreating Webhook ==="

# Delete old webhook if exists
az automation webhook delete \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "restart-vm-webhook" \
  --yes 2>/dev/null || true

echo "Creating new webhook..."

# Create new webhook
WEBHOOK=$(az automation webhook create \
  --resource-group $OPS_RG \
  --automation-account-name $AUTOMATION_ACCOUNT \
  --name "restart-vm-webhook" \
  --runbook-name "Restart-DeallocatedVM" \
  --is-enabled true \
  -o json)

WEBHOOK_URL=$(echo "$WEBHOOK" | jq -r '.properties.uri')
WEBHOOK_EXPIRY=$(echo "$WEBHOOK" | jq -r '.properties.expiryTime')

echo "✓ Webhook created"
echo "  URL: ${WEBHOOK_URL:0:80}..."
echo "  Expiry: $WEBHOOK_EXPIRY"

# Update the action group to use the new webhook URL
echo ""
echo "Updating action group with new webhook..."

az rest --method PUT \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$OPS_RG/providers/Microsoft.Insights/actionGroups/restart-vm-action?api-version=2023-01-01" \
  --body "{
    \"location\": \"Global\",
    \"properties\": {
      \"groupShortName\": \"RestartVM\",
      \"enabled\": true,
      \"webhookReceivers\": [
        {
          \"name\": \"restart-webhook\",
          \"serviceUri\": \"$WEBHOOK_URL\",
          \"useCommonAlertSchema\": false,
          \"useAadAuth\": false
        }
      ]
    }
  }" > /dev/null 2>&1

echo "✓ Action group updated"

echo ""
echo "=== Webhook Setup Complete ==="
echo "Webhook will expire on: $WEBHOOK_EXPIRY"
