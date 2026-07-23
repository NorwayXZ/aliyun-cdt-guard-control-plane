# Aliyun CDT Guard Control Plane - Project Handoff

Last updated: 2026-07-23
Current version: 0.2.9
Repository: https://github.com/NorwayXZ/aliyun-cdt-guard-control-plane

## Project Goal

Aliyun CDT Guard Control Plane is a lightweight self-hosted dashboard for monitoring Alibaba Cloud CDT traffic usage across multiple ECS servers and accounts. It is meant to help a user avoid exceeding free/shared CDT quota by:

- adding multiple Alibaba Cloud ECS servers,
- grouping servers by Alibaba Cloud account/access key,
- checking CDT traffic and account balance,
- stopping servers when a shared quota threshold is reached,
- showing reset/recovery timing,
- sending Telegram/email/webhook notifications,
- supporting domain reverse proxy guidance,
- providing one-command install/update/uninstall.

The project exists because the older `aliyun-cdt-guard` UI became too cramped and hard to understand. This repository is the redesigned control-plane version.

## Current Deployment

Default install directory:

```bash
/opt/aliyun-cdt-guard-control-plane
```

Default web port:

```bash
8788
```

Systemd units:

```bash
cdt-guard-control-plane-web.service
cdt-guard-control-plane.service
cdt-guard-control-plane.timer
```

Useful commands:

```bash
systemctl status cdt-guard-control-plane-web.service --no-pager -l
systemctl status cdt-guard-control-plane.timer --no-pager -l
journalctl -u cdt-guard-control-plane.service -n 120 --no-pager
journalctl -u cdt-guard-control-plane-web.service -n 120 --no-pager
```

Install/update:

```bash
curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/install.sh | sudo bash
curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/update.sh | sudo bash
```

If port `8788` is occupied, the installer can select a nearby free port.

## Architecture

Main files:

- `web.py`: self-contained Python web dashboard, forms, UI, reverse proxy page, auth, APIs.
- `guard.py`: Alibaba Cloud checks, traffic accounting, ECS power actions, history/status writing.
- `notifications.py`: Telegram/email/webhook notifications and Telegram command replies.
- `install.sh`: one-command installer.
- `update.sh`: in-place updater that preserves data/config.
- `uninstall.sh`: removes services but keeps data directory by default.
- `README.md`: public install and feature documentation.

Runtime data is stored under `/opt/aliyun-cdt-guard-control-plane`, including config, status, history, notifications, and auth data. Do not assume local repo data exists on the server.

## Alibaba Cloud Model

Important product decision:

- For CDT free traffic, the user wants account-level protection.
- If one Alibaba Cloud account has multiple ECS servers, they share one CDT quota pool for non-mainland outbound traffic.
- If an account threshold is 180 GB and two servers under that account together reach 180 GB, all servers under that account should be stopped.
- Server-level traffic still matters because the user needs to know which machine consumed traffic.

Display rule:

- Account level: show account CDT used/threshold/reset and balance.
- Server level: show custom server name, runtime state, region/IP, server's own traffic, today's usage, and trend entry.
- Avoid repeating account-level pool total in every server row unless needed for context.

Alibaba Cloud permissions used or discussed:

- ECS read/action permissions for server status, start, stop.
- CloudMonitor permissions for real-time EIP/ECS metrics if enabled.
- BSS read-only permissions for bill/account balance/reset information.
- CDT/BSS billing data is preferred over guessed reset dates.

Never hard-code user AccessKeys. They must be entered through the panel and stored in runtime config only.

## UI Direction

The user strongly prefers:

- light mode only, no dark mode,
- a clean control-plane layout inspired by the Claude/arena prototypes,
- all fonts using `Geist Sans + Noto Sans SC`,
- concise top navigation without extra descriptive subtitles,
- sidebar background that feels integrated with the main light theme,
- server names in a more artistic display style where currently used,
- compact account/server rows with clear hierarchy,
- fewer explanatory blocks and fewer decorative elements,
- no useless "details" buttons that do nothing,
- status should be visually obvious, especially running vs stopped.

The user dislikes:

- cramped typography,
- repeated explanatory text,
- large unnecessary cards,
- old-style thick borders and vertical lines,
- dark-mode visual noise,
- random decorative animations that do not help understanding,
- vague percentages shown in the wrong place,
- hidden/obscured remarks that the user saved for themselves.

When changing UI, test for text overlap on desktop and mobile. Many previous complaints were about overlapping labels, cramped nav text, inconsistent card heights, and poor alignment.

## Telegram Behavior

Telegram is important and must be reliable.

Current commands:

```text
/status
/traffic
/pools
/server keyword
/report
/help
```

Message style rules:

- Keep replies short and easy to scan.
- Use server custom names exactly as shown in the panel.
- Use status markers like `🟢 运行中`, `🔴 已关机`, `🟡 预警`.
- Group `/traffic` by Alibaba Cloud account.
- Under each account, show account CDT usage and reset once.
- Under each server, show server's own traffic and current increment.
- Do not include long text such as "非中国内地区域 CDT 共享池 / 按 AccessKey 所属阿里云账号自动归组".

Important bug fixed in 0.2.9:

- One Telegram command must not generate repeated replies.
- `notifications.py` now uses:
  - `notification_state.lock` for local process locking,
  - `telegram_update_offset`,
  - `telegram_processed_update_ids`.
- Do not remove this de-duplication.

Operational warning:

