---
name: wecom-userdir
description: 从企业微信通讯录读取成员信息（单个或批量），并更新 USER.md 中的联系人数据。触发词：同步通讯录、更新用户、读取成员信息、同步用户。
---

# Skill: 企业微信通讯录读取与 USER.md 同步

## 概述

通过企业微信「读取成员」API（`GET /cgi-bin/user/get`）获取指定成员的信息，支持单个获取和批量遍历。可用于：
1. **首次同步**：根据已知 userid 列表，从企业微信拉取档案填充 USER.md
2. **增量更新**：给定一个 userid，更新 USER.md 中对应联系人的最新信息
3. **按部门拉取**：配合「获取部门成员」API 批量拉取某部门下所有成员

**配置**：从 workspace 根目录 `config.json` 读取企业微信应用凭证（corpId、corpSecret、agentId）。

## 前置条件

- 企业微信自建应用已配置
- 应用已获得「通讯录」相关权限（成员信息需「成员授权」或通讯录同步应用）
- `jq` 已安装（用于 JSON 解析）

## 工具脚本

位置: `skills/wecom-userdir/scripts/wecom-userdir.sh`

corpSecret 存储在 `config.json` 中，脚本自动获取并管理 access_token 缓存。

## 核心 API

**读取成员**
```
GET https://qyapi.weixin.qq.com/cgi-bin/user/get?access_token=ACCESS_TOKEN&userid=USERID
```

返回字段：`userid`、`name`、`department`、`position`、`mobile`、`email`、`alias`、`address`、`status` 等。

## 操作

### 读取单个成员

```bash
./wecom-userdir.sh get "userid"
```

返回 JSON，包含该成员在企业微信通讯录中的完整信息。

### 批量读取（按 userid 列表）

```bash
./wecom-userdir.sh batch "userid1,userid2,userid3"
```

遍历列表，逐个调用 `get` 接口，输出所有成员的 JSON 数组。

### 按部门读取成员列表

需要先调用「获取部门成员」API：
```
GET https://qyapi.weixin.qq.com/cgi-bin/user/simplelist?access_token=ACCESS_TOKEN&deptid=DEPTID&fetch_child=FETCH_CHILD
```

可用 `wecom-userdir.sh dept "部门ID" [fetch_child]` 获取部门下所有成员的 userid，再配合 `batch` 批量拉取详情。

### 更新 USER.md

读取到成员数据后，手动将信息填入 USER.md 的联系人表格。

**USER.md 联系人表格格式**：

| 姓名 | ID/Label | 别名/俗称 | 部门 | 备注 |
|------|----------|----------|------|------|
| 张三 | ZhangSan | - | 技术部 | 主要用户 |
| 李四 | LiSi | 李总 | 产品部 | - |
| 王五 | WangWu | - | 运营部 | 提到xxx时需YYY |

**字段映射**：

| 企业微信字段 | USER.md 字段 | 说明 |
|------------|-------------|------|
| `userid` | ID/Label | 企业微信 userid，直接使用 |
| `name` | 姓名 | 成员姓名 |
| `alias` | 别名/俗称 | 昵称/简称（可选） |
| `position` | - | 职务可填入备注 |
| `department` | 部门 | 需从 deptId 映射为中文部门名 |
| `status` | - | 激活状态，非必要不显示 |

**分组方式**：
按组织架构分组，如「技术团队」、「运营团队」等。

## 典型工作流

### 首次全量同步

1. 获取所有部门的 `deptId`（通过 `wecom-dept.sh list` 或企业微信管理后台）
2. 用 `dept` 命令逐个部门拉取成员 userid
3. 用 `batch` 批量拉取成员详情
4. 将结果整理写入 USER.md

### 更新单个联系人

```bash
./wecom-userdir.sh get "User1"
# 返回该成员最新信息，对照更新 USER.md 中对应条目
```

## 注意事项

- **字段权限**：从 2022 年 6 月起，新创建的自建应用不再返回 `mobile`、`email`、`avatar` 等敏感字段，需通过 OAuth2 授权获取
- **部门 ID vs 部门名称**：`get` 接口返回的是部门 ID（数字），需自行维护 ID→名称 映射
- **access_token 缓存**：脚本自动管理，token 有效期 2 小时，无需手动刷新
- **限流**：批量请求时注意接口限频，建议在循环中加入适当延迟

## 常见问题排查

### 60020 - not allow to access from your ip
**原因**：当前服务器 IP 不在企业微信应用的白名单里。  
**解决**：
1. 使用配置好的代理（`config.json` 中 `proxy.url`）
2. 或将当前 IP 添加到企业微信管理后台 → 应用管理 → 对应应用 → 「企业微信授权登录」→ 「IP白名单」

### 60011 - no privilege to access/modify contact/party/agent
**原因**：当前应用（agent_id）没有通讯录接口权限。  
**解决**：
1. 切换到拥有通讯录权限的应用（如 `business` 账号）
2. 或在企业微信管理后台给当前应用开通「通讯录」相关接口权限

### 60003 - department not found
**原因**：部门 ID 不存在，或 API 参数名错误。  
**解决**：
- 确认部门 ID 正确（可通过 `dept` 命令从根部门 1 开始遍历）
- 检查参数名：`department_id`（正确）vs `deptid`（错误）

### 41001 - access_token missing
**原因**：URL 拼接错误，`access_token` 未正确附加。  
**解决**：检查 `_api_call` 函数中 URL 拼接逻辑，确保 `?` 和 `&` 使用正确：
- 无 query params：`/path?access_token=xxx`
- 有 query params：`/path?param=val&access_token=xxx`

### 配置文件路径错误
**原因**：`WORKSPACE_DIR` 计算错误，导致找不到 `config.json`。  
**解决**：脚本在 `scripts/` 子目录时，需向上 3 级才能到 workspace 根：
```bash
# 正确（scripts/ 子目录）
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 错误（只向上 1 级）
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
```

### PROXY_URL 未生效
**原因**：`load_config()` 未被调用，`PROXY_URL` 变量为空。  
**解决**：在 `_api_call` 函数开头显式调用 `load_config`：
```bash
if [[ -z "$PROXY_URL" ]]; then
    load_config
fi
```

## 参考文档

详细接口说明请参阅 `references/README.md`。
