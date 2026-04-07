#!/bin/bash

# 视图管理脚本
# 用法: ./manage-view.sh <命令> [参数]

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
视图管理

用法: $0 <命令> [选项]

命令:
  add               添加视图
  delete, del       删除视图
  list, ls          查询视图列表

选项:
  --docid           文档 ID（必填）
  --sheet_id        子表 ID（必填）
  --view_id         视图 ID（delete 命令必填）
  --title, -t       视图标题（add 命令必填）
  --type            视图类型（add 命令必填）
  --gantt_start     甘特图开始字段ID（甘特图必填）
  --gantt_end       甘特图结束字段ID（甘特图必填）
  --help, -h        显示帮助

视图类型:
  VIEW_TYPE_GRID      表格视图
  VIEW_TYPE_KANBAN    看板视图
  VIEW_TYPE_GALLERY   画册视图
  VIEW_TYPE_GANTT     甘特视图
  VIEW_TYPE_CALENDAR  日历视图

示例:
  # 添加表格视图
  $0 add --docid "DOCID" --sheet_id "SHEETID" --title "默认视图" --type "VIEW_TYPE_GRID"
  
  # 添加看板视图
  $0 add --docid "DOCID" --sheet_id "SHEETID" --title "预算看板" --type "VIEW_TYPE_KANBAN"
  
  # 添加甘特图
  $0 add --docid "DOCID" --sheet_id "SHEETID" --title "项目甘特图" --type "VIEW_TYPE_GANTT" \
         --gantt_start "FIELD1" --gantt_end "FIELD2"
  
  # 删除视图
  $0 delete --docid "DOCID" --sheet_id "SHEETID" --view_id "VIEWID"
  
  # 查询视图列表
  $0 list --docid "DOCID" --sheet_id "SHEETID"

EOF
}

# 添加视图
add_view() {
    local docid=""
    local sheet_id=""
    local title=""
    local view_type=""
    local gantt_start=""
    local gantt_end=""
    
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
            --title|-t)
                title="$2"
                shift 2
                ;;
            --type)
                view_type="$2"
                shift 2
                ;;
            --gantt_start)
                gantt_start="$2"
                shift 2
                ;;
            --gantt_end)
                gantt_end="$2"
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
    
    if [ -z "$docid" ] || [ -z "$sheet_id" ] || [ -z "$title" ] || [ -z "$view_type" ]; then
        echo "错误: 缺少必填参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\",\"sheet_id\":\"${sheet_id}\",\"view_title\":\"${title}\",\"view_type\":\"${view_type}\"}"
    
    # 甘特图需要额外参数
    if [ "$view_type" == "VIEW_TYPE_GANTT" ] || [ "$view_type" == "VIEW_TYPE_CALENDAR" ]; then
        if [ -z "$gantt_start" ] || [ -z "$gantt_end" ]; then
            echo "错误: 甘特图/日历视图需要 --gantt_start 和 --gantt_end 参数"
            exit 1
        fi
        
        if [ "$view_type" == "VIEW_TYPE_GANTT" ]; then
            body=$(echo "$body" | sed "s/}$/,\"property_gantt\":{\"start_date_field_id\":\"${gantt_start}\",\"end_date_field_id\":\"${gantt_end}\"}}/")
        else
            body=$(echo "$body" | sed "s/}$/,\"property_calendar\":{\"start_date_field_id\":\"${gantt_start}\",\"end_date_field_id\":\"${gantt_end}\"}}/")
        fi
    fi
    
    local response
    if [[ -n "$PROXY_ARG" ]]; then
        response=$(curl -s --connect-timeout 10 -m 30 $PROXY_ARG \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/add_view?access_token=${access_token}")
    else
        response=$(curl -s --connect-timeout 10 -m 30 \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/add_view?access_token=${access_token}")
    fi
    echo "$response"
}

# 删除视图
delete_view() {
    local docid=""
    local sheet_id=""
    local view_id=""
    
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
    
    if [ -z "$docid" ] || [ -z "$sheet_id" ] || [ -z "$view_id" ]; then
        echo "错误: 缺少必填参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\",\"sheet_id\":\"${sheet_id}\",\"view_id\":\"${view_id}\"}"
    
    local response
    if [[ -n "$PROXY_ARG" ]]; then
        response=$(curl -s --connect-timeout 10 -m 30 $PROXY_ARG \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/del_view?access_token=${access_token}")
    else
        response=$(curl -s --connect-timeout 10 -m 30 \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/del_view?access_token=${access_token}")
    fi
    echo "$response"
}

# 查询视图列表
list_views() {
    local docid=""
    local sheet_id=""
    local offset=0
    local limit=100
    
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
            --offset)
                offset="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
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
    
    local response
    if [[ -n "$PROXY_ARG" ]]; then
        response=$(curl -s --connect-timeout 10 -m 30 $PROXY_ARG \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/get_views?access_token=${access_token}")
    else
        response=$(curl -s --connect-timeout 10 -m 30 \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://qyapi.weixin.qq.com/cgi-bin/wedoc/smartsheet/get_views?access_token=${access_token}")
    fi
    echo "$response"
}

# 主入口
case "$1" in
    add)
        shift
        add_view "$@"
        ;;
    delete|del)
        shift
        delete_view "$@"
        ;;
    list|ls)
        shift
        list_views "$@"
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
