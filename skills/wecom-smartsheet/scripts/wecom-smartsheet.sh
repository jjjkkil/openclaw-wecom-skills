#!/bin/bash

# 企业微信智能表格管理 - 统一入口脚本
# 用法: ./wecom-smartsheet.sh <命令> [参数]

set -e

# 配置信息 - 从 workspace/config.json 读取
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${WORKSPACE_DIR:-"$(cd "$SCRIPT_DIR/.." && pwd)"}"
CONFIG_FILE="$WORKSPACE_DIR/config.json"
TOKEN_SCRIPT="$WORKSPACE_DIR/skills/wecom-token.sh"

# 如果 config.json 存在则读取，否则使用默认值
if [ -f "$CONFIG_FILE" ]; then
    # 优先使用 jq，如果没有则使用 grep 回退
    if command -v jq >/dev/null 2>&1; then
        CORP_ID=$(jq -r '.wecom.corp_id // empty' "$CONFIG_FILE")
        CORP_SECRET=$(jq -r '.wecom.corp_secret // empty' "$CONFIG_FILE")
        AGENT_ID=$(jq -r '.wecom.agent_id // empty' "$CONFIG_FILE")
        PROXY_URL=$(jq -r '.proxy.url // empty' "$CONFIG_FILE")
    else
        CORP_ID=$(grep -o '"corp_id"[^,]*' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
        CORP_SECRET=$(grep -o '"corp_secret"[^,]*' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
        AGENT_ID=$(grep -o '"agent_id"[^,]*' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
        PROXY_URL=$(grep -o '"url"[^,]*' "$CONFIG_FILE" | tail -1 | cut -d'"' -f4)
    fi
fi

# 如果配置为空，使用默认值
CORP_ID="${CORP_ID}"
CORP_SECRET="${CORP_SECRET}"
AGENT_ID="${AGENT_ID}"
PROXY_URL="${PROXY_URL}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚠️  警告: 未找到配置文件 $CONFIG_FILE，使用默认配置" >&2
fi

# 获取 access_token（统一从 wecom-token.sh 获取）
get_access_token() {
    if [[ -x "$TOKEN_SCRIPT" ]]; then
        "$TOKEN_SCRIPT" get
    else
        # 回退：直接调用接口
        curl -s --proxy "$PROXY_URL" \
            "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}" \
            | jq -r '.access_token // empty'
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
企业微信智能表格管理工具

用法: $0 <命令> [参数]

文档管理:
  create-sheet     创建智能表格
  rename-doc       重命名文档
  delete-doc       删除文档
  get-doc-info     获取文档信息
  get-share-url    获取分享链接

子表管理:
  add-sheet        添加子表
  delete-sheet     删除子表
  list-sheets      查询子表列表

视图管理:
  add-view         添加视图
  delete-view      删除视图
  list-views       查询视图列表

字段管理:
  add-fields       添加字段
  delete-fields    删除字段
  list-fields      查询字段列表

记录管理:
  add-records      添加记录
  delete-records   删除记录
  update-records   更新记录
  list-records     查询记录

使用 '$0 <命令> --help' 查看具体命令的用法

示例:
  $0 create-sheet --name "项目预算表" --admins "${USER_X}"
  $0 list-sheets --docid "DOCID"
  $0 add-records --docid "DOCID" --sheet_id "SHEETID" --records '[...]'

EOF
}

# 主入口
case "$1" in
    create-sheet)
        shift
        exec "$(dirname "$0")/create-sheet.sh" "$@"
        ;;
    rename-doc|delete-doc|get-doc-info|get-share-url)
        shift
        exec "$(dirname "$0")/share-sheet.sh" "$1" "$@"
        ;;
    add-sheet|delete-sheet|list-sheets)
        shift
        exec "$(dirname "$0")/manage-sheet.sh" "$1" "$@"
        ;;
    add-view|delete-view|list-views)
        shift
        exec "$(dirname "$0")/manage-view.sh" "$1" "$@"
        ;;
    add-fields|delete-fields|list-fields)
        shift
        exec "$(dirname "$0")/manage-field.sh" "$1" "$@"
        ;;
    add-records|delete-records|update-records|list-records)
        shift
        exec "$(dirname "$0")/manage-record.sh" "$1" "$@"
        ;;
    --help|-h|help)
        show_help
        exit 0
        ;;
    *)
        echo "未知命令: $1"
        show_help
        exit 1
        ;;
esac
