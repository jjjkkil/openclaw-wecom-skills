#!/bin/bash

# 记录管理脚本
# 用法: ./manage-record.sh <命令> [参数]

set -e

# 配置信息 - 从 workspace/config.json 读取
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../../../" && pwd)"
CONFIG_FILE="$WORKSPACE_DIR/config.json"

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
PROXY_ARG=""
if [[ -n "$PROXY_URL" ]]; then
    PROXY_ARG="-x $PROXY_URL"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚠️  警告: 未找到配置文件 $CONFIG_FILE，使用默认配置" >&2
fi

TOKEN_FILE="/tmp/wecom_access_token.json"
TOKEN_EXPIRY=7200

# 获取 access_token
get_access_token() {
    local current_time=$(date +%s)
    
    if [ -f "$TOKEN_FILE" ]; then
        local cached_time=$(stat -c %Y "$TOKEN_FILE" 2>/dev/null || stat -f %m "$TOKEN_FILE" 2>/dev/null)
        local age=$((current_time - cached_time))
        
        if [ $age -lt $TOKEN_EXPIRY ]; then
            local token=$(cat "$TOKEN_FILE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
            if [ -n "$token" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi
    
    local response
    if [[ -n "$PROXY_ARG" ]]; then
        response=$(curl -s --connect-timeout 10 -m 30 $PROXY_ARG \
            "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}")
    else
        response=$(curl -s --connect-timeout 10 -m 30 \
            "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}")
    fi
    
    local errcode=$(echo "$response" | grep -o '"errcode":[0-9]*' | cut -d':' -f2)
    
    if [ "$errcode" != "0" ]; then
        echo "获取 access_token 失败: $response" >&2
        exit 1
    fi
    
    echo "$response" > "$TOKEN_FILE"
    echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4
}

# 显示帮助
show_help() {
    cat << EOF
记录管理

用法: $0 <命令> [选项]

命令:
  add               添加记录
  delete, del       删除记录
  update, upd       更新记录
  list, ls          查询记录

选项:
  --docid           文档 ID（必填）
  --sheet_id        子表 ID（必填）
  --view_id         视图 ID（list 命令可选）
  --record_ids      记录 ID 列表，逗号分隔（delete 命令必填）
  --records         记录数据 JSON（add/update 命令必填）
  --key_type        键类型: CELL_VALUE_KEY_TYPE_FIELD_TITLE(默认) 或 CELL_VALUE_KEY_TYPE_FIELD_ID
  --offset          偏移量（list 命令可选，默认0）
  --limit           分页大小（list 命令可选，默认100）
  --filter          筛选条件 JSON（list 命令可选）
  --help, -h        显示帮助

示例:
  # 添加记录
  $0 add --docid "DOCID" --sheet_id "SHEETID" --records '[
    {
      "values": {
        "类别": [{"type": "text", "text": "研究经费"}],
        "金额": [{"type": "text", "text": "65"}]
      }
    }
  ]'
  
  # 删除记录
  $0 delete --docid "DOCID" --sheet_id "SHEETID" --record_ids "record1,record2"
  
  # 更新记录
  $0 update --docid "DOCID" --sheet_id "SHEETID" --records '[
    {
      "record_id": "RECORD_ID",
      "values": {
        "类别": [{"type": "text", "text": "新类别"}]
      }
    }
  ]'
  
  # 查询记录
  $0 list --docid "DOCID" --sheet_id "SHEETID" --limit 50

EOF
}

