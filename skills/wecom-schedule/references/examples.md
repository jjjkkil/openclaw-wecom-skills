# 示例

## 示例1：普通日程创建

**用户**: "帮我创建一个明天下午的会议，标题是产品评审会，时间是下午3点到4点"

**助手**:
```bash
# 1. 确认日期 → $DATE_TOMORROW
# 2. 创建日程
./wecom-schedule.sh create \
  --title "产品评审会" \
  --start "$DATE_TOMORROW 15:00" \
  --end "$DATE_TOMORROW 16:00" \
  --attendees "$CREATOR_USERID,${USER_X},${USER_Y}" \
  --admins "$CREATOR_USERID"

# ⚠️ 必须添加参与者，否则日程不会显示在用户日历中！
```

## 示例2：每周例会（重复日程）

**用户**: "创建一个每周三下午2点的周例会"

```bash
./wecom-schedule.sh create \
  --title "周例会" \
  --start "$DATE_TODAY 14:00" \
  --end "$DATE_TODAY 15:00" \
  --attendees "$CREATOR_USERID,${USER_X}" \
  --admins "$CREATOR_USERID" \
  --is_repeat 1 --repeat_type 1 --is_custom_repeat 1 \
  --repeat_day_of_week "3" --repeat_until "${DATE_FUTURE}"
```

## 示例3：修改日程

**用户**: "把明天中午的会议改到下午3点"

```bash
# 1. 查询明天的日程获取 schedule_id
./wecom-schedule.sh list-user "$CREATOR_USERID" "$DATE_TOMORROW" "$DATE_TOMORROW"

# 2. 使用更新接口修改时间
./wecom-schedule.sh update \
  --schedule_id "xxx" \
  --start "$DATE_TOMORROW 15:00" \
  --end "$DATE_TOMORROW 16:00" \
  --skip_attendees 1
```

## 示例4：添加参与者

**用户**: "在已有的日程里添加小李"

```bash
./wecom-schedule.sh add-attendees "$SCHEDULE_ID" "${USER_X}"
```

## 示例对话：完整对话流程

### 场景1：创建会议

**用户**: "帮我创建一个明天下午的会议"

**助手**:
好的，请问会议的具体信息如下：
- 标题是？
- 具体时间是下午几点到几点？
- 需要邀请哪些人？

**用户**: "下午3点到4点，标题是产品评审会，帮我和${USER_ADMIN}约一下"

**助手**:
好的，我来创建这个日程：
- 标题：产品评审会
- 时间：明天下午3点到4点
- 参与者：您（发起人）+ ${USER_ADMIN}

```bash
./wecom-schedule.sh create \
  --title "产品评审会" \
  --start "$DATE_TOMORROW 15:00" \
  --end "$DATE_TOMORROW 16:00" \
  --attendees "$CREATOR_USERID,${USER_ADMIN}" \
  --admins "$CREATOR_USERID"
```

已成功创建！日程已添加到您的日历中。

### 场景2：查询日程

**用户**: "明天我有什么事情？"

**助手**:
让我查一下您的日程：

```bash
./wecom-schedule.sh list-user "$CREATOR_USERID" "$DATE_TOMORROW" "$DATE_TOMORROW"
```

查询到您明天有以下日程：
- 15:00-16:00 产品评审会

### 场景3：修改日程

**用户**: "把明天的产品评审会改到下午4点"

**助手**:
好的，我来帮您调整时间。先查一下日程ID：

```bash
./wecom-schedule.sh list-user "$CREATOR_USERID" "$DATE_TOMORROW" "$DATE_TOMORROW"
```

找到日程，现在修改时间：

```bash
./wecom-schedule.sh update \
  --schedule_id "$SCHEDULE_ID" \
  --start "$DATE_TOMORROW 16:00" \
  --end "$DATE_TOMORROW 17:00" \
  --skip_attendees 1
```

已更新！产品评审会已改到明天下午4点。

## 常用命令速查

```bash
# 创建日程
./wecom-schedule.sh create \
  --title "会议标题" \
  --start "$DATE_TODAY 14:00" \
  --end "$DATE_TODAY 15:00" \
  --attendees "$CREATOR_USERID,user1,user2" \
  --admins "$CREATOR_USERID"

# 查询用户日程
./wecom-schedule.sh list-user "userid" "$DATE_TODAY" "$DATE_TODAY"

# 查询日历日程
./wecom-schedule.sh list-cal "${DEFAULT_CAL_ID}" "$DATE_TODAY" "$DATE_TODAY"

# 获取日程详情
./wecom-schedule.sh get "schedule_id"

# 更新日程
./wecom-schedule.sh update \
  --schedule_id "日程ID" \
  --start "$DATE_TOMORROW 15:00" \
  --end "$DATE_TOMORROW 16:00" \
  --skip_attendees 1

# 添加参与者
./wecom-schedule.sh add-attendees "$SCHEDULE_ID" "user1" "user2"

# 删除日程
./wecom-schedule.sh delete "schedule_id"
```
