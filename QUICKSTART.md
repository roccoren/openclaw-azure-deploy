# OpenClaw on Azure - Quick Start Guide

## 📋 What Was Generated

✅ **Production-ready code:**
- `Dockerfile` — Optimized for Azure Container Apps with health checks
- `bicep/main.bicep` — Complete infrastructure as code
- `scripts/deploy.sh` — One-command deployment
- `scripts/build-image.sh` — Build and push Docker image
- `scripts/setup-secrets.sh` — Configure Key Vault
- `config/gateway-config.json` — OpenClaw gateway settings
- `config/channels.json` — Teams/Slack/Telegram setup

## 🚀 Quick Start (5 minutes)

### Step 1: Prerequisites
```bash
# Check you have these tools
az --version
docker --version

# Login to Azure
az login
az account set --subscription "0c8290d6-2183-4098-adba-378401263941"
```

### Step 2: Set Environment Variables
```bash
export AZURE_RESOURCE_GROUP="openclaw-rg"
export AZURE_LOCATION="westus2"
export AZURE_ENVIRONMENT="prod"
export AZURE_ACR_NAME="openclawacr"  # Must be globally unique
export DOCKER_IMAGE="$AZURE_ACR_NAME.azurecr.io/openclaw:latest"
```

### Step 3: Create Resource Group
```bash
az group create \
  --name $AZURE_RESOURCE_GROUP \
  --location $AZURE_LOCATION
```

### Step 4: Build and Push Docker Image
```bash
cd /home/roccoren/clawd/azure

# Build image
docker build -t $DOCKER_IMAGE .

# Login to ACR (creates registry if needed)
az acr create -g $AZURE_RESOURCE_GROUP -n $AZURE_ACR_NAME --sku Basic
az acr login -n $AZURE_ACR_NAME

# Push image
docker push $DOCKER_IMAGE
```

### Step 5: Configure Secrets
```bash
# Edit this with your actual API keys
bash scripts/setup-secrets.sh \
  --resource-group $AZURE_RESOURCE_GROUP \
  --anthropic-key "sk-ant-..." \
  --gateway-token "$(openssl rand -hex 32)" \
  --teams-password "your-bot-password"
```

### Step 6: Deploy Infrastructure
```bash
az deployment group create \
  --resource-group $AZURE_RESOURCE_GROUP \
  --template-file bicep/main.bicep \
  --parameters \
    environment=$AZURE_ENVIRONMENT \
    baseName=openclaw \
    containerImage=$DOCKER_IMAGE \
    acrName=$AZURE_ACR_NAME
```

### Step 7: Verify Deployment
```bash
# Get the container app URL
az containerapp show \
  -g $AZURE_RESOURCE_GROUP \
  -n openclaw-app-prod \
  --query properties.configuration.ingress.fqdn
```

## 📊 Cost Estimate

| Component | Monthly |
|-----------|---------|
| Container Apps (2 vCPU, 4GB RAM, prod) | ~$100 |
| Storage (50 GB) | ~$2 |
| Key Vault | ~$1 |
| Application Insights | ~$5 |
| **Total** | **~$108/month** |

## 🔧 Configuration Files

### `gateway-config.json`
```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-3-5-sonnet-20241022"
      }
    }
  },
  "workspace": "/data/workspace",
  "channels": {
    "teams": {
      "enabled": true
    }
  }
}
```

### `channels.json`
```json
{
  "teams": {
    "appId": "YOUR_BOT_APP_ID",
    "appPassword": "YOUR_BOT_APP_PASSWORD",
    "enabled": true
  },
  "slack": {
    "botToken": "xoxb-...",
    "enabled": false
  }
}
```

## 📝 Environment Configurations

### Dev (Minimal Cost)
```bash
az deployment group create \
  -g $RG \
  -f bicep/main.bicep \
  -p @bicep/parameters.dev.json
# Cost: ~$10/month
```

### Prod (High Availability)
```bash
az deployment group create \
  -g $RG \
  -f bicep/main.bicep \
  -p @bicep/parameters.prod.json
# Cost: ~$100/month
```

## 🧪 Testing

After deployment:

```bash
# Get container app FQDN
APP_URL=$(az containerapp show \
  -g $AZURE_RESOURCE_GROUP \
  -n openclaw-app-prod \
  --query properties.configuration.ingress.fqdn -o tsv)

# Test health endpoint
curl https://$APP_URL/health

# View logs
az containerapp logs show \
  -g $AZURE_RESOURCE_GROUP \
  -n openclaw-app-prod \
  --follow
```

## 🔐 Security Best Practices

✅ **Already configured:**
- Non-root Docker user
- Managed identities (no secrets in code)
- Azure Key Vault for sensitive data
- Network isolation via Container Apps
- Health checks and auto-restart

## 📚 Next Steps

1. **Customize gateway config** → Edit `config/gateway-config.json`
2. **Set up Teams bot** → See [Teams Integration Guide](teams-setup.md)
3. **Monitor performance** → View Application Insights in Azure Portal
4. **Scale as needed** → Adjust `bicep/parameters.prod.json` maxReplicas
5. **Backup strategy** → Configure Azure Storage backup schedule

## 🆘 Troubleshooting

**Container won't start?**
```bash
az containerapp logs show -g $RG -n openclaw-app-prod --follow
```

**Can't push to ACR?**
```bash
az acr login -n $AZURE_ACR_NAME
docker push $DOCKER_IMAGE
```

**Gateway not responding?**
```bash
# Check if container is running
az containerapp show -g $RG -n openclaw-app-prod \
  --query properties.template.containers[0].resources
```

## 📞 Support

- **Bicep Reference:** https://learn.microsoft.com/azure/azure-resource-manager/bicep
- **Container Apps Docs:** https://learn.microsoft.com/azure/container-apps
- **OpenClaw Docs:** https://docs.clawd.bot

---

**Ready?** Run `bash scripts/deploy.sh` to automate steps 3-6.
