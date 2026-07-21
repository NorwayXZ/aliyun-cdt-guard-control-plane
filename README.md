# Aliyun CDT Guard Control Plane

Aliyun CDT Guard Control Plane 是新版阿里云 CDT 流量保护控制台项目，用来管理多台 ECS、统计 CDT 流量、到阈值自动关机、账期重置后自动恢复、发送 Telegram/邮件/Webhook 通知，并提供账号安全和域名反代配置。

仓库同时保留新版静态 UI 原型文件，方便继续打磨视觉；正式一键安装使用 Python 后端面板，具备真实阿里云 API 调用能力。

## 一键安装

推荐系统：

- Ubuntu 22.04 LTS
- Debian 12

安装命令：

```bash
curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/install.sh | sudo bash
```

默认安装目录：

```text
/opt/aliyun-cdt-guard-control-plane
```

默认端口：

```text
8788
```

安装完成后终端会输出面板地址、用户名和随机生成的密码。

如果系统提示：

```text
E: dpkg was interrupted, you must manually run 'sudo dpkg --configure -a'
```

可以先执行：

```bash
sudo dpkg --configure -a
```

然后重新运行安装命令。新版安装脚本也会尝试自动修复这个状态。

## 一键卸载

```bash
curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/uninstall.sh | sudo bash
```

卸载脚本只移除 systemd 服务和命令入口，默认保留配置、密钥、状态和历史记录目录：

```text
/opt/aliyun-cdt-guard-control-plane
```

确认不再需要后可以手动删除。

## 命令行

```bash
cdt-guard-control-plane status
cdt-guard-control-plane run
systemctl status cdt-guard-control-plane.timer
systemctl status cdt-guard-control-plane-web.service
```

## 功能范围

- 从网页新增/编辑 ECS，不需要 SSH 到服务器手动改配置。
- 支持 AccessKey ID/Secret、ECS Instance ID、区域、阈值、备注等配置。
- 支持一个阿里云账号多台服务器共享 CDT 流量池的归组统计。
- 支持 CDT 流量查询、ECS 状态查询、自动关机、恢复开机。
- 支持 BSS 账单 API 查询真实账期重置时间和账户余额。
- 支持 Telegram、邮件、Webhook 通知。
- 支持 Telegram 主动查询命令。
- 支持面板账号密码修改。
- 支持 Caddy 域名反代配置。

## 页面范围

- 总览：账号流量池、剩余流量、真实账期重置时间、账户余额、流量曲线、重要事件。
- 服务器：按阿里云账号分组展示 ECS，明确运行中、已关机、预警和保护状态。
- 新增服务器：只展示必须填写项，高级备注信息折叠。
- 服务器日志：异常、预警、自动开机、自动关机优先展示。
- 通知设置：已配置渠道放在顶部，支持 Telegram、邮件、Webhook 的设计占位。
- 域名反代：展示 Cloudflare DNS、Caddy、Nginx 的配置思路。
- 账号安全：面板账号密码修改和会话安全设计。
- 登录页：独立 `login.html`，桌面端为品牌说明 + 登录表单，移动端自动收敛为单栏登录。

## 本地预览

静态 UI 原型可以直接打开 `index.html` 预览：

```bash
open index.html
```

登录页单独预览：

```bash
open login.html
```

也可以启动一个简单静态服务器：

```bash
python3 -m http.server 5173
```

然后访问：

```text
http://127.0.0.1:5173
```

## 后续接入计划

1. 把正式后端页面逐步替换为新版 Control Plane 视觉。
2. 将静态原型中的首页结论区接入真实 `/api/status` 和 `/api/history`。
3. 增强流量曲线图的小时级/天级数据展示。
4. 增加更细的阿里云云监控和 VPC Flow Logs 分析入口。

## 安全说明

公开仓库中不要提交任何真实敏感信息，包括：

- 阿里云 AccessKey ID
- 阿里云 AccessKey Secret
- 服务器 root 密码
- Telegram Bot Token
- Telegram Chat ID
- 真实 `.env` 配置文件

请只提交 `.env.example`。
