#!/bin/bash

# 创建智能表格脚本（增强版）
# 用法: ./create-sheet.sh create [参数]
# 特性: 自动确保发起人包含在管理员中，支持自动获取分享链接

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

# 默认发起人（当前用户）
DEFAULT_CREATOR="${DEFAULT_CREATOR}"

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
创建智能表格（增强版）

用法: $0 create [选项]

选项:
  --name, -n        文档名称（必填）
  --admins, -a      管理员列表，逗号分隔（可选，默认包含发起人）
  --creator, -c     发起人/创建者（可选，默认: ${DEFAULT_CREATOR}）
  --share, -s       创建后自动获取分享链接（可选，默认: true）
  --spaceid         空间 ID（可选）
  --fatherid        父目录 ID（可选）
  --help, -h        显示帮助

特性:
  - 自动确保发起人包含在管理员列表中
  - 创建后可自动获取分享链接
  - 支持通过分享链接邀请其他人协作

示例:
  # 基本用法（发起人自动成为管理员）
  $0 create --name "项目预算表"
  
  # 指定多个管理员（发起人自动追加）
  $0 create -n "客户管理" -a "${USER_X},${USER_Y}"
  
  # 指定不同发起人
  $0 create -n "运营报表" -c "${USER_X}" -a "${USER_Y}"
  
  # 不自动获取分享链接
  $0 create -n "内部文档" --share false

EOF
}

# 获取分享链接
get_share_url() {
    local docid="$1"
    local access_token="$2"
    
    local body="{\"docid\":\"${docid}\"}"
    
    curl -s --connect-timeout 10 -m 30 \
        -x "$PROXY_URL" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://qyapi.weixin.qq.com/cgi-bin/wedoc/get_doc_share_url?access_token=${access_token}"
}

# 创建智能表格
create_sheet() {
    local name=""
    local admins=""
    local creator="$DEFAULT_CREATOR"
    local get_share="true"
    local spaceid=""
    local fatherid=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name|-n)
                name="$2"
                shift 2
                ;;
            --admins|-a)
                admins="$2"
                shift 2
                ;;
            --creator|-c)
                creator="$2"
                shift 2
                ;;
            --share|-s)
                get_share="$2"
                shift 2
                ;;
            --spaceid)
                spaceid="$2"
                shift 2
                ;;
            --fatherid)
                fatherid="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 验证必填参数
    if [ -z "$name" ]; then
        echo "错误: 缺少 --name 参数"
        show_help
        exit 1
    fi
    
    # 确保发起人包含在管理员列表中
    local admin_list="$creator"
    if [ -n "$admins" ]; then
        # 检查发起人是否已在列表中
        if [[ ",${admins}," != *",${creator},"* ]]; then
            admin_list="${creator},${admins}"
        else
            admin_list="$admins"
        fi
    fi
    
    echo "========================================" >&2
    echo "创建智能表格" >&2
    echo "名称: $name" >&2
    echo "发起人: $creator" >&2
    echo "管理员: $admin_list" >&2
    echo "========================================" >&2
    
    # 获取 access_token
    local access_token=$(get_access_token)
    
    # 构建 admin_users 数组
    local admin_array=""
    IFS=',' read -ra ADMIN_ARR <<< "$admin_list"
    for admin in "${ADMIN_ARR[@]}"; do
        if [ -n "$admin_array" ]; then
            admin_array="${admin_array},"
        fi
        admin_array="${admin_array}\"${admin}\""
    done
    
    # 构建请求体
    local body="{\"doc_type\":10,\"doc_name\":\"${name}\",\"admin_users\":[${admin_array}]}"
    
    # 可选参数
    if [ -n "$spaceid" ]; then
        body=$(echo "$body" | sed "s/}$/,"spaceid":"${spaceid}"}/")
    fi
    
    if [ -n "$fatherid" ]; then
        body=$(echo "$body" | sed "s/}$/,"fatherid":"${fatherid}"}/")
    fi
    
    # 发送创建请求
    local response=$(curl -s --connect-timeout 10 -m 30 \
        -x "$PROXY_URL" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://qyapi.weixin.qq.com/cgi-bin/wedoc/create_doc?access_token=${access_token}")
    
    # 检查创建结果
    local errcode=$(echo "$response" | grep -o '"errcode":[0-9]*' | cut -d':' -f2)
    
    if [ "$errcode" != "0" ]; then
        echo "$response"
        return 1
    fi
    
    # 提取 docid
    local docid=$(echo "$response" | grep -o '"docid":"[^"]*"' | cut -d'"' -f4)
    
    echo "" >&2
    echo "✅ 智能表格创建成功！" >&2
    echo "文档ID: $docid" >&2
    
    # 自动获取分享链接
    if [ "$get_share" == "true" ] && [ -n "$docid" ]; then
        echo "" >&2
        echo "正在获取分享链接..." >&2
        
        local share_response=$(get_share_url "$docid" "$access_token")
        local share_errcode=$(echo "$share_response" | grep -o '"errcode":[0-9]*' | cut -d':' -f2)
        
        if [ "$share_errcode" == "0" ]; then
            local share_url=$(echo "$share_response" | grep -o '"share_url":"[^"]*"' | cut -d'"' -f4)
            echo "" >&2
            echo "📎 分享链接: $share_url" >&2
            echo "" >&2
            echo "💡 提示: 发起人 ($creator) 已自动添加为管理员，可以在「文档」中查看此表格" >&2
            echo "💡 提示: 可以将分享链接发送给其他人进行协作" >&2
            
            # 返回包含分享链接的完整响应
            echo "$response" | sed "s/}$/,\"share_url\":\"${share_url}\"}/"
        else
            echo "⚠️ 获取分享链接失败: $share_response" >&2
            echo "$response"
        fi
    else
        echo "$response"
    fi
}

# 主入口
case "$1" in
    create)
        shift
        create_sheet "$@"
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
