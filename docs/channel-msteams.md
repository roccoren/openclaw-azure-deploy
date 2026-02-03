# Microsoft Teams Channel Setup (OpenClaw)

This guide covers Azure Bot creation, Teams app packaging, and minimal OpenClaw config.

---

## 1) Install the Teams Plugin

```bash
openclaw plugins install @openclaw/msteams
```

---

## 2) Create the Azure Bot

1. Azure Portal → **Create a resource** → **Azure Bot**.
2. Choose **Single Tenant**.
3. After creation, open the bot resource and copy:
   - **Microsoft App ID** → `appId`
   - **Tenant ID** → `tenantId`
4. App Registration → **Certificates & secrets** → **New client secret** → copy the **Value** → `appPassword`.

---

## 3) Enable Teams Channel

Azure Bot → **Channels** → **Microsoft Teams** → **Configure** → **Save**.

---

## 4) Build a Teams App Package

Use Teams Developer Portal (recommended):

1. https://dev.teams.microsoft.com/apps → **New app**
2. Add **Bot** → paste App ID
3. Scopes: **personal**, **team**, **groupChat**
4. Download app package (ZIP)

---

## 5) Expose the Webhook Endpoint

Teams needs a public URL for the bot webhook. Examples:

- **ngrok**: `ngrok http 3978`
- **Tailscale Funnel**: `tailscale funnel 3978`

Set Azure Bot **Messaging endpoint** to:
```
https://<public-url>/api/messages
```

---

## 6) Upload the Teams App

Teams → **Apps** → **Manage your apps** → **Upload a custom app** → select the ZIP.

---

## 7) OpenClaw Config (CLI)

```bash
openclaw config set channels.msteams.enabled true --json
openclaw config set channels.msteams.appId "<APP_ID>"
openclaw config set channels.msteams.appPassword "<APP_PASSWORD>"
openclaw config set channels.msteams.tenantId "<TENANT_ID>"
openclaw config set channels.msteams.webhook.port 3978 --json
openclaw config set channels.msteams.webhook.path "/api/messages"
openclaw gateway restart
```

---

## Notes

- By default, group chats are **blocked** unless allowlisted.
- For channels, mentions are required unless configured otherwise.
- If you need channel file/attachment access, enable Graph permissions.
