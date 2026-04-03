---
name: wecom-smartsheet
description: 通过企业微信 API 创建、管理和操作智能表格（Smartsheet）。触发词：创建智能表格、管理子表、管理字段、管理记录、分享表格。
---

# Skill: 企业微信智能表格管理

## 概述

通过企业微信 API 创建、管理和操作智能表格（Smartsheet），支持完整的表格生命周期管理：创建表格、管理子表、配置视图、定义字段、操作记录、分享协作等功能。

## 前置条件

1. **企业微信自建应用已配置**「文档接口权限」并添加到「可调用接口的应用」列表
2. **权限配置**：登录企业微信管理端 → 协作 → 文档 → API → 配置「可调用接口的应用」
3. **环境要求**：企业微信 4.0.20 及以上版本；如服务器 IP 动态变化需配置 HTTP 代理

## ⚠️ 执行注意

**使用 `bash` 执行

```bash
# ✅ 正确
bash skills/wecom-smartsheet/scripts/wecom-smartsheet.sh create --name "表格名称" ...

# ❌ 错误 — 会导致路径计算错误、配置文件找不到
source skills/wecom-smartsheet/scripts/wecom-smartsheet.sh create --name "表格名称" ...
. skills/wecom-smartsheet/scripts/wecom-smartsheet.sh create --name "表格名称" ...
```

原因：脚本使用 `${BASH_SOURCE[0]}` 计算自身路径

## 工具位置

```
skills/wecom-smartsheet/
├── scripts/
│   ├── smartsheet_client.py     # Python API 客户端（推荐）
│   ├── wecom-smartsheet.sh      # 统一入口脚本
│   ├── create-sheet.sh          # 创建智能表格
│   ├── manage-sheet.sh          # 子表管理
│   ├── manage-view.sh           # 视图管理
│   ├── manage-field.sh          # 字段管理
│   ├── manage-record.sh         # 记录管理
│   └── share-sheet.sh           # 分享和权限管理
├── references/                  # 详细文档
└── SKILL.md
```

## 配置信息

从 `~/.openclaw/openclaw.json` 获取 corpSecret:
```bash
cat ~/.openclaw/openclaw.json | jq -r '.channels.wecom.accounts.business.agent.agentSecret // .channels.wecom.accounts.business.agent.corpSecret // empty'
```

## 核心概念

### 智能表格结构层次

```
文档 (Doc)
├── 子表1 (Sheet)
│   ├── 视图1 (View) - 表格视图
│   ├── 视图2 (View) - 看板视图
│   ├── 字段1 (Field) - 文本
│   ├── 字段2 (Field) - 数字
│   └── 记录 (Records)
├── 子表2 (Sheet)
└── ...
```

### 关键 ID 说明

| ID 类型 | 说明 | 示例 |
|---------|------|------|
| docid | 文档唯一标识 | `${DOC_ID}` |
| sheet_id | 子表 ID（6位随机字符串） | `${SHEET_ID}` |
| view_id | 视图 ID | `${VIEW_ID}` |
| field_id | 字段 ID | `fABC123` |
| record_id | 记录 ID | `rXYZ789` |

**重要**: docid 仅在创建时返回，需要妥善保存！

## 快速开始

### Python 客户端

```python
from smartsheet_client import SmartsheetClient

client = SmartsheetClient(corpid="${CORP_ID}", corpsecret="your_secret", proxy_url="${PROXY_URL}")

# 创建文档 → 添加子表 → 添加字段 → 添加记录
doc = client._request("POST", "/wedoc/create_doc", {"doc_type": 10, "doc_name": "项目预算表", "admin_users": []})
docid = doc["docid"]
sheet = client.add_sheet(docid, title="2024年预算")
client.add_fields(docid, sheet["properties"]["sheet_id"], [{"field_title": "类别", "field_type": "FIELD_TYPE_TEXT"}])
client.add_records(docid, sheet["properties"]["sheet_id"], [{"values": {"类别": [{"type": "text", "text": "研究经费"}]}}])
```

### Shell 脚本

```bash
# 创建表格
RESULT=$(bash skills/wecom-smartsheet/scripts/create-sheet.sh create --name "项目预算表")
DOCID=$(echo $RESULT | jq -r '.docid')

# 添加子表
SHEET_ID=$(bash skills/wecom-smartsheet/scripts/manage-sheet.sh add --docid "$DOCID" --title "2024年预算" | jq -r '.properties.sheet_id')

# 添加字段和记录
bash skills/wecom-smartsheet/scripts/manage-field.sh add --docid "$DOCID" --sheet_id "$SHEET_ID" --fields '[{"field_title": "类别", "field_type": "FIELD_TYPE_TEXT"}]'
bash skills/wecom-smartsheet/scripts/manage-record.sh add --docid "$DOCID" --sheet_id "$SHEET_ID" --records '[{"values": {"类别": [{"type": "text", "text": "研究经费"}]}}]'
```

## 可见性与分享机制

- **发起人自动成为管理员**：创建时自动添加到 admin_users，无需手动指定
- **分享链接**：创建后自动获取 share_url，可通过 `bash skills/wecom-smartsheet/scripts/share-sheet.sh get-url` 获取
- **权限角色**：管理员（查看、编辑、修改设置）vs 分享链接访问者（根据链接权限）
- **查看位置**：只有管理员能在「文档」应用中看到表格；其他人通过分享链接访问
- **调整权限**：可通过企业微信客户端随时调整分享权限

## 完整功能列表

| 命令 | 功能 | 脚本 |
|------|------|------|
| `create` | 创建智能表格 | `create-sheet.sh` |
| `sheet-add/del/update/list` | 子表管理 | `manage-sheet.sh` |
| `view-add/del/update/list` | 视图管理 | `manage-view.sh` |
| `field-add/del/update/list` | 字段管理 | `manage-field.sh` |
| `record-add/del/update/list` | 记录管理 | `manage-record.sh` |
| `share-url/auth` | 分享和权限 | `share-sheet.sh` |

详细API文档见 [references/api.md](references/api.md)，示例见 [references/examples.md](references/examples.md)。
