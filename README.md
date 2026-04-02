# WeCom OpenClaw Skills

企业微信集成 OpenClaw 的技能包，支持群聊管理、日程会议、智能表格（Smartsheet）功能。

> ⚠️ **重要说明**：企业微信只支持**自建应用**的服务端接口适配，使用本技能包需要 OpenClaw 已接入企业微信自建应用渠道。关于如何配置企业微信自建应用渠道，请参考 [YanHaidao/wecom](https://github.com/YanHaidao/wecom)。

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
openclaw-wecom-skills/           # 技能包
├── README.md
├── LICENSE
├── SKILL.md                     # 整体技能描述
├── clawhub.yaml                 # Clawhub 发布配置
├── config.example.json          # 配置文件模板
├── config.json                  # ⚠️ 实际配置（首次安装需创建）
├── scripts/
│   └── init-wecom-config.sh    # 从 OpenClaw 配置初始化凭证
└── skills/
    ├── wecom-groupchat/
    │   └── scripts/wecom-groupchat.sh
    ├── wecom-schedule/
    │   └── scripts/wecom-schedule.sh
    ├── wecom-meeting/
    │   └── scripts/wecom-meeting.sh
    ├── wecom-smartsheet/
    │   └── scripts/wecom-smartsheet.sh
    └── wecom-userdir/
        └── scripts/wecom-userdir.sh
```

## 安装与配置

### 目录结构约定

本技能包遵循 **OpenClaw Skill 标准目录规范**：

```
<workspace>/
├── config.json                  # ⚠️ 配置文件（安装时创建）
├── scripts/
│   └── init-wecom-config.sh
└── skills/
    └── <skill-name>/
        ├── SKILL.md
        └── scripts/
            └── <skill-name>.sh
```

**路径规范**：所有脚本位于 `skills/<skill>/scripts/` 下，脚本内部通过 `SCRIPT_DIR/../../..` 向上三层定位 workspace 根目录。这一约定是固定的，只要遵守规范，无需任何额外配置。

### 安装步骤

**第一步**：将本包复制到 OpenClaw workspace 目录下（可作为 workspace 根目录，或放入 `skills/` 下）。

**第二步**：创建 `config.json`：

```bash
cp config.example.json config.json
# 编辑 config.json 填入 corp_id、corp_secret、agent_id 等
```

**第三步**：运行初始化脚本（推荐，自动从 OpenClaw 配置读取凭证）：

```bash
./scripts/init-wecom-config.sh
# 或指定账号 key：
./scripts/init-wecom-config.sh account1
```

> 账号 key 对应 OpenClaw 的 `openclaw.json` 中 `channels.wecom.accounts` 下的 key 名，如 `account1`、`account2`。不指定则列出所有可用账号供选择。

**第四步**：确认 `config.json` 中以下字段：

| 字段 | 含义 | 如何获取 |
|------|------|---------|
| `default_meeting_admin` | 预约会议的管理员用户ID | 企业微信管理后台 → 成员列表 |
| `proxy.url` | HTTP 代理地址 | 服务器 IP 不固定时需要，固定则留空 |

**第五步**（可选）：创建默认日历：
需要询问用户是否创建共享日历，运行以下命令可创建日历

```bash
./skills/wecom-schedule/scripts/wecom-schedule.sh create-calendar "我的日历" "用于团队日程管理"
```

日历创建成功后会自动保存到 `config.json` 的 `calendars` 字典，无需手动记录。

### 快速验证

```bash
# 查看已保存的日历
./skills/wecom-schedule/scripts/wecom-schedule.sh list-cals

# 或直接运行任意脚本，不报 "配置文件不存在" 即为正常
./skills/wecom-groupchat/scripts/wecom-groupchat.sh help
```

## 技能说明

### wecom-groupchat — 群聊管理

创建、修改、获取群聊会话；发送文本、Markdown、图片、文件消息。

```bash
./skills/wecom-groupchat/scripts/wecom-groupchat.sh create --name "测试群" --userlist "user1,user2"
./skills/wecom-groupchat/scripts/wecom-groupchat.sh send-text --chatid "CHATID" --content "Hello"
```

### wecom-schedule — 日程管理

创建、修改、删除日程；支持重复日程（每日/每周/每月/工作日）；查询用户/日历日程。

```bash
./skills/wecom-schedule/scripts/wecom-schedule.sh create \
  --title "周例会" \
  --start "2025-01-15 14:00" \
  --end "2025-01-15 15:00" \
  --attendees "user1,user2" \
  --admins "user1"
```

### wecom-meeting — 预约会议

创建腾讯会议（生成会议号/链接）；修改、取消、查询会议。

```bash
./skills/wecom-meeting/scripts/wecom-meeting.sh create \
  --title "产品评审会" \
  --start "2025-01-16 09:00" \
  --invitees "user1,user2"
```

### wecom-smartsheet — 智能表格

管理文档、子表、视图、字段、记录；支持看板、甘特图等视图。

```bash
./skills/wecom-smartsheet/scripts/create-sheet.sh create --name "项目预算表"
```

## 前置要求

- 企业微信自建应用已开通相关权限
- 服务器能访问 `qyapi.weixin.qq.com`（或配置代理）
- `bash` + `curl` + `jq`（脚本在无 jq 时会 fallback 到 grep，但推荐安装 jq）

## 注意事项

- **敏感信息勿提交**：请将 `config.json` 加入 `.gitignore`，不要将实际凭证提交到仓库
- **代理配置**：若服务器 IP 不固定，需配置代理服务器，所有脚本均支持 `proxy.url`
- **智能表格权限**：需在企业微信管理端「协作→文档→API」中配置可调用接口的应用

## 相关项目

本项目的企业微信配置参考自 [YanHaidao/wecom](https://github.com/YanHaidao/wecom)。

## License

MIT
