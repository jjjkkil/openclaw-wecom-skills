# Skill: 会议日程工作流 (Meeting Workflow)

## 概述

统一处理会议和日程相关请求的**工作流协调器**。负责：
1. **意图识别** - 判断用户要创建「日程」还是「腾讯会议」
2. **场景感知** - 区分群聊/私聊，提取参与者
3. **路由分发** - 调用底层 skill 执行具体操作

底层 skills:
- `wecom-schedule` - 日程管理（无会议号）
- `wecom-meeting` - 腾讯会议（有会议号/链接）

---

## 快速判断：日程 vs 腾讯会议

| 类型 | 关键词 | 使用 Skill |
|------|--------|-----------|
| **日程** | "开会"、"会议"、"日程"、"提醒"、"安排" | `wecom-schedule` |
| **腾讯会议** | "腾讯会议"、"视频会议"、"线上会议"、"会议号"、"入会链接"、"发会议号" | `wecom-meeting` |

**关键区别**：
- **日程**：仅添加到日历，无会议号
- **腾讯会议**：生成腾讯会议号、入会链接，可直接加入视频会议

---

## 参与者提取规则

### 群聊场景

**来源**：
- **发起人**：发送消息的用户（@我的人）
- **其他被@的人**：消息中同时被@的所有用户（除我之外）

**部门自动匹配**：
- 消息中提到"XX部" → 遍历 USER.md 中所有联系人，匹配 `department` 字段，加入对应人员

### 私聊场景

**来源**：语义匹配 USER.md 中的联系人

**匹配规则**：
| 匹配方式 | 示例 | 结果 |
|---------|------|------|
| 直接姓名 | "${USER_张三}" | ${USER_张三} |
| 称呼 | "张总" | ${USER_张三} |
| ID/Label | "${USER_ZHANGSAN}" | ${USER_张三} |
| 部门 | "XX部" | 遍历 USER.md 匹配 department 字段（自动） |

**注意**：私聊中必须将**当前用户**加入参与者列表

---

## 角色配置

### 日程 (wecom-schedule)

| 角色 | 值 | 说明 |
|------|-----|------|
| 组织者 | 机器人（应用） | 固定 |
| 参与者 | 发起人 + 被@的人/匹配联系人 | 动态 |
| 管理员 | 发起人 | 可修改日程 |

### 腾讯会议 (wecom-meeting)

| 角色 | 值 | 说明 |
|------|-----|------|
| 管理员 | ${DEFAULT_MEETING_ADMIN} | **固定**，脚本自动处理 |
| 参会人 | 发起人 + 被@的人/匹配联系人 | 动态 |

---

## 工作流程

### Step 1: 意图识别

解析用户输入，判断类型：

```
用户: "明天下午3点开个会"
→ 关键词: "开会" → 类型: 日程

用户: "明天下午3点开个腾讯会议"
→ 关键词: "腾讯会议" → 类型: 腾讯会议

用户: "发我个会议号"
→ 关键词: "会议号" → 类型: 腾讯会议
```

### Step 2: 场景识别

```
消息来源: 群聊 / 私聊
```

### Step 3: 提取参与者

**群聊**：
```python
participants = [sender] + mentioned_users - [bot]
# 部门匹配：遍历 USER.md，匹配 department 字段
for contact in USER.md.contacts:
    if contact.department in message:
        participants.append(contact.id)
```

**私聊**：
```python
participants = [current_user]  # 必须包含
matched = match_contacts(message, USER.md)
# 部门匹配：遍历 USER.md，匹配 department 字段
for contact in USER.md.contacts:
    if contact.department in message:
        matched.append(contact.id)
participants.extend(matched)
# 向用户确认
```

### Step 4: 解析时间

| 用户说法 | 转换逻辑 |
|---------|---------|
| 今天 | 当前日期 |
| 明天 | 当前日期 + 1天 |
| 后天 | 当前日期 + 2天 |
| 下周 | 下周一 |
| 下周五 | 下周五 |
| 下午3点 | 15:00 |

**必须使用**: `date "+%Y-%m-%d %H:%M:%S"` 获取实时时间

### Step 5: 执行创建

