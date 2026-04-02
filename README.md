# WeCom OpenClaw Skills

> ⚠️ **重要说明**：企业微信只支持**自建应用**的服务端接口适配，使用本技能包需要 OpenClaw 已接入企业微信自建应用渠道。关于如何配置企业微信自建应用渠道，请参考 [YanHaidao/wecom](https://github.com/YanHaidao/wecom)。
## 相关项目
本项目的企业微信配置参考自 [YanHaidao/wecom](https://github.com/YanHaidao/wecom)。


企业微信集成 OpenClaw 的技能包，支持群聊管理、日程会议、智能表格（Smartsheet）功能。

## ✨ 看看你能做什么

> 💬 **"帮我约个会，明天下午3点，叫上产品组的人"**
> 
> 助手自动创建腾讯会议，生成会议号，一键通知所有人。

---

> 📅 **"每周三下午2点提醒我开周会"**
> 
> 助手创建重复日程，自动拉入团队成员，到期自动提醒。

---

> 💬 **"建个项目群，把开发组和设计组拉进来"**
> 
> 助手秒建群聊，发送项目启动通知，支持 Markdown 格式。

---

> 📊 **"看看表格里有哪些任务快到期了，提醒负责人"**
> 
> 助手读取智能表格，筛选即将到期的任务，@相关负责人。

---

> 🔄 **"每天早上9点自动发今日待办"**
> 
> 定时任务驱动，让重复性工作自动化，你专注更重要的事。

---



## 目录结构

```
wecom-openclaw/
├── README.md
├── LICENSE
├── config.example.json          # 配置文件模板
├── scripts/
│   └── init-wecom-config.sh    # 从 OpenClaw 配置初始化凭证
└── skills/
    ├── wecom-groupchat/         # 企业微信群聊管理
    ├── wecom-schedule/          # 企业微信日程管理
    ├── wecom-meeting/           # 企业微信预约会议
    └── wecom-smartsheet/        # 企业微信智能表格
```

## OpenClaw Agent 初始化引导

将以下内容作为 system prompt 或首次对话引导使用：

---

**欢迎使用 WeCom OpenClaw Skills！**

在开始之前，需要完成以下初始化步骤：

### 第一步：运行初始化脚本获取凭证

```bash
./scripts/init-wecom-config.sh
```

这会自动从 OpenClaw 的 `openclaw.json` 中读取企业微信的 `corp_id`、`agent_id`、`agent_secret`，并写入 `config.json`。

脚本会引导你选择使用的企业微信账号（如 `account1`/`account2` 等，对应 OpenClaw 中 wecom 插件配置的 `channels.wecom.accounts` 下的账号 key）。

> **账号与 OpenClaw 配置的对应关系**：初始化脚本读取的是 `~/.openclaw/openclaw.json` 中 `channels.wecom.accounts` 下定义的账号。每个账号 key（如 `account1`）对应一个企业微信自建应用配置，包含 `corpId`、`agentId`、`agentSecret` 等。通过指定账号 key，脚本会自动提取对应的企业微信凭证写入 `config.json`。

### 第二步：确认以下参数的默认值

初始化完成后，请确认 `config.json` 中以下字段是否需要填写：

| 字段 | 含义 | 如何获取 |
|------|------|---------|
| `default_meeting_admin` | 预约会议的管理员用户ID | 企业微信管理后台 → 成员列表 → 找到负责创建会议的管理员账号 |
| `default_calendar_id` | 日程使用的日历ID | 日程接口权限开通后，调用一次创建日历接口会返回日历ID |

> **日历ID说明**：如果这是你第一次使用日程功能，可以跳过此字段，脚本会使用企业微信自动创建的默认日历。如果需要使用特定日历（如共享日历），请先手动创建一个日历，然后将返回的 `cal_id` 填入。

**是否需要创建默认日历？**

如果你的应用尚未创建任何日历，运行以下命令创建一个（创建后返回的日历ID即为 `default_calendar_id`）：

```bash
./skills/wecom-schedule/scripts/wecom-schedule.sh create-calendar "我的日历" "用于团队日程管理"
```

创建成功后，日历信息会自动保存到 `config.json` 中的 `calendars` 字典，**无需手动记录**。

查看已保存的日历：

```bash
./skills/wecom-schedule.sh list-cals
```

> **多日历支持**：`calendars` 是一个字典，键为日历 ID，值为名称、描述、创建时间等信息。第一个创建的日历会自动成为默认日历；之后的创建顺序不影响默认选择。调用日程命令时若不指定 `--calId`，默认使用第一个日历。

### 第三步：确认其他参数（可选）

| 字段 | 含义 | 如何获取 |
|------|------|---------|
| `default_meeting_admin` | 预约会议的管理员用户ID | 企业微信管理后台 → 成员列表 → 找到负责创建会议的管理员账号 |
| `calendars` | 日历字典 | 创建日历时自动写入，第一个日历自动成为默认日历 |

### 第三步：检查代理配置

如果你的服务器 IP 会经常变动，脚本可能无法访问企业微信 API，此时需要在 `config.json` 中填入 `proxy.url`。

如果服务器 IP 固定，跳过此字段即可。

### 完成后

配置完成！现在可以开始使用了。你可以：
- 让助手帮你创建群聊、发送消息
- 创建日程并自动邀请参与者
- 预约腾讯会议并获取会议链接
- 在企业微信智能表格中管理数据

---

## 快速开始

### 1. 配置凭证

**方式一：自动初始化（推荐）**

```bash
# 从 OpenClaw 配置自动读取企业微信凭证
./scripts/init-wecom-config.sh

# 或指定账号 key（对应 openclaw.json 中 channels.wecom.accounts 下的 key）：
./scripts/init-wecom-config.sh account1
./scripts/init-wecom-config.sh account2
```

> 账号 key 如 `account1`、`account2` 等，是你在 OpenClaw 的 wecom 插件配置中定义的 `channels.wecom.accounts` 下的 key 名。运行脚本时会列出所有可用的账号供选择。

**方式二：手动配置**

复制配置模板并填写：

```bash
cp config.example.json config.json
# 编辑 config.json，填入实际的 corp_id、corp_secret 等
```

`config.json` 字段说明：

| 字段 | 说明 |
|------|------|
| `wecom.corp_id` | 企业 ID |
| `wecom.corp_secret` | 应用Secret |
| `wecom.agent_id` | 应用AgentID |
| `wecom.default_meeting_admin` | 预约会议的默认管理员用户ID |
| `wecom.calendars` | 日历字典（键为 ID，值为 name/description/created_at），第一个键自动作为默认日历 |
| `proxy.url` | HTTP代理地址（服务器IP不固定时需要） |

### 2. 技能说明

#### wecom-groupchat — 群聊管理

- 创建、修改、获取群聊会话
- 发送文本、Markdown、图片、文件消息

```bash
./skills/wecom-groupchat/wecom-groupchat.sh create --name "测试群" --userlist "user1,user2"
./skills/wecom-groupchat/wecom-groupchat.sh send-text --chatid "CHATID" --content "Hello"
```

#### wecom-schedule — 日程管理

- 创建、修改、删除日程
- 支持重复日程（每日/每周/每月/工作日）
- 查询用户/日历日程

```bash
./skills/wecom-schedule/scripts/wecom-schedule.sh create \
  --title "周例会" \
  --start "2025-01-15 14:00" \
  --end "2025-01-15 15:00" \
  --attendees "user1,user2" \
  --admins "user1"
```

#### wecom-meeting — 预约会议

- 创建腾讯会议（生成会议号/链接）
- 修改、取消会议
- 查询会议详情

```bash
./skills/wecom-meeting/scripts/wecom-meeting.sh create \
  --title "产品评审会" \
  --start "2025-01-16 09:00" \
  --invitees "user1,user2"
```

#### wecom-smartsheet — 智能表格

- 管理文档、子表、视图、字段、记录
- 支持看板、甘特图等视图

```bash
./skills/wecom-smartsheet/scripts/create-sheet.sh create --name "项目预算表"
```

---

## 前置要求

- 企业微信自建应用已开通相关权限
- 服务器能访问 `qyapi.weixin.qq.com`（或配置代理）
- `bash` + `curl` + `jq`（推荐安装，脚本会 fallback 到 grep）

## 注意事项

- **敏感信息勿提交**：请将 `config.json` 加入 `.gitignore`，不要将实际凭证提交到仓库
- **代理配置**：若服务器 IP 不固定，需配置代理服务器，所有脚本均支持 `proxy.url`
- **智能表格权限**：需在企业微信管理端「协作→文档→API」中配置可调用接口的应用

## License

MIT
