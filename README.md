# Aliyun CDT Guard Control Plane

Aliyun CDT Guard Control Plane 是新版面板 UI 原型项目，用来验证下一代阿里云 CDT 流量保护控制台的页面结构、视觉风格和交互方案。

这个仓库目前是静态前端原型，不连接真实阿里云 API，不保存真实 AccessKey，也不会执行真实开机、关机、通知或反代配置。

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

直接打开 `index.html` 即可预览：

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

1. 将静态假数据替换成后端接口数据。
2. 接入阿里云 ECS、CDT、CloudMonitor、BSS 账单 API。
3. 实现真实的服务器新增、编辑、开机、关机。
4. 实现 Telegram、邮件、Webhook 通知。
5. 实现账号共享 CDT 流量池的自动归组。
6. 实现一键安装、一键卸载和反代配置。

## 安全说明

公开仓库中不要提交任何真实敏感信息，包括：

- 阿里云 AccessKey ID
- 阿里云 AccessKey Secret
- 服务器 root 密码
- Telegram Bot Token
- Telegram Chat ID
- 真实 `.env` 配置文件

请只提交 `.env.example`。
