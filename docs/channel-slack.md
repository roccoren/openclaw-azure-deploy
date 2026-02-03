# Slack Channel Setup (OpenClaw)

This guide covers **Slack Socket Mode** (recommended). It includes the Slack-side setup and the minimal OpenClaw CLI config.

---

## 1) Create the Slack App

1. Go to https://api.slack.com/apps → **Create New App** → **From Scratch**.
2. Choose an app name + workspace.

---

## 2) Enable Socket Mode + App Token

1. **Socket Mode** → Enable.
2. **Basic Information** → **App-Level Tokens** → **Generate Token**
   - Scope: `connections:write`
   - Copy the **App Token** (`xapp-...`).

---

## 3) OAuth Scopes + Install

1. **OAuth & Permissions** → add bot scopes (minimal recommended):

   - `chat:write`
   - `channels:history`, `channels:read`
   - `groups:history`, `groups:read`
   - `im:history`, `im:read`, `im:write`
   - `mpim:history`, `mpim:read`
   - `users:read`
   - `app_mentions:read`
   - `reactions:read`, `reactions:write`
   - `pins:read`, `pins:write`
   - `emoji:read`
   - `files:write`
   - `commands`

2. Click **Install to Workspace**.
3. Copy **Bot User OAuth Token** (`xoxb-...`).

---

## 4) Event Subscriptions

1. **Event Subscriptions** → Enable.
2. Subscribe to:
   - `message.*`
   - `app_mention`
   - `reaction_added`, `reaction_removed`

---

## 5) App Home

Enable the **Messages Tab** so users can DM the bot.

---

## 6) OpenClaw Config (CLI)

```bash
openclaw config set channels.slack.enabled true --json
openclaw config set channels.slack.appToken "xapp-..."
openclaw config set channels.slack.botToken "xoxb-..."
openclaw gateway restart
```

---

## Notes

- Invite the bot into channels you want it to read.
- If you want HTTP mode instead of Socket Mode, see OpenClaw Slack docs.
