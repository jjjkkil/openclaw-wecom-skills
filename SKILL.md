---
name: wecom-openclaw
description: 企业微信全能工具包 - 一键初始化，集成日程管理、会议预约、群聊协作、智能表格四大能力。
triggers:
  - 企业微信
  - 日程
  - 会议
  - 群聊
  - 智能表格
  - wecom
---

# WeCom OpenClaw Skills - 企业微信全能工具包

一站式企业微信自动化解决方案，支持日程管理、腾讯会议预约、群聊协作、智能表格数据驱动。

## 🚀 快速开始

### 第一步：运行初始化脚本

```bash
./scripts/init-wecom-config.sh
```

这会自动从 OpenClaw 配置中读取企业微信凭证（corp_id, agent_id, agent_secret）。

### 第二步：开始使用

初始化完成后，你可以：

| 功能 | 触发词 | 示例 |
|------|--------|------|
| **日程管理** | 创建日程、查日程、改日程 | "帮我约个明天下午3点的会" |
| **预约会议** | 预约会议、腾讯会议 | "预约周五的评审会，叫上产品组" |
| **群聊管理** | 建群、发消息 | "建个项目群，拉开发组进来" |
| **智能表格** | 查表格、提醒任务 | "看看有哪些任务快到期了" |

## 📦 包含的子 Skills

安装本 Skill 后，以下子 Skills 会自动可用：

### 📅 wecom-schedule - 日程管理
- 创建、修改、删除日程
- 支持重复日程（每日/每周/每月/工作日）
- 自动识别群聊/私聊场景

**触发词**：创建日程、修改日程、查询日程、删除日程

**文档**：`skills/wecom-schedule/SKILL.md`

---

### 🎯 wecom-meeting - 预约会议
- 创建腾讯会议，自动生成会议号
- 支持周期性会议
- 一键通知参会人

**触发词**：预约会议、创建会议、腾讯会议

**文档**：`skills/wecom-meeting/SKILL.md`

---

### 💬 wecom-groupchat - 群聊管理
- 创建、修改群聊
- 发送文本、Markdown、图片、文件
- 项目通知一键触达

**触发词**：建群、创建群聊、发送消息

**文档**：`skills/wecom-groupchat/SKILL.md`

---

### 📊 wecom-smartsheet - 智能表格
- 读取表格数据
- 自动筛选、提醒
- 驱动工作流自动化

**触发词**：查表格、智能表格、提醒任务

**文档**：`skills/wecom-smartsheet/SKILL.md`

## ⚙️ 配置说明

初始化完成后，`config.json` 会包含以下配置：

```json
{
  "wecom": {
    "corp_id": "你的企业ID",
    "corp_secret": "你的应用Secret",
    "agent_id": "你的应用AgentID",
    "default_meeting_admin": "会议管理员用户ID",
    "default_calendar_id": "默认日历ID"
  },
  "proxy": {
    "url": "http://代理地址（如需要）"
  }
}
```

## 🔧 故障排查

| 问题 | 解决方案 |
|------|----------|
| 初始化失败 | 检查 `~/.openclaw/openclaw.json` 是否包含 wecom 配置 |
| API 调用失败 | 检查代理配置，或确认服务器 IP 是否在企业微信白名单 |
| 日程不显示 | 确认已添加参与者（attendees），否则日程不会出现在个人日历 |

## 📚 更多文档

- [日程管理详细文档](skills/wecom-schedule/SKILL.md)
- [工作流指南](skills/wecom-schedule/references/workflow-guide.md)
- [示例对话](skills/wecom-schedule/references/examples.md)

## License

MIT