- If the same Telegram Bot Token is configured on multiple panel installations, each panel can still respond. The safest product rule is one Bot per main panel, or all old panels must be updated/disabled.
- If a bot starts spamming, first stop the timer on the offending server:

```bash
sudo systemctl stop cdt-guard-control-plane.timer cdt-guard-control-plane.service
```

Then update:

```bash
curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/update.sh | sudo bash
```

## Telegram Setup UX

User requirements:

- Chat ID must not be auto-filled with `admin` or any unrelated value.
- Bot Token must be saved before fetching candidate Chat IDs.
- Candidate Chat IDs should be displayed as selectable hints, not silently inserted.
- The setup guide must be sequential:
  1. create bot in BotFather,
  2. paste Bot Token,
  3. send a message to the bot,
  4. fetch/select Chat ID,
  5. save settings,
  6. send a test message.
- Saved channels should be shown as separate blocks at the top.
- Command help should be its own block, near test notification, not mixed into setup steps.

## Add Server UX

User requirements:

- Page title should be "新增服务器".
- Required fields must have red asterisks.
- Region ID must not be prefilled.
- Reusing a saved Alibaba Cloud account should be optional.
- If a saved account is selected, both AccessKey ID and AccessKey Secret should be visible in the form rather than hidden behind dots.
- AccessKey helper links should be near the AccessKey fields:
  - China: `https://ram.console.aliyun.com/users`
  - International: `https://ram.console.alibabacloud.com/users`
- Do not make users manually fill irrelevant pool IDs. Shared pooling should be explained and inferred from same AccessKey/account.

## Account Security UX

User wanted:

- allow username changes,
- allow password changes without requiring old password after the user is already logged in,
- show existing password as dots,
- keep the page simple.

Security caveat for future agents:

- The user prefers convenience, but do not expose password hashes or secrets in UI.
- If adding more security, explain clearly and keep it optional.

## Reverse Proxy UX

User wants a panel page for domain reverse proxy setup:

- Source/origin IP should be auto-detected/displayed after login, not manually typed.
- Include Cloudflare/Caddy/Nginx guidance.
- The page should help users use a domain instead of `IP:port`.

Existing guide:

- `docs/reverse-proxy.md`

## Installer Requirements

Supported/recommended systems:

- Ubuntu 22.04 is the primary recommendation.
- Debian 12 is also recommended.
- Other Debian/Ubuntu-like systems may work.

Installer constraints:

- Keep it lightweight.
- Do not install unnecessary large packages.
- Avoid heavy frameworks and databases.
- Preserve data/config on update.
- Uninstall removes services but keeps `/opt/aliyun-cdt-guard-control-plane` unless user manually deletes it.

Known Linux package issues addressed:

- apt/dpkg locks can block install.
- broken `/var/lib/dpkg/updates/0000` can cause `dpkg --configure -a` parse errors.
- Oracle/Ubuntu kernel post-install failures can make apt unusable; installer should explain rather than blindly remove system files.
- `SKIP_SYSTEM_PACKAGES=1` is supported only if required commands and Python venv support already exist.

## Current Known Risks

1. Multiple installed panels can still share the same Telegram Bot Token.
   - 0.2.9 prevents repeated replies within one panel.
   - It cannot stop another old panel from replying.
   - Future improvement: add a panel instance ID in Telegram setup and warn if the same bot is detected replying from another panel, if feasible.

2. Account names are currently shown as fingerprints in Telegram, such as `阿里云账号 6780e69731`.
   - Future improvement: allow user-defined account aliases.

3. BSS/CDT reset time should come from real billing data when available.
   - Do not present guessed reset dates as authoritative.

4. UI has gone through many iterations.
   - Be careful with CSS churn.
   - Screenshot-test key pages after UI changes.

## Useful Verification

Before committing:

```bash
bash -n install.sh
bash -n update.sh
bash -n uninstall.sh
python3 -m py_compile web.py guard.py notifications.py
```

After deploying:

```bash
curl -fsS http://127.0.0.1:8788/healthz
systemctl is-active cdt-guard-control-plane-web.service
systemctl is-active cdt-guard-control-plane.timer
cat /opt/aliyun-cdt-guard-control-plane/VERSION
```

## Suggested Next Roadmap

High priority:

- Add user-defined Alibaba Cloud account aliases.
- Add a clear warning if Telegram Bot Token appears to be configured on multiple panels.
- Add a safer "disable Telegram command replies on this panel" toggle.
- Improve `/traffic` for 10+ accounts with pagination or top-risk first summaries.
- Continue UI cleanup page by page with screenshots.

Medium priority:

- Add better account balance display and billing detail grouping.
- Improve per-server monthly cost visibility if Alibaba Cloud billing APIs can map costs to instance IDs.
- Add VPC Flow Log + SLS documentation for traffic destination analysis.
- Add a setup wizard for first install.

Lower priority:

- Add email provider presets.
- Add iPhone-friendly push notification channel if a lightweight provider is chosen.
- Add backup/export/import for config.

## Sensitive Data Policy

Never place the following in git, docs, logs, final answers, screenshots, or test fixtures:

- root passwords,
- Aliyun AccessKey ID,
- Aliyun AccessKey Secret,
- Telegram Bot Token,
- Telegram Chat ID if the user considers it private,
- server private keys,
- live session cookies.

Use placeholders such as:

```text
<ALIYUN_ACCESS_KEY_ID>
<ALIYUN_ACCESS_KEY_SECRET>
<TELEGRAM_BOT_TOKEN>
<TELEGRAM_CHAT_ID>
```

