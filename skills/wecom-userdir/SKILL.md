---
name: wecom-userdir
description: 从企业微信通讯录读取成员信息和部门列表，并更新 USER.md 中的联系人数据。触发词：同步通讯录、更新用户、读取成员信息、同步用户、部门列表、部门信息。
---

# Skill: 企业微信通讯录读取与 USER.md 同步

## 概述

通过企业微信 API 获取通讯录信息，支持：
1. **获取部门列表** — 调用 `department/list`，返回所有部门的 ID → 名称映射
2. **读取成员** — 调用 `user/get`，返回指定成员的完整信息
3. **批量读取成员** — 遍历多个 userid，返回所有成员的 JSON 数组
4. **按部门读取成员** — 调用 `user/simplelist`，返回某部门下所有成员的 userid 和 name

## 配置

从 workspace 根目录 `config.json` 读取企业微信应用凭证（corpId、corpSecret）和代理配置。

## 工具脚本

位置: `skills/wecom-userdir/scripts/wecom-userdir.sh`

```bash
./wecom-userdir.sh get "userid"               # 读取单个成员
./wecom-userdir.sh batch "userid1,userid2"   # 批量读取成员
./wecom-userdir.sh dept <部门ID> [fetch_child]  # 按部门获取成员 userid 列表
./wecom-userdir.sh dept-list                 # 获取所有部门列表（ID→名称映射）
```

## 核心 API

### 获取部门列表
```
GET https://qyapi.weixin.qq.com/cgi-bin/department/list?access_token=ACCESS_TOKEN
```
返回字段：`id`、`name`、`parentid`、`order`、`department_leader`

### 读取成员
```
GET https://qyapi.weixin.qq.com/cgi-bin/user/get?access_token=ACCESS_TOKEN&userid=USERID
```
返回字段：`userid`、`name`、`department`、`position`、`alias`、`status`、`direct_leader`、`isleader`、`is_leader_in_dept` 等。

### 按部门获取成员 userid 列表
```
GET https://qyapi.weixin.qq.com/cgi-bin/user/simplelist?access_token=ACCESS_TOKEN&department_id=DEPTID&fetch_child=FETCH_CHILD
```

## USER.md 联系人表格式规范

USER.md 中的联系人表格采用统一格式

### 联系人表格式

```markdown
## <组织名称>成员列表

| 姓名 | ID/Label | 别名/俗称 | 部门 | 备注 |
|------|----------|----------|------|------|
| 张三 | ZhangSan | 张总 | 产品部 | 部门负责人，直接汇报：李四 |
| 李四 | LiSi | - | 技术部 | isleader |
```

### 字段说明

| 字段 | 说明 | 是否必填 |
|------|------|---------|
| `姓名` | 成员真实姓名 | 必填 |
| `ID/Label` | 系统唯一标识（企业微信 userid ） | 必填 |
| `别名/俗称` | 昵称、简称，如"张总"，无则填 `-` | 可选 |
| `部门` | 部门名称（与 `dept-map` 中的 dept_id 对应） | 必填 |
| `备注` | 职位（position）、直接汇报对象（direct_leader）、是否为部门负责人（isleader=1 时标注）、特殊说明 | 可选 |

### 部门映射表格式（dept-map）

在联系人表之后，统一维护部门 ID → 名称的映射，供 skill 脚本解析使用：

```markdown
## 部门映射表（dept-map）

| dept_id | 部门名称 |
|---------|---------|
| 1 | 集团总部 |
| 3 | 创新业务部 |
| ... | ... |
```

**格式规则：**
- dept_id 为数字，与企业微信/飞书等系统的部门 ID 一一对应
- 部门名称为字符串，不含特殊格式
- 同一组织内 dept_id 唯一

### 字段映射（企业微信 → USER.md）

| 企业微信字段 | USER.md 字段 | 说明 |
|------------|-------------|------|
| `userid` | `ID/Label` | 直接使用 |
| `name` | `姓名` | 成员姓名 |
| `alias` | `别名/俗称` | 昵称/简称，无则填 `-` |
| `position` | `备注` | 职务信息 |
| `department[0]`（主部门） | `部门` | 通过 `dept-map` 将数字 ID 转为中文名称 |
| `isleader_in_dept` 含 1 | `备注` | 标注 `isleader` |
| `direct_leader` | `备注` | 标注直接汇报对象的 userid 或姓名 |

**注意：** `department` 字段返回的是数组（如 `[3, 5]`），取主部门（第一个）映射到 dept_id，再查 dept-map 得到部门名称。

### 完整同步流程

1. `dept-list` — 获取所有部门 ID → 名称映射，更新 USER.md 的 `dept-map`
2. `dept <部门ID> 1` — 逐个部门拉取所有成员的 userid
3. `batch <userid1,userid2,...>` — 批量拉取所有成员详情
4. 按字段映射规则，将结果写入 USER.md 联系人表

### 更新单个联系人

```bash
./wecom-userdir.sh get "User1"
# 返回该成员最新信息，对照更新 USER.md 中对应条目
```

## 注意事项

- **access_token 缓存**：脚本自动管理，token 有效期 2 小时
- **批量请求限频**：建议循环中加入 0.2s 延迟
- **部门成员获取**：需应用有通讯录「获取部门成员」权限

## 常见问题

| 错误码 | 原因 | 解决 |
|--------|------|------|
| 60011 | 无通讯录接口权限 | 联系管理员开通 |
| 60020 | IP 不在白名单 | 使用代理或添加 IP 白名单 |
| 41001 | access_token 缺失 | 检查 URL 拼接是否正确 |

## 参考文档

- 读取成员：https://developer.work.weixin.qq.com/document/path/90196
- 获取部门成员：https://developer.work.weixin.qq.com/document/path/90200
- 获取部门列表：https://developer.work.weixin.qq.com/document/path/90208
