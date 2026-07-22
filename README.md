# Aliyun CDT Guard Control Plane

Aliyun CDT Guard Control Plane 是阿里云 CDT 流量保护控制台项目，用来管理多台 ECS、统计 CDT 流量、到阈值自动关机、账期重置后自动恢复、发送 Telegram/邮件/Webhook 通知，并提供账号安全和域名反代配置。

项目采用轻量 Python 后端面板，不依赖 Node.js、数据库服务或 Docker。安装脚本只部署正式运行所需文件，避免旧 UI 原型、构建产物和无用依赖占用服务器空间。

## 一键安装

推荐系统：

- Ubuntu 22.04 LTS
- Debian 12

安装脚本会自动安装运行所需的基础组件：`python3`、`python3-venv`、`curl`、`tar`、`openssl` 和 `ca-certificates`。不需要安装 Node.js、Docker、MySQL、Redis 或 Git。

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

如果继续提示类似：

```text
dpkg: error: parsing file '/var/lib/dpkg/updates/0000' near line 0:
 end of file after field name ''
```

说明 dpkg 的临时 updates 文件损坏。可以先备份并移走这个坏文件：

```bash
sudo mkdir -p /root/dpkg-updates-backup
sudo cp -a /var/lib/dpkg/updates /root/dpkg-updates-backup/updates.$(date +%s)
sudo mv /var/lib/dpkg/updates/0000 /root/dpkg-updates-backup/0000.broken.$(date +%s)
sudo dpkg --configure -a
sudo apt-get -f install
```

确认修复后再重新运行安装命令。新版安装脚本也会尝试自动把 dpkg 错误中点名的坏文件移动到 `/root/dpkg-updates-backup-*`。

如果 `dpkg --configure -a` 失败在系统内核包、GRUB 或云厂商镜像脚本上，例如 `linux-image-*`、`grub-probe`、`flash-kernel`，这属于系统包状态异常，不是面板安装失败。若服务器已经具备 `python3`、`curl`、`tar`、`openssl`，可以先跳过 apt 阶段安装面板：

```bash
curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/install.sh | sudo env SKIP_SYSTEM_PACKAGES=1 bash
```

这个命令只绕过系统依赖安装，不会修复系统内核包。建议后续仍然修复系统的 `dpkg/apt` 状态，避免以后安装其他软件继续报错。

如果系统没有 `ensurepip`，安装脚本会尝试创建不带 pip 的虚拟环境，并通过 `get-pip.py` 只给面板自己的 venv 补上 pip，不会把依赖装进系统 Python。

## 一键卸载

```bash
curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/uninstall.sh | sudo bash
```

卸载脚本只移除 systemd 服务和命令入口，默认保留配置、密钥、状态和历史记录目录：

```text
/opt/aliyun-cdt-guard-control-plane
```

确认不再需要后可以手动删除。

## 一键更新

已经安装过旧版本的服务器，可以直接执行：

```bash
curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/update.sh | sudo bash
```

更新会覆盖面板程序、巡检程序、通知程序、依赖和 systemd 服务文件，并自动重启服务。

更新会保留这些数据：

- 服务器配置和阿里云 AccessKey
- 登录备注、SSH 备注和账号密码备注
- 通知配置
- 流量状态和历史记录
- 面板登录账号密码

安装新版后，也可以在面板侧边栏进入“版本更新”，查看当前版本、GitHub 最新版本、更新命令和最近更新日志。

## 命令行

```bash
cdt-guard-control-plane status
cdt-guard-control-plane run
cdt-guard-control-plane-update
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

- 主页：账号流量池、剩余流量、真实账期重置时间、账户余额、流量曲线、重要事件。
- 服务器：按阿里云账号分组展示 ECS，明确运行中、已关机、预警和保护状态。
- 新增服务器：只展示必须填写项，高级备注信息折叠。
- 服务器日志：异常、预警、自动开机、自动关机优先展示。
- 通知设置：已配置渠道放在顶部，支持 Telegram、邮件、Webhook 的设计占位。
- 域名反代：展示 Cloudflare DNS、Caddy、Nginx 的配置思路。
- 账号安全：面板账号密码修改和会话安全设计。
- 登录页：正式面板内置登录页，桌面端居中展示账号密码输入区，移动端自动适配。

## 后续接入计划

1. 增强流量曲线图的小时级/天级数据展示。
2. 增加更细的阿里云云监控和 VPC Flow Logs 分析入口。
3. 增加更多通知渠道和更完整的日报模板。

## 安全说明

公开仓库中不要提交任何真实敏感信息，包括：

- 阿里云 AccessKey ID
- 阿里云 AccessKey Secret
- 服务器 root 密码
- Telegram Bot Token
- Telegram Chat ID
- 真实 `.env` 配置文件

请只提交 `.env.example`。