# 添加记录
add_records() {
    local docid=""
    local sheet_id=""
    local records=""
    local key_type="CELL_VALUE_KEY_TYPE_FIELD_TITLE"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docid)
                docid="$2"
                shift 2
                ;;
            --sheet_id)
                sheet_id="$2"
                shift 2
                ;;
            --records)
                records="$2"
                shift 2
                ;;
            --key_type)
                key_type="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    if [ -z "$docid" ] || [ -z "$sheet_id" ] || [ -z "$records" ]; then
        echo "错误: 缺少必填参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\",\"sheet_id\":\"${sheet_id}\",\"key_type\":\"${key_type}\",\"records\":${records}}"
    
    local response
    if [[ -n "$PROXY_ARG" ]]; then
        response=$(curl -s --connect-timeout 10 -m 30 $PROXY_ARG \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/add_records?access_token=${access_token}")
    else
        response=$(curl -s --connect-timeout 10 -m 30 \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/add_records?access_token=${access_token}")
    fi
    echo "$response"
}

# 删除记录
delete_records() {
    local docid=""
    local sheet_id=""
    local record_ids=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docid)
                docid="$2"
                shift 2
                ;;
            --sheet_id)
                sheet_id="$2"
                shift 2
                ;;
            --record_ids)
                record_ids="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    if [ -z "$docid" ] || [ -z "$sheet_id" ] || [ -z "$record_ids" ]; then
        echo "错误: 缺少必填参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    # 构建 record_ids 数组
    local id_array=""
    IFS=',' read -ra ID_LIST <<< "$record_ids"
    for id in "${ID_LIST[@]}"; do
        if [ -n "$id_array" ]; then
            id_array="${id_array},"
        fi
        id_array="${id_array}\"${id}\""
    done
    
    local body="{\"docid\":\"${docid}\",\"sheet_id\":\"${sheet_id}\",\"record_ids\":[${id_array}]}"
    
    local response
    if [[ -n "$PROXY_ARG" ]]; then
        response=$(curl -s --connect-timeout 10 -m 30 $PROXY_ARG \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/del_records?access_token=${access_token}")
    else
        response=$(curl -s --connect-timeout 10 -m 30 \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/del_records?access_token=${access_token}")
    fi
    echo "$response"
}

# 更新记录
update_records() {
    local docid=""
    local sheet_id=""
    local records=""
    local key_type="CELL_VALUE_KEY_TYPE_FIELD_TITLE"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docid)
                docid="$2"
                shift 2
                ;;
            --sheet_id)
                sheet_id="$2"
                shift 2
                ;;
            --records)
                records="$2"
                shift 2
                ;;
            --key_type)
                key_type="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    if [ -z "$docid" ] || [ -z "$sheet_id" ] || [ -z "$records" ]; then
        echo "错误: 缺少必填参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\",\"sheet_id\":\"${sheet_id}\",\"key_type\":\"${key_type}\",\"records\":${records}}"
    
    local response
    if [[ -n "$PROXY_ARG" ]]; then
        response=$(curl -s --connect-timeout 10 -m 30 $PROXY_ARG \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/update_records?access_token=${access_token}")
    else
        response=$(curl -s --connect-timeout 10 -m 30 \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/update_records?access_token=${access_token}")
    fi
    echo "$response"
}

# 查询记录
list_records() {
    local docid=""
    local sheet_id=""
    local view_id=""
    local offset=0
    local limit=100
    local filter=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docid)
                docid="$2"
                shift 2
                ;;
            --sheet_id)
                sheet_id="$2"
                shift 2
                ;;
            --view_id)
                view_id="$2"
                shift 2
                ;;
            --offset)
                offset="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --filter)
                filter="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    if [ -z "$docid" ] || [ -z "$sheet_id" ]; then
        echo "错误: 缺少必填参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\",\"sheet_id\":\"${sheet_id}\",\"offset\":${offset},\"limit\":${limit}}"
    
    if [ -n "$view_id" ]; then
        body=$(echo "$body" | sed "s/}$/,\"view_id\":\"${view_id}\"}/")
    fi
    
    if [ -n "$filter" ]; then
        body=$(echo "$body" | sed "s/}$/,\"filter\":${filter}}/")
    fi
    
    local response
    if [[ -n "$PROXY_ARG" ]]; then
        response=$(curl -s --connect-timeout 10 -m 30 $PROXY_ARG \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/get_records?access_token=${access_token}")
    else
        response=$(curl -s --connect-timeout 10 -m 30 \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/get_records?access_token=${access_token}")
    fi
    echo "$response"
}

# 主入口
case "$1" in
    add)
        shift
        add_records "$@"
        ;;
    delete|del)
        shift
        delete_records "$@"
        ;;
    update|upd)
        shift
        update_records "$@"
        ;;
    list|ls)
        shift
        list_records "$@"
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
