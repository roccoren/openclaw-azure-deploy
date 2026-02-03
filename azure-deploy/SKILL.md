---
name: azure-deploy
description: "Deploy OpenClaw to Azure VMs or Azure Container Apps. Use when deploying OpenClaw to Azure, creating Azure infrastructure for OpenClaw, setting up spot VMs with OpenClaw, or automating cloud deployment of OpenClaw gateway."
---

# Azure Deploy

Deploy OpenClaw to Azure with a single command. Supports Azure VMs (spot pricing, ~$30/mo) or Azure Container Apps.

## Prerequisites

- Azure CLI logged in (`az login`)
- Python 3.8+
- SSH public key in `~/.ssh/` (auto-detected for VM deployments)

Verify Azure login:
```bash
az account show
```

## Quick Start

### Deploy to Azure VM (Recommended)

```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2
```

With GitHub Copilot auth:
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --auth-token "ghu_xxxxxxxxxxxx"
```

### Deploy to Azure Container Apps

```bash
python scripts/deploy-openclaw.py aca --name my-openclaw --location westus2
```

## VM Options

| Option | Default | Description |
|--------|---------|-------------|
| `--name` | required | Deployment name |
| `--location` | required | Azure region (westus2, eastus, etc.) |
| `--resource-group` | `<name>-group` | Existing RG to use |
| `--no-spot` | spot on | Regular pricing instead of spot |
| `--vm-size` | `Standard_D2als_v6` | VM size (2 vCPU, 4GB) |
| `--auth-token` | none | GitHub Copilot token for model auth |
| `--tailscale` | off | Use Tailscale Funnel for HTTPS |
| `--vnet-name` | auto | Existing VNet to reuse |
| `--subnet-name` | auto | Existing subnet (requires --vnet-name) |
| `--dry-run` | off | Preview commands only |

## Container Apps Options

| Option | Default | Description |
|--------|---------|-------------|
| `--name` | required | Deployment name |
| `--location` | required | Azure region |
| `--cpu` | `1.0` | CPU cores |
| `--memory` | `2Gi` | Memory |

## What Gets Created

**VM Deployment:**
- Resource Group: `<name>-group`
- VNet: `<name>-vnet` (10.200.x.x/27, auto-incremented)
- Subnet: `<name>-subnet` (/28)
- NSG: `<name>-nsg` (SSH + port 18789)
- Public IP: `<name>-pip` (static)
- VM: `<name>-vm` (Ubuntu 24.04, spot by default)

OpenClaw installs via cloud-init and runs as systemd service.

**Container Apps Deployment:**
- Resource Group: `<name>-group`
- Container Apps Environment: `<name>-env`
- Container App: `<name>-app`

## Post-Deployment

### VM Access
```bash
# SSH in
ssh <username>@<public-ip>

# Check status
sudo systemctl status openclaw

# View logs
sudo journalctl -u openclaw -f

# Dashboard (via SSH tunnel)
ssh -L 18789:localhost:18789 <user>@<ip>
# Then open http://localhost:18789/?token=<TOKEN>
```

### Container Apps Access
Dashboard available at HTTPS URL shown after deployment.

## Cost Estimates

| Target | Monthly |
|--------|---------|
| VM (spot) | ~$28-38 |
| Container Apps | ~$55 |

## Troubleshooting

**Cloud-init failed:**
```bash
sudo cloud-init status
sudo cat /var/log/cloud-init-output.log
```

**OpenClaw not running:**
```bash
sudo systemctl status openclaw
sudo journalctl -u openclaw -n 100
```

**Check versions:**
```bash
node --version
openclaw --version
```
