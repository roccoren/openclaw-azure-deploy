# Telegram Channel Setup (OpenClaw)

This guide covers creating a Telegram bot via BotFather and minimal OpenClaw config.

---

## 1) Create the Bot

1. Open Telegram and message **@BotFather**.
2. Run `/newbot` and follow the prompts.
3. Copy the **bot token** it gives you.

---

## 2) Optional: Allow Group Messages

If you want the bot to see messages in groups, you may want to disable privacy:

1. In BotFather, run `/setprivacy`.
2. Choose your bot.
3. Set to **Disable**.

---

## 3) OpenClaw Config (CLI)

```bash
openclaw config set channels.telegram.enabled true --json
openclaw config set channels.telegram.token "YOUR_TELEGRAM_BOT_TOKEN"
openclaw gateway restart
```

---

## Notes

- Telegram DMs are enabled by default.
- For groups, you still need to **add the bot** to the group.
