# openclaw-azure-deploy - Complete Enhancement Guide

Welcome! This project now includes **configuration-first deployment** with Azure Key Vault support.

## 🚀 Start Here

Choose your path:

### 📖 I want to understand what changed
→ Read **`ENHANCEMENTS.md`** (2-minute overview)

### 🛠️ I want to deploy right now
→ Follow **`DEPLOYMENT-CHECKLIST.md`** (step-by-step guide)

### 🔧 I want to understand the configuration system
→ Read **`CONFIGURATION.md`** (detailed guide with examples)

### 📋 I want to know all the variables
→ Check **`.env.example`** (complete reference with comments)

---

## 🎯 Quick Summary

**The Problem We Solved:**
- Previous deployments would fail because configuration files weren't ready when the container started
- No reliable way to provide secrets to the container
- Manual intervention required to get things working

**The Solution:**
- Container now reads secrets from Azure Key Vault or environment variables at startup
- Automatically generates configuration files before starting the gateway
- Validates everything before startup
- One-command deployment: `bash scripts/deploy.sh prod`

---

## 📚 Documentation Structure

```
openclaw-azure-deploy/
│
├── 📄 README.md
│   └── Original project overview (high-level)
│
├── 📄 QUICKSTART.md
│   └── Original quick start (useful reference)
│
├── 📄 ENHANCEMENTS.md ⭐ START HERE
│   └── What changed, how it works, benefits
│       (2-3 minutes to read)
│
├── 📄 CONFIGURATION.md
│   └── Detailed setup guide, environment variables,
│       troubleshooting, how to provide secrets
│       (15 minutes to read)
│
├── 📄 DEPLOYMENT-CHECKLIST.md
│   └── Step-by-step deployment guide with commands
│       Pre-deployment, deployment, testing, rollback
│       (30 minutes to complete)
│
├── 📄 .env.example
│   └── Complete environment variables reference
│       Copy to .env and fill in your values
│
├── 📄 azure-openclaw-architecture.md
│   └── Architecture diagrams and concepts
│
└── 📂 scripts/
    ├── entrypoint-v2.sh ⭐ ENHANCED
    │   └── Container startup script (reads KV, generates config)
    │
    ├── validate-deployment.sh ⭐ NEW
    │   └── Pre-deployment validator (catch issues early)
    │
    ├── deploy.sh
    │   └── One-command deployment
    │
    ├── build-image.sh
    │   └── Docker image build and push
    │
    ├── setup-secrets.sh
    │   └── Key Vault secret management
    │
    └── healthcheck.sh
        └── Container health check
```

---

## 🔄 How Configuration Works

### Startup Flow

```
1. Container starts (dumb-init as PID 1)
                    ↓
2. entrypoint-v2.sh runs
                    ↓
3. Read secrets (Key Vault → env vars → defaults)
                    ↓
4. Generate /data/config/openclaw.json
                    ↓
5. Generate /data/config/channels.json
                    ↓
6. Validate configuration
                    ↓
7. Start OpenClaw gateway (foreground)
```

### Configuration Priority

1. **Environment Variables** (highest priority)
   - Set via `az containerapp update --set-env-vars`
   - Best for: Secrets, per-instance customization

2. **Azure Key Vault** (recommended for production)
   - Container reads via managed identity
   - Best for: Secure secret storage
   - Requires: `AZURE_KEYVAULT_NAME` env var

3. **Generated Defaults** (fallback)
   - Gateway token auto-generated if not provided
   - Best for: Optional settings

---

## ⚡ 5-Minute Getting Started

### Step 1: Prepare Environment (2 min)
```bash
cd openclaw-azure-deploy

# Copy environment template
cp .env.example .env

# Edit with your values
nano .env
```

**Must set:**
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `AZURE_KEYVAULT_NAME`
- `ANTHROPIC_API_KEY`

### Step 2: Validate Configuration (1 min)
```bash
# Load environment
source .env

# Run validator
bash scripts/validate-deployment.sh
```

All checks should pass (warnings are OK).

### Step 3: Deploy (2 min)
```bash
# Populate Key Vault
bash scripts/setup-secrets.sh $AZURE_KEYVAULT_NAME --file .env

# Deploy to Azure
bash scripts/deploy.sh prod \
  --resource-group $AZURE_RESOURCE_GROUP \
  --registry $AZURE_ACR_NAME
```

### Step 4: Verify
```bash
# Check logs
az containerapp logs show \
  -g $AZURE_RESOURCE_GROUP \
  -n openclaw-app-prod \
  --follow
```

That's it! 🎉

---

## 🔐 Security Best Practices

✅ **DO:**
- Store secrets in Azure Key Vault
- Use managed identity for authentication
- Never commit `.env` file to git (add to .gitignore)
- Use separate Key Vaults for dev/staging/prod
- Rotate secrets regularly

❌ **DON'T:**
- Put secrets in environment variables (unless temporary)
- Commit `.env` file to git
- Share GATEWAY_TOKEN with unauthorized users
- Use same Key Vault for multiple environments
- Store plaintext secrets in code

---

## 🛠️ Common Tasks

### Update Configuration Without Redeploying

