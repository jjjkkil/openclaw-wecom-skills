#!/bin/bash

# 分享和文档管理脚本
# 用法: ./share-sheet.sh <命令> [参数]

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
    
    local response=$(curl -s --connect-timeout 10 -m 30 \
        -x "$PROXY_URL" \
        "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}")
    
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
分享和文档管理

用法: $0 <命令> [选项]

命令:
  rename            重命名文档
  delete, del       删除文档
  info              获取文档信息
  share-url         获取分享链接
  auth              获取文档权限信息

选项:
  --docid           文档 ID（必填）
  --new_name        新名称（rename 命令必填）
  --help, -h        显示帮助

示例:
  # 重命名文档
  $0 rename --docid "DOCID" --new_name "新名称"
  
  # 删除文档
  $0 delete --docid "DOCID"
  
  # 获取文档信息
  $0 info --docid "DOCID"
  
  # 获取分享链接
  $0 share-url --docid "DOCID"
  
  # 获取权限信息
  $0 auth --docid "DOCID"

EOF
}

# 重命名文档
rename_doc() {
    local docid=""
    local new_name=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docid)
                docid="$2"
                shift 2
                ;;
            --new_name)
                new_name="$2"
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
    
    if [ -z "$docid" ] || [ -z "$new_name" ]; then
        echo "错误: 缺少必填参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\",\"new_name\":\"${new_name}\"}"
    
    curl -s --connect-timeout 10 -m 30 \
        -x "$PROXY_URL" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://qyapi.weixin.qq.com/cgi-bin/wedoc/rename_doc?access_token=${access_token}"
}

# 删除文档
delete_doc() {
    local docid=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docid)
                docid="$2"
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
    
    if [ -z "$docid" ]; then
        echo "错误: 缺少 --docid 参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\"}"
    
    curl -s --connect-timeout 10 -m 30 \
        -x "$PROXY_URL" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://qyapi.weixin.qq.com/cgi-bin/wedoc/del_doc?access_token=${access_token}"
}

# 获取文档信息
get_doc_info() {
    local docid=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docid)
                docid="$2"
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
    
    if [ -z "$docid" ]; then
        echo "错误: 缺少 --docid 参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\"}"
    
    curl -s --connect-timeout 10 -m 30 \
        -x "$PROXY_URL" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://qyapi.weixin.qq.com/cgi-bin/wedoc/get_doc_base_info?access_token=${access_token}"
}

# 获取分享链接
get_share_url() {
    local docid=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docid)
                docid="$2"
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
    
    if [ -z "$docid" ]; then
        echo "错误: 缺少 --docid 参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\"}"
    
    curl -s --connect-timeout 10 -m 30 \
        -x "$PROXY_URL" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://qyapi.weixin.qq.com/cgi-bin/wedoc/get_doc_share_url?access_token=${access_token}"
}

# 获取文档权限
get_doc_auth() {
    local docid=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docid)
                docid="$2"
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
    
    if [ -z "$docid" ]; then
        echo "错误: 缺少 --docid 参数"
        exit 1
    fi
    
    local access_token=$(get_access_token)
    
    local body="{\"docid\":\"${docid}\"}"
    
    curl -s --connect-timeout 10 -m 30 \
        -x "$PROXY_URL" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://qyapi.weixin.qq.com/cgi-bin/wedoc/get_doc_auth?access_token=${access_token}"
}

# 主入口
case "$1" in
    rename)
        shift
        rename_doc "$@"
        ;;
    delete|del)
        shift
        delete_doc "$@"
        ;;
    info)
        shift
        get_doc_info "$@"
        ;;
    share-url)
        shift
        get_share_url "$@"
        ;;
    auth)
        shift
        get_doc_auth "$@"
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
