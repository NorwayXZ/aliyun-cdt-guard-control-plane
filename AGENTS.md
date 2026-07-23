# AI Agent Handoff

This repository is the new control-plane version of Aliyun CDT Guard.

Before making changes, read:

- `docs/PROJECT_HANDOFF.md` for product context, current behavior, user preferences, known issues, and roadmap.
- `README.md` for install, update, uninstall, supported systems, and operator commands.

Important rules for future agents:

- Do not commit secrets, passwords, AccessKey ID/Secret, Telegram Bot Token, Chat ID, or live server credentials.
- Preserve user-facing server names exactly as saved in the panel. Do not replace names with ECS instance IDs, IPs, or generic labels unless no custom name exists.
- Telegram command replies must be short and scannable. Avoid long flow-pool explanations and duplicate account-level data on every server line.
- One Telegram command should produce one reply. Keep `notification_state.json` offset/update-id de-duplication and the notification lock intact.
- Treat one Alibaba Cloud account as one shared CDT protection pool for non-mainland CDT usage. If multiple servers use the same AccessKey account, account-level quota protects all of them together.
- Keep the installer lightweight. Avoid adding large dependencies, build systems, databases, or background services unless there is a clear reason.
- Test before finishing: `bash -n install.sh update.sh uninstall.sh` and `python3 -m py_compile web.py guard.py notifications.py`.