**日程**：
```bash
./wecom-schedule.sh create \
  --title "会议标题" \
  --start "2026-03-20 15:00" \
  --end "2026-03-20 16:00" \
  --attendees "用户ID1,用户ID2" \
  --admins "发起人ID"
```

**腾讯会议**：
```bash
./wecom-meeting.sh create \
  --title "会议标题" \
  --start "2026-03-20 15:00" \
  --invitees "用户ID1,用户ID2"
  # 管理员 ${DEFAULT_MEETING_ADMIN} 已固定，自动加入
```

### Step 6: 反馈结果

**日程**：
```
✅ 日程创建成功！
📋 日程信息：
• 标题：xxx
• 时间：2026-03-20 15:00 - 16:00
• 参与者：xxx、xxx
```

**腾讯会议**（必须包含完整信息）：
```
✅ 会议创建成功！
📋 会议信息：
• 标题：xxx
• 时间：2026-03-20 15:00
• 时长：1小时
• 会议号：123456789
• 会议ID：hyxxxxxxxx
• 会议链接：https://wecomm.com/xxxxx
• 参会人：xxx、xxx
```

---

## 修改与取消

### 修改日程/会议

**识别关键词**："改成"、"改到"、"延期到"、"调整到"

**流程**：
1. 查询现有日程/会议获取 ID
2. 确认修改内容
3. 执行更新

**日程更新**：
```bash
./wecom-schedule.sh update \
  --schedule_id "xxx" \
  --start "2026-03-21 15:00" \
  --end "2026-03-21 16:00" \
  --skip_attendees 1
```

**会议更新**：
```bash
./wecom-meeting.sh update \
  --meetingid "hyxxx" \
  --start "2026-03-21 15:00"
```

### 取消日程/会议

**识别关键词**："取消"、"删除"、"删掉"

**日程**：
```bash
./wecom-schedule.sh delete "schedule_id"
```

**会议**：
```bash
./wecom-meeting.sh cancel "meetingid"
```

---

## 查询日程

**识别关键词**："有什么事情"、"什么安排"、"查看日程"

**流程**：
1. 解析时间范围（今天/明天/下周）
2. 查询用户日程
3. 筛选并总结

```bash
# 查询明天日程
./wecom-schedule.sh list-user "用户ID" "2026-03-21" "2026-03-21"
```

---

## 完整示例

### 示例 1: 群聊创建日程

**用户**: @Bot @张三 @李四 明天下午3点开个评审会

**处理**:
1. 类型: 日程（关键词"开会"）
2. 场景: 群聊
3. 参与者: 发起人 + 张三 + 李四
4. 时间: 明天 15:00
5. 执行:
```bash
./wecom-schedule.sh create \
  --title "评审会" \
  --start "2026-03-21 15:00" \
  --end "2026-03-21 16:00" \
  --attendees "发起人ID,张三,李四" \
  --admins "发起人ID"
```

### 示例 2: 私聊创建腾讯会议

**用户**: 约张总明天下午开腾讯会议

**处理**:
1. 类型: 腾讯会议（关键词"腾讯会议"）
2. 场景: 私聊
3. 匹配: "张总" → ${USER_张三}
4. 参与者: 当前用户 + ${USER_张三}
5. 确认: "识别到参会人：${USER_张三}，对吗？"
6. 执行:
```bash
./wecom-meeting.sh create \
  --title "腾讯会议" \
  --start "2026-03-21 15:00" \
  --invitees "当前用户ID,${USER_ZHANGSAN}"
```

### 示例 3: 涉及部门

**用户**: 约运营部明天下午开会

**处理**:
1. 类型: 日程（关键词"开会"）
2. 场景: 私聊
3. 自动识别: "运营部" → 遍历 USER.md 发现某联系人 department="运营部" → 加入该人员
4. 参与者: 当前用户 + 运营部联系人
5. 执行:
```bash
./wecom-schedule.sh create \
  --title "运营部会议" \
  --start "2026-03-21 15:00" \
  --end "2026-03-21 16:00" \
  --attendees "当前用户ID,运营部联系人ID" \
  --admins "当前用户ID"
```

---

## 相关文档

- 底层 Skill: `skills/wecom-schedule/SKILL.md`
- 底层 Skill: `skills/wecom-meeting/SKILL.md`
- 联系人配置: `USER.md`
