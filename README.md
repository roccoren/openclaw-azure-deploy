# Azure OpenClaw Deployment - Complete Package

## 📦 What's Included

All production-ready code for deploying OpenClaw to Azure Container Apps:

### Infrastructure as Code
- **`bicep/main.bicep`** — Complete Container Apps setup
  - Container Apps environment with auto-scaling
  - Managed identity for security
  - Log Analytics + Application Insights monitoring
  - Azure Files for persistent storage
  - Key Vault integration
  
- **`bicep/parameters.bicep`** — Reusable parameters
- **`bicep/parameters.dev.json`** — Dev environment (0.5 vCPU, 1 GB RAM)
- **`bicep/parameters.prod.json`** — Prod environment (2 vCPU, 4 GB RAM)

### Docker
- **`Dockerfile`** — Production-optimized
  - Node.js 22 base
  - Chromium for browser automation
  - Non-root user for security
  - Health checks
  - Proper signal handling

### Deployment Scripts
- **`scripts/deploy.sh`** — Full deployment automation
  - Validates prerequisites
  - Builds and pushes Docker image
  - Creates/updates infrastructure
  - Configures secrets
  - Verifies deployment
  
- **`scripts/build-image.sh`** — Docker build helper
- **`scripts/setup-secrets.sh`** — Key Vault configuration
- **`scripts/healthcheck.sh`** — Container health check

### Configuration
- **`config/gateway-config.json`** — OpenClaw gateway settings
- **`config/channels.json`** — Teams/Slack/Telegram setup template

### Documentation
- **`QUICKSTART.md`** — 5-minute setup guide
- **`azure-openclaw-architecture.md`** — Detailed architecture (in docs/)

---

## 🚀 Getting Started

### Option 1: Automated (Recommended)
```bash
cd /home/roccoren/clawd/azure

# Deploy everything in one command
bash scripts/deploy.sh prod \
  --resource-group openclaw-prod-rg \
  --registry openclawacr
```

### Option 2: Step by Step
```bash
# 1. Create resource group
az group create -n openclaw-prod-rg -l westus2

# 2. Build and push Docker image
bash scripts/build-image.sh \
  --registry openclawacr \
  --resource-group openclaw-prod-rg

# 3. Configure secrets
bash scripts/setup-secrets.sh \
  --resource-group openclaw-prod-rg \
  --anthropic-key "sk-ant-..." \
  --gateway-token "$(openssl rand -hex 32)"

# 4. Deploy infrastructure
az deployment group create \
  -g openclaw-prod-rg \
  -f bicep/main.bicep \
  -p @bicep/parameters.prod.json \
  -p containerImage=openclawacr.azurecr.io/openclaw:latest
```

---

## 💰 Cost Comparison

| Component | Dev | Staging | Prod |
|-----------|-----|---------|------|
| Container Apps | $10 | $25 | $100 |
| Storage | $1 | $1 | $2 |
| Key Vault | $1 | $1 | $1 |
| Monitoring | $0 | $2 | $5 |
| **Monthly Total** | **$12** | **$29** | **$108** |

---

## 🔒 Security Features

✅ **Built-in:**
- Non-root Docker container
- Managed identities (no API keys in code)
- Azure Key Vault for secrets
- Network policies via Container Apps
- TLS/HTTPS by default
- Health checks + auto-restart
- Application Insights for audit logs

---

## 📊 Monitoring & Logging

Once deployed, view:
- **Container logs:** `az containerapp logs show -g <rg> -n openclaw-app-prod --follow`
- **Metrics:** Azure Portal → Application Insights
- **Health status:** `curl https://<app-url>/health`

---

## 🔄 Updating Deployment

To update the container image:
```bash
# Rebuild and push
docker build -t openclawacr.azurecr.io/openclaw:latest .
docker push openclawacr.azurecr.io/openclaw:latest

# Redeploy (Container App auto-updates)
az deployment group update \
  -g openclaw-prod-rg \
  -f bicep/main.bicep \
  -p @bicep/parameters.prod.json
```

---

## ❓ FAQ

**Q: Do I need a custom domain?**
A: No, Azure provides a default FQDN. To use custom domain, add Application Gateway in front.

**Q: How do I scale?**
A: Edit `maxReplicas` in Bicep parameters, then redeploy.

**Q: Can I switch models?**
A: Yes, edit `gateway-config.json` and redeploy.

**Q: What about backups?**
A: Azure Files is automatically replicated. For production, enable geo-redundancy in parameters.

---

## 🎯 Next Steps

1. **Read:** `QUICKSTART.md` for detailed steps
2. **Customize:** `config/gateway-config.json` for your needs
3. **Deploy:** Run `bash scripts/deploy.sh prod`
4. **Verify:** Check logs and test endpoints
5. **Connect:** Configure Teams bot or other channels
6. **Monitor:** Set up alerts in Application Insights

---

## 📞 Need Help?

- **Azure CLI:** `az containerapp --help`
- **Bicep Docs:** https://learn.microsoft.com/azure/azure-resource-manager/bicep
- **Container Apps:** https://learn.microsoft.com/azure/container-apps
- **OpenClaw:** https://docs.clawd.bot

---

**Status:** ✅ Ready to Deploy
