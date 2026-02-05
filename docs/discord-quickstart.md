# Discord + GitHub Copilot Quickstart

Deploy OpenClaw to Azure with Discord and GitHub Copilot authentication.

## Prerequisites

- Azure CLI logged in (`az login`)
- GitHub account with Copilot access

## 1. Create a Discord Bot

### 1.1 Create Discord Application

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **"New Application"**
3. Enter a name (e.g., "OpenClaw Bot") and click **Create**

### 1.2 Configure Bot Settings

1. In the left sidebar, click **"Bot"**
2. Click **"Reset Token"** and copy the token — save it securely!
3. Under **Privileged Gateway Intents**, enable:
   - ✅ **Message Content Intent** (required to read messages)
   - ✅ **Server Members Intent** (optional, for member lookups)

### 1.3 Generate Invite URL

1. In the left sidebar, click **"OAuth2"** → **"URL Generator"**
2. Under **Scopes**, select:
   - ✅ `bot`
   - ✅ `applications.commands` (for slash commands)
3. Under **Bot Permissions**, select:
   - ✅ Send Messages
   - ✅ Read Message History
   - ✅ Add Reactions
   - ✅ Use Slash Commands
   - ✅ Attach Files
   - ✅ Embed Links
4. Copy the generated URL at the bottom
5. Open the URL in your browser and add the bot to your server

## 2. Deploy the VM

```bash
python scripts/deploy-openclaw.py vm \
  --name openclaw-discord \
  --location westus2 \
  --enable-discord \
  --discord-token "YOUR_DISCORD_BOT_TOKEN"
```

## 3. SSH into the VM

```bash
# As your admin user
ssh <admin-user>@<public-ip>

# Switch to openclaw user
sudo su - openclaw
```

## 4. Run Setup Script

```bash
./setup-gateway.sh
```

## 5. Set up GitHub Copilot Auth

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

## 6. Restart Gateway

```bash
openclaw gateway restart
```

## 7. Verify

```bash
# Check gateway status
openclaw gateway status

# Watch logs
openclaw logs -f
```

## 8. Test Discord

1. DM the bot — you'll get a pairing code
2. Approve the pairing:
   ```bash
   openclaw pairing list
   openclaw pairing approve discord <code>
   ```
3. Message the bot again — it should respond!

## Troubleshooting

**"systemctl --user unavailable"**
```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
```

**Bot not responding in server channels?**

By default, the bot only responds when mentioned in servers. To auto-respond:
```bash
# Get your guild (server) ID - right-click server → Copy Server ID
openclaw config set channels.discord.guilds.YOUR_GUILD_ID.requireMention false
openclaw gateway restart
```

**Check Discord connection**
```bash
openclaw doctor
```

**View detailed logs**
```bash
openclaw logs -f --level debug
```
