#!/bin/bash

# 企业微信通讯录读取脚本
# 支持：读取单个成员、批量读取、按部门读取成员列表

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${WORKSPACE_DIR:-"$(cd "$SCRIPT_DIR/../../.." && pwd)"}"
CONFIG_FILE="$WORKSPACE_DIR/config.json"
TOKEN_SCRIPT="$WORKSPACE_DIR/skills/wecom-token.sh"

# 读取配置
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "错误: 配置文件不存在: $CONFIG_FILE" >&2
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "错误: 需要 jq 工具，请先安装: brew install jq" >&2
        exit 1
    fi

    CORP_ID=$(jq -r '.wecom.corp_id // empty' "$CONFIG_FILE")
    CORP_SECRET=$(jq -r '.wecom.corp_secret // empty' "$CONFIG_FILE")
    PROXY_URL=$(jq -r '.proxy.url // empty' "$CONFIG_FILE")

    if [[ -z "$CORP_ID" ]] || [[ -z "$CORP_SECRET" ]]; then
        echo "错误: config.json 中缺少 wecom.corp_id 或 wecom.corp_secret" >&2
        exit 1
    fi
}

# 获取 access_token
get_access_token() {
    if [[ -x "$TOKEN_SCRIPT" ]]; then
        "$TOKEN_SCRIPT" get
    else
        load_config
        curl -s --proxy "$PROXY_URL" \
            "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}" \
            | jq -r '.access_token // empty'
    fi
}

# 检查 token 过期并重试
check_and_retry() {
    local response="$1"
    local errcode
    errcode=$(echo "$response" | jq -r '.errcode // -1' 2>/dev/null || echo "-1")
    case "$errcode" in
        40014|42001|42002) return 0 ;;
        *) return 1 ;;
    esac
}

# API 调用封装
_api_call() {
    local method="$1"
    local path="$2"
    local json_body="${3:-}"
    local token
    token=$(get_access_token)
    
    # 确保配置已加载（PROXY_URL 等）
    if [[ -z "$PROXY_URL" ]]; then
        load_config
    fi
    
    # 如果 path 已带 ? query params，用 & 拼接 access_token
    local separator="?"
    if [[ "$path" == *"?"* ]]; then
        separator="&"
    fi
    local url="https://qyapi.weixin.qq.com${path}${separator}access_token=${token}"

    local response
    if [[ -n "$json_body" ]]; then
        response=$(curl -s --proxy "$PROXY_URL" -X "$method" \
            -H "Content-Type: application/json" \
            -d "$json_body" "$url")
    else
        response=$(curl -s --proxy "$PROXY_URL" -X "$method" "$url")
    fi

    if check_and_retry "$response"; then
        [[ -x "$TOKEN_SCRIPT" ]] && "$TOKEN_SCRIPT" force-refresh >/dev/null 2>&1
        token=$(get_access_token)
        url="https://qyapi.weixin.qq.com${path}${separator}access_token=${token}"
        if [[ -n "$json_body" ]]; then
            response=$(curl -s --proxy "$PROXY_URL" -X "$method" \
                -H "Content-Type: application/json" \
                -d "$json_body" "$url")
        else
            response=$(curl -s --proxy "$PROXY_URL" -X "$method" "$url")
        fi
    fi

    echo "$response"
}

# 读取单个成员
cmd_get() {
    local userid="$1"
    if [[ -z "$userid" ]]; then
        echo "错误: 缺少 userid 参数" >&2
        echo "用法: $0 get <userid>" >&2
        exit 1
    fi

    echo "👤 读取成员: $userid" >&2
    _api_call "GET" "/cgi-bin/user/get?userid=${userid}"
}

# 批量读取成员
cmd_batch() {
    local userids="$1"
    if [[ -z "$userids" ]]; then
        echo "错误: 缺少 userid 列表参数" >&2
        echo "用法: $0 batch <userid1,userid2,...>" >&2
        exit 1
    fi

    echo "📋 批量读取成员: $userids" >&2
    local first=true
    echo "["
    IFS=',' read -ra USERS <<< "$userids"
    for user in "${USERS[@]}"; do
        user=$(echo "$user" | xargs)
        [[ -z "$user" ]] && continue

        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi

        # 逐个调用，输出 JSON（不加额外日志）
        _api_call "GET" "/cgi-bin/user/get?userid=${user}" | jq '.'
        sleep 0.2  # 避免限频
    done
    echo "]"
}

# 按部门获取成员 userid 列表（简易版，只返回 userid 和 name）
cmd_dept() {
    local deptid="$1"
    local fetch_child="${2:-0}"

    if [[ -z "$deptid" ]]; then
        echo "错误: 缺少部门 ID 参数" >&2
        echo "用法: $0 dept <部门ID> [fetch_child=1]" >&2
        exit 1
    fi

    echo "🏢 读取部门 $deptid 的成员列表 (fetch_child=$fetch_child)" >&2
    _api_call "GET" "/cgi-bin/user/simplelist?department_id=${deptid}&fetch_child=${fetch_child}"
}

# 主函数
main() {
    local cmd="${1:-}"
    shift

    case "$cmd" in
        get)
            cmd_get "$@"
            ;;
        batch)
            cmd_batch "$@"
            ;;
        dept)
            cmd_dept "$@"
            ;;
        help|--help|-h)
            cat << EOF
企业微信通讯录读取工具

用法:
  $0 get <userid>              读取单个成员信息
  $0 batch <userid1,userid2>  批量读取成员信息
  $0 dept <部门ID> [fetch_child]  按部门获取成员 userid 列表

示例:
  # 读取单个成员
  $0 get WangXinJing

  # 批量读取
  $0 batch WangXinJing,LiuZhen,Mimi

  # 获取部门成员列表
  $0 dept 1       # 根部门，不含子部门
  $0 dept 1 1     # 根部门，含子部门

  # 完整同步流程示例:
  # 1. 先获取部门列表（通过企业微信管理后台或 wecom-dept.sh）
  # 2. 用 dept 命令逐个部门拉取 userid
  # 3. 用 batch 批量拉取成员详情
  # 4. 手动更新 USER.md
EOF
            ;;
        *)
            echo "未知命令: $cmd" >&2
            echo "使用 '$0 help' 查看帮助" >&2
            exit 1
            ;;
    esac
}

main "$@"
