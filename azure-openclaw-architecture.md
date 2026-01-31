# OpenClaw on Azure - Architecture

## Overview

Run OpenClaw (formerly Clawdbot) on Azure Container Apps with persistent storage and Azure AD authentication.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Azure Cloud                                     │
│                                                                             │
│  ┌──────────────┐     ┌─────────────────────────────────────────────────┐  │
│  │   Azure AD   │     │           Azure Container Apps                   │  │
│  │  (Entra ID)  │────▶│  ┌─────────────────────────────────────────┐   │  │
│  │              │     │  │         OpenClaw Container               │   │  │
│  └──────────────┘     │  │                                          │   │  │
│                       │  │  ┌──────────┐  ┌──────────┐  ┌────────┐ │   │  │
│                       │  │  │ Gateway  │  │  Agent   │  │ Skills │ │   │  │
│                       │  │  │ :18789   │  │ Runtime  │  │        │ │   │  │
│                       │  │  └────┬─────┘  └──────────┘  └────────┘ │   │  │
│                       │  │       │                                  │   │  │
│                       │  └───────┼──────────────────────────────────┘   │  │
│                       │          │                                       │  │
│                       └──────────┼───────────────────────────────────────┘  │
│                                  │                                          │
│         ┌────────────────────────┼────────────────────────┐                │
│         │                        │                        │                │
│         ▼                        ▼                        ▼                │
│  ┌─────────────┐         ┌─────────────┐         ┌─────────────┐          │
│  │ Azure Blob  │         │   Azure     │         │   Azure     │          │
│  │  Storage    │         │ Key Vault   │         │  App Gw /   │          │
│  │ (workspace) │         │  (secrets)  │         │  Front Door │          │
│  └─────────────┘         └─────────────┘         └─────────────┘          │
│                                                         │                  │
└─────────────────────────────────────────────────────────┼──────────────────┘
                                                          │
                    ┌─────────────────────────────────────┼─────────────────┐
                    │                                     │                 │
                    ▼                                     ▼                 ▼
             ┌─────────────┐                    ┌─────────────┐    ┌─────────────┐
             │   Teams     │                    │  Telegram   │    │   Slack     │
             │  Webhook    │                    │  Bot API    │    │  Socket     │
             └─────────────┘                    └─────────────┘    └─────────────┘
