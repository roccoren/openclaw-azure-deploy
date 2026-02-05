# 🦞 OpenClaw Azure Deployment

English | [简体中文](README.zh-CN.md)

> **🤖 Built entirely by AI** — This project was created by [OpenClaw](https://openclaw.ai), an AI-powered assistant running Claude and OpenAI Codex (GPT-5.2-codex). Every script, configuration, and documentation file was generated through natural language conversations.

Deploy OpenClaw to Azure VMs (production-ready) or Azure Container Apps (development only) with a single command.

---

## 🤖 For AI Agents

**If you're an AI agent** (Claude, GPT, Codex, OpenClaw, or any LLM-based assistant), read [`AGENT.md`](AGENT.md) for deployment instructions optimized for you.

**Quick agent prompt:**
> Read AGENT.md in this repository and deploy OpenClaw to Azure using the VM option in westus2.

**OpenClaw skill:** Install `azure-deploy.skill` for native skill integration.

---

## 📚 Quickstart Guides

- **[Discord + GitHub Copilot](docs/discord-quickstart.md)** — Deploy with Discord and GitHub Copilot auth

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

### Deploy to Azure Container Apps (Development)

> ⚠️ **Warning:** Container Apps deployment is currently in development and may not work properly. VM deployment is recommended for production use.

```bash
python scripts/deploy-openclaw.py aca --name my-openclaw --location westus2
```

**Note:** The ACA option is for testing only. For production deployments, use the VM option.

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

### Channel Configuration

| Option | Description |
|--------|-------------|
| `--enable-telegram` | Enable Telegram channel |
| `--telegram-token` | Telegram bot token (from @BotFather) |
| `--enable-discord` | Enable Discord channel |
| `--discord-token` | Discord bot token |
| `--enable-slack` | Enable Slack channel |
| `--slack-app-token` | Slack app token (xapp-...) |
| `--slack-bot-token` | Slack bot token (xoxb-...) |
| `--enable-msteams` | Enable Microsoft Teams channel |
| `--msteams-app-id` | MS Teams App ID |
| `--msteams-app-password` | MS Teams App Password |
| `--msteams-tenant-id` | MS Teams Tenant ID |

**Example: Deploy with Telegram**
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --enable-telegram --telegram-token "123:abc..."
```

**Example: Deploy with multiple channels**
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --enable-discord --discord-token "TOKEN" \
  --enable-slack --slack-app-token "xapp-..." --slack-bot-token "xoxb-..."
```

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
│   ├── discord-quickstart.md   # Quickstart guide for Discord + GitHub Copilot
│   └── legacy/                 # Old documentation
├── Dockerfile                  # Container image for ACA
└── README.md
```

---

## 🚨 Development Status

- ✅ **Azure VM**: Production-ready
- ⚠️ **Azure Container Apps**: In development (not recommended for production)

---

## 🤝 Contributing

This project was AI-generated. Contributions welcome! The Python deployment script is well-documented and extensible.

---

## 📄 License

MIT