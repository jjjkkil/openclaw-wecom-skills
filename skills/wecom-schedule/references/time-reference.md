# 时间转换参考

## 时间描述转换

| 用户说法 | 转换后的日期变量 |
|---------|----------------|
| 今天 | `$DATE_TODAY` |
| 明天 | `$DATE_TOMORROW` |
| 后天 | `$DATE_DAY_AFTER` |
| 下周 | `$DATE_NEXT_MONDAY`（下周一）|
| 下周五 | `$DATE_NEXT_FRIDAY` |

## 重复日程类型

| repeat_type | 说明 | 是否需要 is_custom_repeat |
|-------------|------|---------------------------|
| 0 | 每天重复 | 否 |
| 1 | 每周重复 | 可选（指定周几时需要） |
| 2 | 每月重复 | 可选（指定日期时需要） |
| 5 | 每年重复 | 否 |
| 7 | 工作日重复（周一至周五） | 否 |

### 创建重复日程示例

| 类型 | 命令参数 |
|------|---------|
| 每周周三例会 | `--is_repeat 1 --repeat_type 1 --is_custom_repeat 1 --repeat_day_of_week "3" --repeat_until "${DATE_FUTURE}"` |
| 工作日日报提醒 | `--is_repeat 1 --repeat_type 7` |
| 每月1号和15号 | `--is_repeat 1 --repeat_type 2 --is_custom_repeat 1 --repeat_day_of_month "1,15" --repeat_until "${DATE_FUTURE}"` |
| 双周会议 | `--is_repeat 1 --repeat_type 1 --is_custom_repeat 1 --repeat_interval 2 --repeat_day_of_week "3" --repeat_until "${DATE_FUTURE}"` |

### 修改重复日程

| 操作 | 命令参数 |
|------|---------|
| 仅修改这一次 | `--op_mode 1 --op_start_time $TIMESTAMP` |
| 修改将来所有 | `--op_mode 2 --op_start_time $TIMESTAMP` |
| 取消后续重复 | `--repeat_until "${DATE_FUTURE}" --skip_attendees 1` |