```

## Components

### 1. Azure Container Apps (Core)

**Purpose:** Run the OpenClaw container

**Configuration:**
- **Image:** Custom Docker image with OpenClaw installed
- **CPU/Memory:** 1 vCPU / 2 GB (adjustable)
- **Min replicas:** 1 (always running)
- **Ingress:** External, port 18789

**Environment Variables:**
```
ANTHROPIC_API_KEY     → from Key Vault
OPENCLAW_WORKSPACE    → /data/workspace
OPENCLAW_CONFIG       → /data/config
```

**Volume Mounts:**
```
/data → Azure Files share (persistent)
```

### 2. Azure Blob Storage

**Purpose:** Persistent workspace storage

**Containers:**
- `workspace/` — Agent workspace files (MEMORY.md, skills, etc.)
- `config/` — OpenClaw configuration
- `backups/` — Periodic backups

**Access:** Managed Identity (no keys in container)

### 3. Azure Key Vault

**Purpose:** Secure secrets management

**Secrets:**
- `anthropic-api-key`
- `telegram-bot-token`
- `slack-bot-token`
- `slack-app-token`
- `teams-app-password`
- `gateway-token`

**Access:** Container Apps Managed Identity

### 4. Azure AD / Entra ID

**Purpose:** Authentication for web UI

**Configuration:**
- App Registration for OpenClaw
- OAuth2 flow for Control UI access
- Optional: Restrict to specific users/groups

### 5. Networking

**Option A: Azure Front Door (Recommended)**
- Global load balancing
- WAF protection
- Custom domain + SSL
- WebSocket support ✅

**Option B: Azure Application Gateway**
- Regional load balancer
- WAF v2
- WebSocket support ✅

**Option C: Direct Container Apps Ingress**
- Simplest setup
- Built-in HTTPS
- Auto-generated domain

## Dockerfile

```dockerfile
FROM node:22-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    chromium \
    && rm -rf /var/lib/apt/lists/*

# Install OpenClaw globally
RUN npm install -g openclaw

# Create data directory
RUN mkdir -p /data/workspace /data/config

# Set environment
ENV OPENCLAW_WORKSPACE=/data/workspace
ENV OPENCLAW_CONFIG=/data/config
ENV BROWSER_PATH=/usr/bin/chromium

WORKDIR /data/workspace

# Expose gateway port
EXPOSE 18789

# Start gateway
CMD ["openclaw", "gateway", "start", "--foreground"]
```

## Infrastructure as Code (Bicep)

```bicep
// main.bicep
param location string = resourceGroup().location
param envName string = 'openclaw-env'
param appName string = 'openclaw'

// Container Apps Environment
resource containerEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: envName
  location: location
  properties: {
    zoneRedundant: false
  }
}

// Storage Account
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'openclawstorage'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
}

// File Share for persistent data
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storage
  name: 'default'
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: 'openclaw-data'
  properties: {
    shareQuota: 5 // GB
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'openclaw-kv'
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    accessPolicies: []
    enableRbacAuthorization: true
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 18789
        transport: 'http'
        allowInsecure: false
      }
      secrets: [
        {
          name: 'anthropic-key'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/anthropic-api-key'
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'openclaw'
          image: 'your-registry.azurecr.io/openclaw:latest'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            { name: 'ANTHROPIC_API_KEY', secretRef: 'anthropic-key' }
          ]
          volumeMounts: [
            { volumeName: 'data', mountPath: '/data' }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: 'data'
          storageType: 'AzureFile'
          storageName: 'openclaw-data'
        }
      ]
    }
  }
}
```

## Deployment Steps

### 1. Create Resource Group
```bash
az group create -n openclaw-rg -l westus2
```

### 2. Deploy Infrastructure
```bash
az deployment group create \
  -g openclaw-rg \
  -f main.bicep
```

### 3. Add Secrets to Key Vault
```bash
az keyvault secret set --vault-name openclaw-kv \
  --name anthropic-api-key --value "sk-ant-..."

az keyvault secret set --vault-name openclaw-kv \
  --name gateway-token --value "$(openssl rand -hex 32)"
```

### 4. Build & Push Container
```bash
az acr build -r yourregistry -t openclaw:latest .
```

### 5. Configure Channels
Update Container App environment variables for each channel (Teams, Slack, Telegram).

## Cost Estimate

| Component | SKU | Monthly Cost |
|-----------|-----|--------------|
| Container Apps | 1 vCPU, 2 GB, always-on | ~$50 |
| Storage Account | Standard LRS, 5 GB | ~$1 |
| Key Vault | Standard | ~$0.03/secret |
| Front Door (optional) | Standard | ~$35 |
| **Total** | | **~$50-85/month** |

## Comparison: Cloudflare vs Azure

| Feature | Cloudflare Moltworker | Azure OpenClaw |
|---------|----------------------|----------------|
| Container Runtime | Sandbox (proprietary) | Container Apps (standard) |
| Cold Start | 1-2 min | ~10-30 sec |
| Persistence | R2 | Azure Blob/Files |
| Auth | Cloudflare Access | Azure AD |
| Browser | Browser Rendering API | Chromium in container |
| Pricing | ~$5/mo + usage | ~$50-85/mo |
| Portability | CF-locked | Standard Docker |

## Next Steps

1. [ ] Create Azure Container Registry
2. [ ] Build OpenClaw Docker image
3. [ ] Deploy Bicep template
4. [ ] Configure Key Vault secrets
5. [ ] Set up Azure AD app registration
6. [ ] Configure Teams/Slack webhooks
7. [ ] Test and validate
