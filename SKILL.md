---
name: wecom-openclaw
description: 企业微信全能工具包 - 日程管理、会议预约、群聊协作、智能表格四大能力。安装后自动包含所有子技能。
triggers:
  - 企业微信
  - 日程
  - 会议
  - 群聊
  - 智能表格
  - wecom
---

# WeCom OpenClaw Skills

企业微信集成 OpenClaw 技能包。安装后以下子技能自动可用：wecom-schedule、wecom-meeting、wecom-groupchat、wecom-smartsheet、wecom-userdir。

## 安装步骤

**第一步**：确认 workspace 根目录存在 `config.json`（包含企业微信凭证），若不存在则创建：

```bash
cp config.example.json config.json
# 填入 corp_id、corp_secret、agent_id
```

**第二步**（推荐）：运行初始化脚本，自动从 OpenClaw 配置读取凭证：

```bash
./scripts/init-wecom-config.sh
```

**第三步**：确认 `config.json` 中 `default_meeting_admin` 已填写（企业微信管理后台 → 成员列表中的管理员用户ID）。

**第四步**：确认 `skills/wecom-token.sh` 存在于 `skills/` 根目录下，所有子技能统一通过该脚本管理 access_token：
- `./skills/wecom-token.sh get`：获取 access_token（自动缓存，未过期直接返回）
- `./skills/wecom-token.sh force-refresh`：强制刷新 token
token 自动缓存到根目录 `config.json` 中，无需手动维护。

> 脚本路径规范：`skills/<skill>/scripts/<script>.sh`，配置在 workspace 根目录的 `config.json`，无需额外配置路径。

## 子技能

| 技能 | 触发词 |
|------|--------|
| wecom-schedule | 创建日程、查日程、改日程、删日程 |
| wecom-meeting | 预约会议、腾讯会议 |
| wecom-groupchat | 建群、发消息 |
| wecom-smartsheet | 查表格、智能表格 |
| wecom-userdir | 查通讯录、查成员 |

## 故障排查

| 问题 | 方案 |
|------|------|
| 配置文件不存在 | 在 workspace 根目录创建 `config.json`，参考 `config.example.json` |
| API 调用失败 | 检查 `proxy.url` 配置，或确认服务器 IP 在企业微信白名单 |
| 日程不显示在日历 | 确认已将用户加入 attendees，否则不会出现在个人日历 |

详细文档请参考各子技能的 SKILL.md。
