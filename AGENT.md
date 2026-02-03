# OpenClaw Azure Deployment — Agent Instructions

> **For AI agents:** This file contains everything you need to deploy OpenClaw to Azure. Read this file, then execute the commands.

## Prerequisites

Before deploying, verify:

```bash
# Check Azure CLI is logged in
az account show

# Check Python is available
python3 --version

# Check SSH key exists (for VM deployment)
ls ~/.ssh/*.pub
```

If `az account show` fails, the user must run `az login` first.

## Deployment Script Location

The deployment script is at:
```
scripts/deploy-openclaw.py
```

Relative to this file's directory. If you're in the repo root:
```bash
python scripts/deploy-openclaw.py --help
```

## Deploy to Azure VM (Recommended)

**Basic deployment with spot pricing (~$30/month):**
```bash
python scripts/deploy-openclaw.py vm --name <deployment-name> --location <azure-region>
```

**Example:**
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2
```

**With GitHub Copilot authentication:**
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --auth-token "ghu_xxxxxxxxxxxx"
```

**Common Azure regions:** `westus2`, `eastus`, `westeurope`, `southeastasia`

### VM Options

| Flag | Default | Purpose |
|------|---------|---------|
| `--name` | required | Name for all resources |
| `--location` | required | Azure region |
| `--resource-group` | `<name>-group` | Use existing resource group |
| `--no-spot` | spot enabled | Regular pricing (more expensive) |
| `--vm-size` | `Standard_D2als_v6` | VM size (2 vCPU, 4GB RAM) |
| `--auth-token` | none | GitHub Copilot token |
| `--tailscale` | off | Use Tailscale Funnel for HTTPS |
| `--dry-run` | off | Preview without executing |

### What Gets Created

The script creates:
- Resource Group: `<name>-group`
- Virtual Network: `<name>-vnet`
- Subnet: `<name>-subnet`
- Network Security Group: `<name>-nsg` (allows SSH + port 18789)
- Public IP: `<name>-pip`
- Virtual Machine: `<name>-vm` (Ubuntu 24.04 LTS)

OpenClaw is installed automatically via cloud-init.

## Deploy to Azure Container Apps

```bash
python scripts/deploy-openclaw.py aca --name <deployment-name> --location <azure-region>
```

**Example:**
```bash
python scripts/deploy-openclaw.py aca --name my-openclaw --location westus2
```

### Container Apps Options

| Flag | Default | Purpose |
|------|---------|---------|
| `--name` | required | Name for all resources |
| `--location` | required | Azure region |
| `--cpu` | `1.0` | CPU cores |
| `--memory` | `2Gi` | Memory allocation |

## After Deployment

The script outputs:
- **Public IP** (VM) or **FQDN** (Container Apps)
- **Gateway token** for dashboard access
- **SSH command** (VM only)

### Access the VM

```bash
# SSH into the VM
ssh <username>@<public-ip>

# Check OpenClaw status
sudo -u openclaw openclaw gateway status

# View logs
sudo -u openclaw openclaw gateway logs -f

# Access dashboard (via SSH tunnel)
ssh -L 18789:localhost:18789 <username>@<public-ip>
# Then open: http://localhost:18789/?token=<TOKEN>
```

### Access Container Apps

Open the HTTPS URL shown after deployment.

## Troubleshooting

**Azure CLI not logged in:**
```bash
az login
```

**Cloud-init failed (VM):**
```bash
ssh <user>@<ip>
sudo cloud-init status
sudo cat /var/log/cloud-init-output.log
```

**OpenClaw not running:**
```bash
# Check status
sudo -u openclaw openclaw gateway status

# Start if stopped
sudo -u openclaw openclaw gateway start

# View recent logs
sudo -u openclaw openclaw gateway logs -n 100
```

**Check installed versions:**
```bash
node --version    # Should be 22.x
openclaw --version
```

## Dry Run

To preview what will be created without executing:
```bash
python scripts/deploy-openclaw.py vm --name test --location westus2 --dry-run
```

## Cost Estimates

| Target | Approximate Monthly Cost |
|--------|-------------------------|
| VM (spot pricing) | $28-38 |
| VM (regular pricing) | $60-80 |
| Container Apps | $55 |

---

**Source:** https://github.com/roccoren/openclaw-azure-deploy
