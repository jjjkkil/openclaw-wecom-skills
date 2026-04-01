---
name: wecom-groupchat
description: 通过企业自建应用管理企业微信群聊会话、发送消息。触发词：创建群聊、修改群成员、获取群信息、向群聊发送文本/Markdown/图片/文件消息。
---

# wecom-groupchat - 企业微信群聊管理

通过企业自建应用管理企业微信群聊会话、发送消息。

## 前置要求

- 企业微信企业账号
- 企业自建应用（需配置在根部门可见）
- 应用的 `Corp ID`、`Corp Secret`、`Agent ID`

配置项写入 workspace 根目录 `config.json`：

```json
{
  "wecom": {
    "corp_id": "YOUR_CORP_ID",
    "corp_secret": "YOUR_CORP_SECRET",
    "agent_id": "YOUR_AGENT_ID"
  },
  "proxy": {
    "url": "http://user:password@YOUR_PROXY_IP:PORT"
  }
}
```

## 快速开始

```bash
# 创建群聊（至少2人）
./scripts/wecom-groupchat.sh create --name "群聊名称" --owner "userid" --userlist "user1,user2,user3"

# 修改群聊
./scripts/wecom-groupchat.sh update --chatid "CHATID" --name "新名称" --add_user_list "user4,user5"

# 获取群聊信息
./skills/wecom-groupchat/scripts/wecom-groupchat.sh get --chatid "CHATID"

# 发送文本消息
./scripts/wecom-groupchat.sh send-text --chatid "CHATID" --content "消息内容"

# 发送 Markdown 消息
./scripts/wecom-groupchat.sh send-markdown --chatid "CHATID" --content "**加粗** 内容"

# 发送图片/文件消息（需先通过媒体文件接口上传获取 media_id）
./scripts/wecom-groupchat.sh send-image --chatid "CHATID" --media_id "MEDIA_ID"
./scripts/wecom-groupchat.sh send-file --chatid "CHATID" --media_id "MEDIA_ID"
```

## 群聊信息记录

创建群聊后，建议将群聊信息记录到 USER.md，方便后续快速识别群成员：

**USER.md 群聊记录格式**：

```markdown
## Group Chats

| 群聊名称 | ChatID | 群主 | 成员 | 备注 |
|---------|--------|------|------|------|
| 产品评审群 | CHATID123 | 张三 | 张三、李四、王五 | 周会群 |
| 运营沟通群 | CHATID456 | 赵六 | 赵六、孙七、周八 | 运营部 |
```

**记录时机**：
1. 创建群聊后，API 返回 `chatid`
2. 调用 `get` 命令获取完整群聊信息
3. 将群聊名称、chatid、群主、成员列表整理填入 USER.md

**用途**：
- 用户说"给产品评审群发消息"时，可通过群聊名称匹配到 `chatid`
- 用户说"约群成员开会"时，可从成员列提取参会人
- 避免重复询问用户群成员有哪些人

## 命令参考

| 命令 | 说明 |
|------|------|
| `create` | 创建群聊会话 |
| `update` | 修改群聊（名称、成员） |
| `get` | 获取群聊信息 |
| `send-text` | 发送文本消息 |
| `send-markdown` | 发送 Markdown 消息 |
| `send-image` | 发送图片消息 |
| `send-file` | 发送文件消息 |

详细 API 文档见 `references/api.md`
