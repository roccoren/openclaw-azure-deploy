# Discord + GitHub Copilot Quickstart

Deploy OpenClaw to Azure with Discord and GitHub Copilot authentication.

## Prerequisites

- Azure CLI logged in (`az login`)
- Discord bot token ([create one](https://discord.com/developers/applications))
- GitHub account with Copilot access

## 1. Deploy the VM

```bash
python scripts/deploy-openclaw.py vm \
  --name openclaw-discord \
  --location westus2 \
  --enable-discord \
  --discord-token "YOUR_DISCORD_BOT_TOKEN"
```

## 2. SSH into the VM

```bash
# As your admin user
ssh <admin-user>@<public-ip>

# Switch to openclaw user
sudo su - openclaw
```

## 3. Set up GitHub Copilot Auth

**Option A: Interactive login (recommended)**
```bash
openclaw models auth login-github-copilot
```
This opens a browser flow to authenticate with GitHub.

**Option B: Manual token**

Get your token first:
```bash
# Using GitHub CLI (on your local machine)
gh auth token
```

Then on the VM:
```bash
openclaw config set auth '{"active":"github-copilot:manual","profiles":{"github-copilot:manual":{"provider":"github-copilot","token":"ghu_xxxxxxxxxxxx"}}}'
```

## 4. Restart Gateway

```bash
openclaw gateway restart
```

## 5. Verify

```bash
# Check gateway status
openclaw gateway status

# Watch logs
openclaw logs -f
```

## 6. Test Discord

1. Invite your bot to a Discord server
2. DM the bot — you'll get a pairing code
3. Approve the pairing:
   ```bash
   openclaw pairing list
   openclaw pairing approve discord <code>
   ```
4. Message the bot again — it should respond!

## Troubleshooting

**"systemctl --user unavailable"**
```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
```

**Check Discord connection**
```bash
openclaw doctor
```

**View detailed logs**
```bash
openclaw logs -f --level debug
```
