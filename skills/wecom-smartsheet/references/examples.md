# 完整示例

## 创建项目预算表

```bash
#!/bin/bash

# 1. 创建智能表格
echo "创建智能表格..."
# 注意：--admins 参数可选，发起人会自动添加到管理员列表
RESULT=$(./scripts/create-sheet.sh create \
  --name "项目预算管理")

DOCID=$(echo $RESULT | jq -r '.docid')
SHARE_URL=$(echo $RESULT | jq -r '.share_url')
echo "文档ID: $DOCID"
echo "分享链接: $SHARE_URL"

# 2. 添加子表
echo "添加子表..."
SHEET_RESULT=$(./scripts/manage-sheet.sh add \
  --docid "$DOCID" \
  --title "2024年项目预算")

SHEET_ID=$(echo $SHEET_RESULT | jq -r '.properties.sheet_id')
echo "子表ID: $SHEET_ID"

# 3. 添加字段
echo "添加字段..."
./scripts/manage-field.sh add \
  --docid "$DOCID" \
  --sheet_id "$SHEET_ID" \
  --fields '[
    {"field_title": "类别", "field_type": "FIELD_TYPE_TEXT"},
    {"field_title": "具体描述", "field_type": "FIELD_TYPE_TEXT"},
    {"field_title": "金额(万)", "field_type": "FIELD_TYPE_NUMBER"},
    {"field_title": "状态", "field_type": "FIELD_TYPE_SINGLE_SELECT", "property_single_select": {"options": [{"text": "已批准", "color": "#00FF00"}, {"text": "待审批", "color": "#FFA500"}, {"text": "已拒绝", "color": "#FF0000"}]}},
    {"field_title": "负责人", "field_type": "FIELD_TYPE_USER"},
    {"field_title": "完成日期", "field_type": "FIELD_TYPE_DATE_TIME"}
  ]'

# 4. 添加记录
echo "添加记录..."
./scripts/manage-record.sh add \
  --docid "$DOCID" \
  --sheet_id "$SHEET_ID" \
  --records '[
    {
      "values": {
        "类别": [{"type": "text", "text": "研究经费"}],
        "具体描述": [{"type": "text", "text": "向申请本项目项下课题的研究者拨付研究经费"}],
        "金额(万)": [{"type": "text", "text": "65"}],
        "状态": [{"text": "已批准"}]
      }
    },
    {
      "values": {
        "类别": [{"type": "text", "text": "服务费"}],
        "具体描述": [{"type": "text", "text": "乙方组织实施本项目的其他必要支出"}],
        "金额(万)": [{"type": "text", "text": "30"}],
        "状态": [{"text": "已批准"}]
      }
    },
    {
      "values": {
        "类别": [{"type": "text", "text": "管理费、税费"}],
        "具体描述": [{"type": "text", "text": "15%管理费，7.2%税费"}],
        "金额(万)": [{"type": "text", "text": "22"}],
        "状态": [{"text": "已批准"}]
      }
    }
  ]'

# 5. 添加看板视图
echo "添加看板视图..."
./scripts/manage-view.sh add \
  --docid "$DOCID" \
  --sheet_id "$SHEET_ID" \
  --title "预算看板" \
  --type "VIEW_TYPE_KANBAN"

# 6. 获取分享链接
echo "获取分享链接..."
./scripts/share-sheet.sh get-url \
  --docid "$DOCID"

echo "完成！"
```

## Python 完整示例

```python
#!/usr/bin/env python3
import sys
import json
import os
sys.path.insert(0, 'skills/wecom-smartsheet/scripts')  # 相对于 workspace 目录

from smartsheet_client import SmartsheetClient

# 获取 corpSecret
config_path = os.path.expanduser("~/.openclaw/openclaw.json")
with open(config_path, 'r') as f:
    config = json.load(f)
corp_secret = config.get('channels', {}).get('wecom', {}).get('accounts', {}).get('business', {}).get('agent', {}).get('agentSecret') or config.get('channels', {}).get('wecom', {}).get('accounts', {}).get('business', {}).get('agent', {}).get('corpSecret', '')

# 初始化
client = SmartsheetClient(
    corpid="${CORP_ID}",
    corpsecret=corp_secret,
    proxy_url="${PROXY_URL}"
)

# 创建表格
doc = client._request("POST", "/wedoc/create_doc", {
    "doc_type": 10,
    "doc_name": "会议管理",
    "admin_users": ["${CREATOR_USERID}"]
})
docid = doc["docid"]

# 添加子表
sheet = client.add_sheet(docid, title="会议议程")
sheet_id = sheet["properties"]["sheet_id"]

# 添加字段
client.add_fields(docid, sheet_id, [
    {"field_title": "时间", "field_type": "FIELD_TYPE_TEXT"},
    {"field_title": "内容", "field_type": "FIELD_TYPE_TEXT"},
    {"field_title": "主讲人", "field_type": "FIELD_TYPE_TEXT"}
])

# 添加数据
client.add_records(docid, sheet_id, [
    {"values": {
        "时间": [{"type": "text", "text": "09:00"}],
        "内容": [{"type": "text", "text": "开场致辞"}],
        "主讲人": [{"type": "text", "text": "${USER_X}"}]
    }}
])

print(f"✅ 创建成功！文档ID: {docid}")
```
