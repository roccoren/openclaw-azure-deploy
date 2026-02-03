# 🦞 OpenClaw Azure 部署

[English](README.md) | 简体中文

> **🤖 完全由 AI 构建** — 本项目由 [OpenClaw](https://openclaw.ai)（一个基于 Claude 的 AI 助手）创建。所有脚本、配置和文档都是通过自然语言对话生成的。

一键部署 OpenClaw 到 Azure 虚拟机或 Azure Container Apps。

---

## 🤖 AI 智能体指南

**如果你是 AI 智能体**（Claude、GPT、Codex、OpenClaw 或任何基于 LLM 的助手），请阅读 [`AGENT.md`](AGENT.md) 获取专为你优化的部署指南。

**快速提示词：**
> 阅读此仓库中的 AGENT.md，使用 VM 选项将 OpenClaw 部署到 westus2 区域。

**OpenClaw 技能包：** 安装 `azure-deploy.skill` 以获得原生技能集成。

---

## 🚀 快速开始

### 部署到 Azure 虚拟机（推荐）

```bash
# 使用 Spot 定价的基础部署
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2

# 使用 GitHub Copilot 认证令牌
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --auth-token "ghu_xxxxxxxxxxxx"

# 试运行（预览命令但不执行）
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 --dry-run
```

### 部署到 Azure Container Apps

```bash
python scripts/deploy-openclaw.py aca --name my-openclaw --location westus2
```

---

## 📋 前置条件

- Python 3.8+
- 已登录的 Azure CLI (`az`)
- `~/.ssh/` 中的 SSH 公钥（自动检测）

```bash
# 登录 Azure
az login

# 验证
az account show
```

---

## 📁 项目结构

```
openclaw-azure-deploy/
├── AGENT.md                    # 🤖 智能体可读的部署指南
├── azure-deploy.skill          # 📦 OpenClaw 技能包
├── azure-deploy/               # 技能源文件
│   ├── SKILL.md
│   └── scripts/
├── scripts/
│   ├── deploy-openclaw.py      # 🎯 主部署脚本（VM + ACA）
│   └── legacy/                 # 旧版 bash 脚本（已弃用）
├── bicep/                      # Azure Bicep 模板（用于 ACA）
│   ├── main.bicep
│   └── parameters.*.json
├── config/                     # 配置模板
│   ├── gateway-config.json
│   └── channels.json
├── docs/
│   ├── azure-openclaw-architecture.md
│   └── legacy/                 # 旧版文档
├── Dockerfile                  # ACA 容器镜像
└── README.md
```

---

## ⚙️ 虚拟机部署选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--name` | （必需） | 部署名称（用于资源组、虚拟机、VNet 等） |
| `--location` | （必需） | Azure 区域（如 `westus2`、`eastus`） |
| `--resource-group` | `<name>-group` | 使用现有资源组 |
| `--no-spot` | 启用 Spot | 使用常规定价而非 Spot |
| `--vm-size` | `Standard_D2als_v6` | 虚拟机规格（2 vCPU，4 GB 内存） |
| `--os-disk-size` | `128` | 操作系统磁盘大小（GB） |
| `--auth-token` | 无 | GitHub Copilot 或其他提供商认证令牌 |
| `--vnet-name` | 自动创建 | 复用现有 VNet |
| `--subnet-name` | 自动创建 | 复用现有子网 |
| `--ssh-key` | 自动检测 | SSH 公钥路径 |
| `--admin-username` | `$USER` | 虚拟机管理员用户名 |
| `--dry-run` | false | 预览命令但不执行 |

---

## ⚙️ Container Apps 选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--name` | （必需） | 部署名称 |
| `--location` | （必需） | Azure 区域 |
| `--resource-group` | `<name>-group` | 资源组 |
| `--cpu` | `1.0` | CPU 核心数 |
| `--memory` | `2Gi` | 内存 |
| `--min-replicas` | `1` | 最小副本数 |
| `--max-replicas` | `1` | 最大副本数 |

---

## 🔧 创建的资源

### 虚拟机部署

| 资源 | 命名规则 |
|------|----------|
| 资源组 | `<name>-group` |
| 虚拟网络 | `<name>-vnet` (10.200.x.x/27) |
| 子网 | `<name>-subnet` (/28) |
| 网络安全组 | `<name>-nsg`（SSH + OpenClaw 端口） |
| 公共 IP | `<name>-pip`（静态） |
| 虚拟机 | `<name>-vm`（Ubuntu 24.04 LTS，Spot） |

OpenClaw 通过 **cloud-init** 安装，并作为 **systemd 服务** 运行。

### Container Apps 部署

| 资源 | 命名规则 |
|------|----------|
| 资源组 | `<name>-group` |
| Container Apps 环境 | `<name>-env` |
| Container App | `<name>-app` |
| Log Analytics | `<name>-logs` |

---

## 🌐 网络配置

VNet 地址在 `10.200.0.0/16` 范围内**自动递增**：

| 部署序号 | VNet CIDR |
|----------|-----------|
| 第 1 个 | `10.200.0.0/27` |
| 第 2 个 | `10.200.0.32/27` |
| 第 3 个 | `10.200.0.64/27` |
| ... | ... |

复用现有 VNet：
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --resource-group existing-rg \
  --vnet-name existing-vnet \
  --subnet-name existing-subnet
```

---

## 🔑 认证

### Gateway 令牌
部署后会自动生成随机 Gateway 令牌：
```
Dashboard: http://<public-ip>:18789/?token=<TOKEN>
```

### 模型认证（GitHub Copilot）
使用 `--auth-token` 配置 GitHub Copilot 认证：
```bash
python scripts/deploy-openclaw.py vm --name my-openclaw --location westus2 \
  --auth-token "ghu_xxxxxxxxxxxx"
```

---

## 📊 部署后操作

### SSH 连接虚拟机
```bash
ssh <username>@<public-ip>
```

### 检查 OpenClaw 状态
```bash
sudo -u openclaw openclaw gateway status
```

### 查看日志
```bash
sudo -u openclaw openclaw gateway logs -f
```

### 访问控制台
```
http://<public-ip>:18789/?token=<TOKEN>
```

---

## 💰 成本估算

### 虚拟机（Spot 定价）— 推荐
| 资源 | 月费用 |
|------|--------|
| 虚拟机（D2als_v6 Spot） | ~$15-25 |
| 磁盘（128 GB） | ~$10 |
| 公共 IP | ~$3 |
| **总计** | **~$28-38** |

### Container Apps
| 资源 | 月费用 |
|------|--------|
| 容器（1 vCPU，2 GB） | ~$50 |
| Log Analytics | ~$5 |
| **总计** | **~$55** |

---

## 🔒 安全性

- ✅ SSH 密钥认证（无密码）
- ✅ NSG 限制仅允许 22 和 18789 端口
- ✅ 访问控制台需要 Gateway 令牌
- ✅ OpenClaw 以非 root 用户 `openclaw` 运行
- ✅ 虚拟机启用托管标识

---

## 🆘 故障排除

### Cloud-init 失败
```bash
sudo cloud-init status
sudo cat /var/log/cloud-init-output.log
```

### OpenClaw 未运行
```bash
# 检查状态
sudo -u openclaw openclaw gateway status

# 如果未运行则启动
sudo -u openclaw openclaw gateway start

# 查看最近的日志
sudo -u openclaw openclaw gateway logs -n 100
```

### 检查版本
```bash
node --version
openclaw --version
```

---

## 🤖 关于本项目

本项目的所有内容 — 包括 Python 部署脚本、cloud-init 模板、文档和故障排除指南 — 均由基于 Claude 的 AI 助手 **OpenClaw** 创建。

开发过程包括：
- 通过自然语言对话定义需求
- 迭代调试和优化
- 在 Azure 基础设施上进行实际测试

**AI 生成。人类指导。生产就绪。**

---

## 📞 资源链接

- **OpenClaw:** https://openclaw.ai
- **OpenClaw 文档:** https://docs.openclaw.ai
- **Azure CLI:** https://learn.microsoft.com/cli/azure
- **源码:** https://github.com/roccoren/openclaw-azure-deploy

---

<p align="center">
  <strong>🦞 由 OpenClaw + Claude 构建</strong><br>
  <em>AI 驱动的基础设施自动化</em>
</p>
