# 企业微信通讯录读取 - 参考文档

## API 基础信息

**接口**：读取成员
**请求方式**：GET
**请求地址**：
```
https://qyapi.weixin.qq.com/cgi-bin/user/get?access_token=ACCESS_TOKEN&userid=USERID
```

**接口**：获取部门成员（简易版，仅返回 userid 和 name）
**请求方式**：GET
```
https://qyapi.weixin.qq.com/cgi-bin/user/simplelist?access_token=ACCESS_TOKEN&deptid=DEPTID&fetch_child=FETCH_CHILD
```

## 返回字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `userid` | string | 成员 UserID，企业内唯一 |
| `name` | string | 成员名称（第三方不可获取，返回 userid） |
| `department` | array | 成员所属部门 ID 列表 |
| `position` | string | 职务信息 |
| `mobile` | string | 手机号码（敏感字段，新应用不再返回） |
| `email` | string | 邮箱（敏感字段，新应用不再返回） |
| `alias` | string | 别名 |
| `address` | string | 地址（敏感字段，新应用不再返回） |
| `status` | int | 激活状态：1=已激活，2=已禁用，4=未激活，5=退出 |
| `is_leader_in_dept` | array | 是否部门负责人 |
| `direct_leader` | array | 直属上级 |
| `avatar` | string | 头像 URL（敏感字段，新应用不再返回） |
| `qr_code` | string | 员工二维码（敏感字段，新应用不再返回） |


## 字段到 USER.md 的映射

| 企业微信字段 | USER.md 字段 | 备注 |
|------------|-------------|------|
| `userid` | `id` | 直接使用 |
| `name` | `name` | 注意第三方应用不可获取name |
| `alias` | `label` | 可选 |
| `position` | `title` | 可选 |
| `department` | `department` | 需从 deptId 映射为中文名称 |
| `mobile` | `mobile` | 敏感字段，可能为空 |
| `email` | `email` | 敏感字段，可能为空 |
| `status` | `status` | 1=正常 |

## 部门 ID 映射

`get` 接口返回的 `department` 是数字 ID（如 `[1, 2]`），需维护 ID → 部门名称 的映射。

可通过「获取部门列表」API 获取完整部门树：
```
GET /cgi-bin/department/list?access_token=TOKEN
```

## 批量读取注意事项

- 批量请求时建议在循环中加入 `sleep 0.2` 延迟，避免触发限频
- 每企业每天最多获取 1000 次成员信息（通讯录同步应用除外）
- 建议一次拉取完整用户列表后缓存，定期增量更新

## 官方文档链接

- 读取成员：https://developer.work.weixin.qq.com/document/path/90196
- 获取部门成员：https://developer.work.weixin.qq.com/document/path/90200
- 获取部门列表：https://developer.work.weixin.qq.com/document/path/90208
