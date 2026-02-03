# 🦞 OpenClaw Azure Deployment

> **🤖 Built entirely by AI** — This project was created by [OpenClaw](https://openclaw.ai), an AI-powered assistant running Claude. Every script, configuration, and documentation file was generated through natural language conversations.

Deploy OpenClaw to Azure VMs or Azure Container Apps with a single command.

---

## 🤖 For AI Agents

**If you're an AI agent** (Claude, GPT, Codex, OpenClaw, or any LLM-based assistant), read [`AGENT.md`](AGENT.md) for deployment instructions optimized for you.

**Quick agent prompt:**
> Read AGENT.md in this repository and deploy OpenClaw to Azure using the VM option in westus2.

**OpenClaw skill:** Install `azure-deploy.skill` for native skill integration.

---

## 🚀 Quick Start

### Deploy to Azure VM (Recommended)

```bash
# Basic deployment with spot pricing
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2

# With GitHub Copilot auth token
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --auth-token "ghu_xxxxxxxxxxxx"

# Dry run (preview commands without executing)
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 --dry-run
```

### Deploy to Azure Container Apps

```bash
python scripts/deploy-openclaw.py aca --name my-openclaw --location westus2
```

---

## 📋 Prerequisites

- Python 3.8+
- Azure CLI (`az`) logged in
- SSH public key in `~/.ssh/` (auto-detected)

```bash
# Login to Azure
az login

# Verify
az account show
```

---

## 📁 Project Structure

```
openclaw-azure-deploy/
├── AGENT.md                    # 🤖 Agent-readable deployment instructions
├── azure-deploy.skill          # 📦 OpenClaw skill package
├── azure-deploy/               # Skill source files
│   ├── SKILL.md
│   └── scripts/
├── scripts/
│   ├── deploy-openclaw.py      # 🎯 Main deployment script (VM + ACA)
│   └── legacy/                 # Old bash scripts (deprecated)
├── bicep/                      # Azure Bicep templates (for ACA)
│   ├── main.bicep
│   └── parameters.*.json
├── config/                     # Configuration templates
│   ├── gateway-config.json
│   └── channels.json
├── docs/
│   ├── azure-openclaw-architecture.md
│   └── legacy/                 # Old documentation
├── Dockerfile                  # Container image for ACA
└── README.md
```

---

## ⚙️ VM Deployment Options

| Option | Default | Description |
|--------|---------|-------------|
| `--name` | (required) | Deployment name (used for RG, VM, VNet, etc.) |
| `--location` | (required) | Azure region (e.g., `westus2`, `eastus`) |
| `--resource-group` | `<name>-group` | Existing resource group to use |
| `--no-spot` | spot enabled | Use regular pricing instead of spot |
| `--vm-size` | `Standard_D2als_v6` | VM size (2 vCPU, 4 GB RAM) |
| `--os-disk-size` | `128` | OS disk size in GB |
| `--auth-token` | none | GitHub Copilot or provider auth token |
| `--vnet-name` | auto-created | Existing VNet to reuse |
| `--subnet-name` | auto-created | Existing subnet to reuse |
| `--ssh-key` | auto-detected | Path to SSH public key |
| `--admin-username` | `$USER` | VM admin username |
| `--dry-run` | false | Preview commands without executing |

---

## ⚙️ Container Apps Options

| Option | Default | Description |
|--------|---------|-------------|
| `--name` | (required) | Deployment name |
| `--location` | (required) | Azure region |
| `--resource-group` | `<name>-group` | Resource group |
| `--cpu` | `1.0` | CPU cores |
| `--memory` | `2Gi` | Memory |
| `--min-replicas` | `1` | Minimum replicas |
| `--max-replicas` | `1` | Maximum replicas |

---

## 🔧 What Gets Created

### VM Deployment

| Resource | Naming |
|----------|--------|
| Resource Group | `<name>-group` |
| Virtual Network | `<name>-vnet` (10.200.x.x/27) |
| Subnet | `<name>-subnet` (/28) |
| NSG | `<name>-nsg` (SSH + OpenClaw ports) |
| Public IP | `<name>-pip` (static) |
| VM | `<name>-vm` (Ubuntu 24.04 LTS, spot) |

OpenClaw is installed via **cloud-init** and runs as a **systemd service**.

### Container Apps Deployment

| Resource | Naming |
|----------|--------|
| Resource Group | `<name>-group` |
| Container Apps Environment | `<name>-env` |
| Container App | `<name>-app` |
| Log Analytics | `<name>-logs` |

---

## 🌐 Network Configuration

VNet addresses are **auto-incremented** in the `10.200.0.0/16` range:

| Deployment | VNet CIDR |
|------------|-----------|
| 1st | `10.200.0.0/27` |
| 2nd | `10.200.0.32/27` |
| 3rd | `10.200.0.64/27` |
| ... | ... |

To reuse an existing VNet:
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --resource-group existing-rg \
  --vnet-name existing-vnet \
  --subnet-name existing-subnet
```

---

## 🔑 Authentication

### Gateway Token
A random gateway token is auto-generated and shown after deployment:
```
Dashboard: http://<public-ip>:18789/?token=<TOKEN>
```

### Model Auth (GitHub Copilot)
Pass `--auth-token` to configure GitHub Copilot authentication:
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --auth-token "ghu_xxxxxxxxxxxx"
```

---

## 📊 Post-Deployment

### SSH into VM
```bash
ssh <username>@<public-ip>
```

### Check OpenClaw Status
```bash
sudo systemctl status openclaw
```

### View Logs
```bash
sudo journalctl -u openclaw -f
```

### Access Dashboard
```
http://<public-ip>:18789/?token=<TOKEN>
```

---

## 💰 Cost Estimates

### VM (Spot Pricing) — Recommended
| Resource | Monthly |
|----------|---------|
| VM (D2als_v6 spot) | ~$15-25 |
| Disk (128 GB) | ~$10 |
| Public IP | ~$3 |
| **Total** | **~$28-38** |

### Container Apps
| Resource | Monthly |
|----------|---------|
| Container (1 vCPU, 2 GB) | ~$50 |
| Log Analytics | ~$5 |
| **Total** | **~$55** |

---

## 🔒 Security

- ✅ SSH key authentication (no passwords)
- ✅ NSG limits access to ports 22 and 18789
- ✅ Gateway token required for dashboard
- ✅ OpenClaw runs as non-root `openclaw` user
- ✅ Managed identity enabled on VM

---

## 🆘 Troubleshooting

### Cloud-init failed
```bash
sudo cloud-init status
sudo cat /var/log/cloud-init-output.log
```

### OpenClaw not running
```bash
sudo systemctl status openclaw
sudo journalctl -u openclaw -n 100
```

### Check versions
```bash
node --version
openclaw --version
```

---

## 🤖 About This Project

This entire project — including the Python deployment script, cloud-init templates, documentation, and troubleshooting guides — was created by **OpenClaw**, an AI assistant powered by Claude.

The development process involved:
- Natural language conversations to define requirements
- Iterative debugging and refinement
- Real-world testing on Azure infrastructure

**AI-generated. Human-guided. Production-ready.**

---

## 📞 Resources

- **OpenClaw:** https://openclaw.ai
- **OpenClaw Docs:** https://docs.openclaw.ai
- **Azure CLI:** https://learn.microsoft.com/cli/azure
- **Source:** https://github.com/roccoren/openclaw-azure-deploy

---

<p align="center">
  <strong>🦞 Built with OpenClaw + Claude</strong><br>
  <em>AI-powered infrastructure automation</em>
</p>
