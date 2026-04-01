---
name: wecom-meeting
description: 通过企业微信 API 创建、管理和操作预约会议（腾讯会议）。触发词：创建会议、修改会议、取消会议、查询会议详情。
---

# Skill: 企业微信预约会议管理

## 概述

通过企业微信 API 创建、管理和操作预约会议（腾讯会议），支持代理配置以解决动态 IP 问题。与「日程」不同，预约会议会直接创建腾讯会议，生成会议号和会议链接，参会人可通过企业微信直接加入。

**配置**：管理员通过 workspace 根目录 `config.json` 的 `default_meeting_admin` 字段配置。

## 前置条件

- 企业微信自建应用已配置
- 应用已获得「会议接口权限」
- 配置了 HTTP 代理（服务器 IP 动态）

## 工具脚本

位置: `skills/wecom-meeting/scripts/wecom-meeting.sh`（相对于 workspace 目录）

corpSecret 存储在 OpenClaw 配置中，脚本自动获取。管理员 `${DEFAULT_MEETING_ADMIN}` 通过 config.json 配置。

## 工作流程

### 创建会议
1. 确认当前日期（`date` 命令）
2. 将时间描述（今天/明天/下周等）转换为具体日期
3. 识别参与者（被@的人或语义匹配联系人）
4. 执行创建（admin 从配置读取）
5. **向发起人返回完整会议信息**：标题、时间、会议号、meetingid、会议链接、时长、参会人

### 修改会议
识别关键词：改成、改到、延期、调整。获取 meetingid → 确认修改内容 → `update` 执行

### 取消会议
识别关键词：取消、删掉、删除。确认 meetingid → `cancel` 执行

## 可用操作

### 创建会议
```bash
./wecom-meeting.sh create --title "标题" --start "YYYY-MM-DD HH:MM" [--duration 3600] [--description "描述"] [--invitees "user1,user2"] [--hosts "host1"] [--password "1234"]
```

### 修改会议
```bash
./wecom-meeting.sh update --meetingid "ID" [--title "新标题"] [--start "新时间"] [--duration 7200] [--invitees "user1"]
```
- `meetingid` 必需；不传的参数保持原值

### 取消会议
```bash
./wecom-meeting.sh cancel "meetingid"
```

### 查询会议详情
```bash
./wecom-meeting.sh info "meetingid"
```

### 列出用户会议（获取成员会议ID列表）
```bash
./wecom-meeting.sh list "userid" ["开始时间"] ["结束时间"]
```
- 用途：查询指定成员在某个时间段内的会议ID列表
- 参数：userid（必需），开始/结束时间格式 `YYYY-MM-DD HH:MM`（可选，默认今天至未来7天）
- 返回：会议ID列表，需配合 `info` 命令获取详情

## 场景处理

### 私聊
- 语义匹配 USER.md 联系人确定参与者
- 提到具体部门关键词时自动添加对应成员
- 发起人须加入参会人列表并设为主持人

### 群聊
- 提取所有被@用户作为参与者
- 发送消息的用户为发起人（加入参会人、设为主持人）
- 部门关键词 → 自动添加对应成员


## 参考文档

详细错误码说明和官方 API 链接请参阅 `references/README.md`。