```bash
# Change environment variable
az containerapp update \
  -g $RESOURCE_GROUP \
  -n openclaw-app-prod \
  --set-env-vars OPENCLAW_LOG_LEVEL="debug"

# Container will pick up new config on restart
az containerapp revision restart \
  -g $RESOURCE_GROUP \
  -n openclaw-app-prod
```

### View Startup Logs

```bash
# Stream logs in real-time
az containerapp logs show \
  -g $RESOURCE_GROUP \
  -n openclaw-app-prod \
  --follow

# Look for:
# "OpenClaw Container Entrypoint v2"
# "Generating gateway configuration"
# "Starting OpenClaw gateway"
```

### Check Generated Configuration

```bash
# Connect to running container
az containerapp exec \
  -g $RESOURCE_GROUP \
  -n openclaw-app-prod

# Inside container:
cat /data/config/openclaw.json
cat /data/config/channels.json
```

### Rollback to Previous Revision

```bash
# List revisions
az containerapp revision list \
  -g $RESOURCE_GROUP \
  -n openclaw-app-prod

# Activate previous revision
az containerapp revision activate \
  -g $RESOURCE_GROUP \
  -n openclaw-app-prod \
  --revision openclaw-app-prod--<revision-number>
```

---

## 📊 File Summary

| File | Purpose | Size | Status |
|------|---------|------|--------|
| `ENHANCEMENTS.md` | Overview of changes | 10.5 KB | ⭐ NEW |
| `CONFIGURATION.md` | Setup and config guide | 11.9 KB | ⭐ NEW |
| `DEPLOYMENT-CHECKLIST.md` | Step-by-step checklist | 9.5 KB | ⭐ NEW |
| `.env.example` | Environment variables | 5.5 KB | ⭐ NEW |
| `scripts/entrypoint-v2.sh` | Container startup | 10.7 KB | ⭐ ENHANCED |
| `scripts/validate-deployment.sh` | Pre-deployment check | 12.1 KB | ⭐ NEW |
| `config/gateway-config.template.json` | Gateway template | 2 KB | ⭐ NEW |
| `config/channels.template.json` | Channels template | 590 B | ⭐ NEW |
| `Dockerfile` | Container image | 5.3 KB | 🔄 UPDATED |
| `README.md` | Original docs | 6.8 KB | Original |
| `QUICKSTART.md` | Quick start | 4.5 KB | Original |

---

## ✅ What You Get

✨ **Reliability**
- Configuration validated before startup
- Clear error messages if something's wrong
- No more "config not found" failures

🔐 **Security**
- Secrets in Azure Key Vault (encrypted)
- Managed identity authentication
- No API keys in code or logs

🎛️ **Flexibility**
- Supports env vars and Key Vault
- Works with all channels (Teams, Slack, Telegram, etc.)
- Easy to update without redeploying

📋 **Operability**
- One-command deployment
- Pre-deployment validation
- Step-by-step checklist
- Detailed logs for troubleshooting

---

## 🤔 FAQ

**Q: Do I need to use Azure Key Vault?**  
A: No, you can use environment variables instead. But Key Vault is more secure and recommended for production.

**Q: How do I provide secrets?**  
A: Option 1 (Simple): `az containerapp update --set-env-vars ANTHROPIC_API_KEY=...`  
Option 2 (Secure): Store in Key Vault, container reads via managed identity

**Q: What if I update the configuration?**  
A: Changes take effect on the next container restart. No redeployment needed.

**Q: How do I troubleshoot?**  
A: Check logs: `az containerapp logs show ... --follow`

**Q: Can I rollback?**  
A: Yes! Use `az containerapp revision activate` to switch to a previous version.

**Q: What channels are supported?**  
A: Teams, Slack, Telegram, Discord, Google Chat, Signal, WhatsApp, and more.

---

## 📞 Support

**Stuck?** Check these resources in order:
1. `ENHANCEMENTS.md` — overview of what changed
2. `CONFIGURATION.md` — detailed setup guide
3. `DEPLOYMENT-CHECKLIST.md` — step-by-step instructions
4. Container logs — `az containerapp logs show ... --follow`
5. Azure Portal → Application Insights → Live Metrics

---

## 🎓 Learning Resources

- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep)
- [Azure Key Vault](https://learn.microsoft.com/azure/key-vault)
- [OpenClaw Documentation](https://docs.openclaw.ai)

---

## 📝 Git Information

**Latest Commit:**
```
bfbd9c6 feat: Configuration-first deployment with Key Vault support
```

**Files Changed:** 9 files (+2,331 lines)

**Branch:** main

**Status:** ✅ Production Ready

---

## 🎉 You're Ready!

**Next Steps:**
1. Read `ENHANCEMENTS.md` (2 minutes)
2. Copy `.env.example` to `.env` and fill in values
3. Run `bash scripts/validate-deployment.sh`
4. Follow `DEPLOYMENT-CHECKLIST.md`
5. Deploy with `bash scripts/deploy.sh prod`

**Questions?** Read the docs — they're comprehensive!

---

**Version:** 2.0 (Configuration-First)  
**Status:** ✅ Ready to Deploy  
**Updated:** 2026-02-02
