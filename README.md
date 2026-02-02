# OpenClaw Azure Deployment

Deploy OpenClaw to Azure VMs or Azure Container Apps with a single command.

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

## 🔧 What Gets Created

### VM Deployment

- **Resource Group:** `<name>-group`
- **Virtual Network:** `<name>-vnet` (10.200.x.x/27, auto-incremented)
- **Subnet:** `<name>-subnet` (/28)
- **Network Security Group:** SSH (22) + OpenClaw (18789)
- **Public IP:** Static
- **VM:** Ubuntu 24.04 LTS with spot pricing
- **OpenClaw:** Installed via cloud-init, runs as systemd service

### Container Apps Deployment

- **Resource Group:** `<name>-group`
- **Container Apps Environment**
- **Container App:** OpenClaw with HTTPS ingress
- **Log Analytics Workspace**

## 🌐 Network Configuration

VNet addresses are auto-incremented in the `10.200.0.0/16` range:
- First deployment: `10.200.0.0/27`
- Second deployment: `10.200.0.32/27`
- And so on...

To reuse an existing VNet:
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --resource-group existing-rg \
  --vnet-name existing-vnet \
  --subnet-name existing-subnet
```

## 🔑 Authentication

### Gateway Token
A random gateway token is auto-generated and shown after deployment:
```
Dashboard: http://<public-ip>:18789/?token=<TOKEN>
```

### Model Auth (GitHub Copilot)
Pass `--auth-token` to configure GitHub Copilot authentication during deployment:
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --auth-token "ghu_xxxxxxxxxxxx"
```

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
Open the URL shown after deployment:
```
http://<public-ip>:18789/?token=<TOKEN>
```

## 💰 Cost Estimates

### VM (Spot Pricing)
| Resource | Monthly Cost |
|----------|-------------|
| VM (D2als_v6 spot) | ~$15-25 |
| Disk (128 GB) | ~$10 |
| Public IP | ~$3 |
| **Total** | **~$28-38** |

### Container Apps
| Resource | Monthly Cost |
|----------|-------------|
| Container (1 vCPU, 2 GB) | ~$50 |
| Log Analytics | ~$5 |
| **Total** | **~$55** |

## 🔒 Security

- SSH key authentication (no passwords)
- Network Security Group limits access to ports 22 and 18789
- Gateway token required for dashboard access
- OpenClaw runs as non-root `openclaw` user
- Managed identity enabled on VM

## 📁 Repository Structure

```
openclaw-azure-deploy/
├── scripts/
│   └── deploy-openclaw.py    # Main deployment script
├── bicep/                     # (Legacy) Bicep templates
├── config/                    # Configuration templates
└── README.md
```

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

### Check if Node.js installed
```bash
node --version
openclaw --version
```

## 📞 Resources

- **OpenClaw Docs:** https://docs.openclaw.ai
- **Azure CLI:** https://learn.microsoft.com/cli/azure
- **Container Apps:** https://learn.microsoft.com/azure/container-apps

---

**Status:** ✅ Ready to Deploy
