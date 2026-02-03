# Discord Channel Setup (OpenClaw)

This guide covers creating a Discord bot, inviting it to a server, and minimal OpenClaw config.

---

## 1) Create the Discord App + Bot

1. Go to https://discord.com/developers/applications → **New Application**.
2. In your app → **Bot** → **Add Bot**.
3. Copy the **Bot Token**.

---

## 2) Enable Gateway Intents

In **Bot → Privileged Gateway Intents**, enable:

- **Message Content Intent** (required to read message text in guilds)
- **Server Members Intent** (needed for allowlists / member lookups)

---

## 3) Generate Invite URL

1. **OAuth2 → URL Generator**
2. Scopes:
   - `bot`
   - `applications.commands`
3. Bot Permissions (minimal recommended):
   - View Channels
   - Send Messages
   - Read Message History
   - Embed Links
   - Attach Files (optional)
   - Add Reactions (optional)

4. Open the generated URL and invite the bot to your server.

---

## 4) OpenClaw Config (CLI)

```bash
openclaw config set channels.discord.enabled true --json
openclaw config set channels.discord.token "YOUR_DISCORD_BOT_TOKEN"
openclaw gateway restart
```

---

## Notes

- DMs are **pairing-enabled** by default; approve pairing codes with:
  ```bash
  openclaw pairing approve discord <code>
  ```
- If the bot doesn’t respond in a server channel, check:
  - The bot has the right permissions in that channel
  - **Message Content Intent** is enabled
  - You’re mentioning the bot if mentions are required
