# 详细接口说明

## 一、文档管理接口

### 1. 创建智能表格

**重要**: 脚本会自动确保发起人包含在管理员列表中。

**接口**: `POST /wedoc/create_doc`

```bash
# 基本用法（发起人自动成为管理员）
./scripts/create-sheet.sh create \
  --name "表格名称"

# 指定多个管理员（发起人自动追加）
./scripts/create-sheet.sh create \
  --name "表格名称" \
  --admins "user1,user2"

# 指定不同发起人
./scripts/create-sheet.sh create \
  --name "表格名称" \
  --creator "${USER_X}" \
  --admins "${USER_Y}"
```

**参数说明**:
- `doc_type`: 10 (固定值，表示智能表格)
- `doc_name`: 文档名称（必填）
- `admin_users`: 管理员列表（必填，脚本会自动添加发起人）
- `spaceid`: 空间 ID（可选）
- `fatherid`: 父目录 ID（可选）

**返回示例**:
```json
{
  "errcode": 0,
  "errmsg": "ok",
  "docid": "${DOC_ID}",
  "url": "https://doc.weixin.qq.com/...",
  "share_url": "https://doc.weixin.qq.com/s/..."
}
```

### 2. 重命名文档

**接口**: `POST /wedoc/rename_doc`

```bash
./scripts/share-sheet.sh rename \
  --docid "DOCID" \
  --new_name "新名称"
```

### 3. 删除文档

**接口**: `POST /wedoc/del_doc`

```bash
./scripts/share-sheet.sh delete \
  --docid "DOCID"
```

### 4. 获取分享链接

**接口**: `POST /wedoc/get_doc_share_url`

```bash
./scripts/share-sheet.sh get-url \
  --docid "DOCID"
```

## 二、子表管理接口

### 1. 添加子表

**接口**: `POST /smartsheet/add_sheet`

```bash
./scripts/manage-sheet.sh add \
  --docid "DOCID" \
  --title "子表标题" \
  --index 0
```

**参数说明**:
- `docid`: 文档 ID（必填）
- `title`: 子表标题（可选，默认"智能表"）
- `index`: 插入位置（可选）

**返回示例**:
```json
{
  "errcode": 0,
  "errmsg": "ok",
  "properties": {
    "sheet_id": "${SHEET_ID}",
    "title": "子表标题",
    "index": 0
  }
}
```

### 2. 删除子表

**接口**: `POST /smartsheet/del_sheet`

```bash
./scripts/manage-sheet.sh delete \
  --docid "DOCID" \
  --sheet_id "SHEETID"
```

### 3. 查询子表列表

**接口**: `POST /smartsheet/get_sheets`

```bash
./scripts/manage-sheet.sh list \
  --docid "DOCID"
```

## 三、视图管理接口

### 1. 添加视图

**接口**: `POST /smartsheet/add_view`

```bash
./scripts/manage-view.sh add \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --title "视图标题" \
  --type "VIEW_TYPE_GRID"
```

**视图类型**:
- `VIEW_TYPE_GRID`: 表格视图
- `VIEW_TYPE_KANBAN`: 看板视图
- `VIEW_TYPE_GALLERY`: 画册视图
- `VIEW_TYPE_GANTT`: 甘特视图
- `VIEW_TYPE_CALENDAR`: 日历视图

**甘特视图额外参数**:
```bash
./scripts/manage-view.sh add \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --title "甘特图" \
  --type "VIEW_TYPE_GANTT" \
  --gantt_start_field "开始日期字段ID" \
  --gantt_end_field "结束日期字段ID"
```

### 2. 删除视图

**接口**: `POST /smartsheet/del_view`

```bash
./scripts/manage-view.sh delete \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --view_id "VIEWID"
```

### 3. 查询视图列表

**接口**: `POST /smartsheet/get_views`

```bash
./scripts/manage-view.sh list \
  --docid "DOCID" \
  --sheet_id "SHEETID"
```

## 四、字段管理接口

### 1. 添加字段

**接口**: `POST /smartsheet/add_fields`

```bash
./scripts/manage-field.sh add \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --fields '[
    {"field_title": "文本字段", "field_type": "FIELD_TYPE_TEXT"},
    {"field_title": "数字字段", "field_type": "FIELD_TYPE_NUMBER"},
    {"field_title": "日期字段", "field_type": "FIELD_TYPE_DATE_TIME"}
  ]'
```

