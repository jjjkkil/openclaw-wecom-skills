---
name: wecom-schedule
description: 在企业微信群聊或私聊场景下，通过企业自建应用创建、管理和查询日程，支持重复日程和参与者管理。触发词：创建日程、修改日程、查询日程、删除日程、添加参与者。
---

# Skill: 企业微信日程管理

## 概述

通过企业微信自建应用创建、管理和查询日程，支持重复日程、参与者管理和代理配置。群聊场景与私聊场景管理员设置规则不同，请参考 references/workflow-guide.md。

## 前置条件

1. 企业微信自建应用已配置，并获得「日程接口权限」
2. HTTP 代理已配置（服务器 IP 动态）
3. `jq` 工具已安装（用于客户端日期筛选）

## 工具脚本位置

`skills/wecom-schedule/scripts/wecom-schedule.sh`（相对于 workspace 目录）

配置通过 workspace 根目录的 `config.json` 统一管理。

## 日程管理命令速查

| 操作 | 命令 | 关键参数 |
|------|------|---------|
| 创建日历 | `./wecom-schedule.sh create-calendar "名称" ["描述"]` | 返回 `cal_id` |
| 获取日历详情 | `./wecom-schedule.sh get-calendar "cal_id"` | 支持多 cal_id |
| 创建日程 | `./wecom-schedule.sh create --title ... --start ... --end ... --attendees ... --admins ...` | attendees第一个成员为发起人，admins必填（最多3人） |
| 添加参与者 | `./wecom-schedule.sh add-attendees "schedule_id" "user1" "user2"` | |
| 查询用户日程 | `./wecom-schedule.sh list-user "userid" "$DATE_TODAY" "$DATE_TODAY"` | 推荐方式 |
| 查询日历日程 | `./wecom-schedule.sh list-cal "${DEFAULT_CAL_ID}" ...` | 需要 `cal_id`，用 `jq` 本地过滤日期 |
| 获取日程详情 | `./wecom-schedule.sh get "schedule_id"` | |
| 更新日程 | `./wecom-schedule.sh update --schedule_id ... --start ... --end ...` | `--skip_attendees 1` 保持参与者；重复日程用 `--op_mode` |
| 删除日程 | `./wecom-schedule.sh delete "schedule_id"` | |

**核心注意事项**：
- `admins` 参数必填，为日程管理员（最多3人），必须在 `attendees` 列表中
- `attendees` 第一个成员即为日程发起人
- 群聊场景：发起人通常为群主或@机器人的用户；私聊场景：发起人为当前私聊用户
- 创建后**必须**将用户添加为 attendee，否则日程不会显示在用户日历中
- 群聊场景：管理员设为**发起人**；私聊场景：管理员设为**当前私聊用户**
- 查询只返回**发起人**的日程
- 已预约会议室的日程无法修改时间和重复相关字段（需先取消会议室）

## references/ 引用指引

| 场景 | 查阅文件 |
|------|---------|
| 时间/日期表达转换、重复日程参数详解 | `references/time-reference.md` |
| 创建/修改日程标准流程、群聊/私聊场景处理 | `references/workflow-guide.md` |
| 完整示例对话和命令输出 | `references/examples.md` |
| 错误码含义和排查 | `references/error-codes.md` |