**字段类型列表**:

| 字段类型 | 说明 | 额外属性 |
|---------|------|----------|
| `FIELD_TYPE_TEXT` | 文本 | - |
| `FIELD_TYPE_NUMBER` | 数字 | `property_number` |
| `FIELD_TYPE_CHECKBOX` | 复选框 | `property_checkbox` |
| `FIELD_TYPE_DATE_TIME` | 日期时间 | `property_date_time` |
| `FIELD_TYPE_IMAGE` | 图片 | `property_image` |
| `FIELD_TYPE_ATTACHMENT` | 附件 | `property_attachment` |
| `FIELD_TYPE_USER` | 成员 | `property_user` |
| `FIELD_TYPE_URL` | 链接 | `property_url` |
| `FIELD_TYPE_SELECT` | 多选 | `property_select` |
| `FIELD_TYPE_SINGLE_SELECT` | 单选 | `property_single_select` |
| `FIELD_TYPE_PROGRESS` | 进度 | `property_progress` |
| `FIELD_TYPE_PHONE_NUMBER` | 电话 | - |
| `FIELD_TYPE_EMAIL` | 邮箱 | - |
| `FIELD_TYPE_LOCATION` | 地理位置 | `property_location` |
| `FIELD_TYPE_CURRENCY` | 货币 | `property_currency` |
| `FIELD_TYPE_PERCENTAGE` | 百分数 | `property_percentage` |
| `FIELD_TYPE_BARCODE` | 条码 | - |

**带属性的字段示例**:
```bash
./scripts/manage-field.sh add \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --fields '[
    {
      "field_title": "优先级",
      "field_type": "FIELD_TYPE_SINGLE_SELECT",
      "property_single_select": {
        "options": [
          {"text": "高", "color": "#FF0000"},
          {"text": "中", "color": "#FFA500"},
          {"text": "低", "color": "#00FF00"}
        ]
      }
    }
  ]'
```

### 2. 删除字段

**接口**: `POST /smartsheet/del_fields`

```bash
./scripts/manage-field.sh delete \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --field_ids "field1,field2"
```

### 3. 查询字段列表

**接口**: `POST /smartsheet/get_fields`

```bash
./scripts/manage-field.sh list \
  --docid "DOCID" \
  --sheet_id "SHEETID"
```

## 五、记录管理接口

### 1. 添加记录

**接口**: `POST /smartsheet/add_records`

```bash
./scripts/manage-record.sh add \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --key_type "CELL_VALUE_KEY_TYPE_FIELD_TITLE" \
  --records '[
    {
      "values": {
        "文本字段": [{"type": "text", "text": "内容"}],
        "数字字段": [{"type": "text", "text": "100"}],
        "日期字段": [{"type": "text", "text": "1704067200000"}]
      }
    }
  ]'
```

**单元格值类型**:

| 字段类型 | 值格式 |
|---------|--------|
| 文本 | `[{"type": "text", "text": "内容"}]` |
| 数字 | `[{"type": "text", "text": "123.45"}]` |
| 复选框 | `true` / `false` |
| 日期 | `[{"type": "text", "text": "毫秒时间戳"}]` |
| 成员 | `[{"type": "text", "text": "userid"}]` |
| 单选/多选 | `[{"text": "选项1"}, {"text": "选项2"}]` |

**注意**: 不能给创建时间、最后编辑时间、创建人、最后编辑人字段添加记录。

### 2. 删除记录

**接口**: `POST /smartsheet/del_records`

```bash
./scripts/manage-record.sh delete \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --record_ids "record1,record2"
```

### 3. 更新记录

**接口**: `POST /smartsheet/update_records`

```bash
./scripts/manage-record.sh update \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --records '[
    {
      "record_id": "RECORD_ID",
      "values": {
        "字段标题": [{"type": "text", "text": "新内容"}]
      }
    }
  ]'
```

### 4. 查询记录

**接口**: `POST /smartsheet/get_records`

```bash
./scripts/manage-record.sh list \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --view_id "VIEWID" \
  --offset 0 \
  --limit 100
```

**筛选条件** (高级用法):
```bash
./scripts/manage-record.sh list \
  --docid "DOCID" \
  --sheet_id "SHEETID" \
  --filter '{"field_id": "FIELDID", "operator": "EQUAL", "value": "条件值"}'
```
