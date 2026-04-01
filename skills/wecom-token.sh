#!/bin/bash
#
# wecom-token.sh - 企业微信 Access Token 统一管理脚本
#
# 功能：
#   1. 从 config.json 读取 corpid/corpsecret
#   2. 检查缓存的 access_token 是否有效（未过期）
#   3. 如无缓存或已过期，调用企业微信 gettoken 接口获取新 token
#   4. 将新 token 及过期时间写入 config.json
#   5. 输出 token 值
#
# 用法：
#   source /path/to/wecom-token.sh   # 在调用方脚本中 source（会定义 get_wecom_token 函数）
#   或直接执行：
#   ./wecom-token.sh get            # 获取（可能已缓存）的 token
#   ./wecom-token.sh force-refresh  # 强制刷新 token
#
# config.json 中的存储结构：
#   {
#     "wecom": {
#       "corp_id": "...",
#       "corp_secret": "...",
#       "agent_id": "...",
#       "access_token": "xxx",
#       "expires_at": 1234567890,
#       "token_updated_at": 1234567890
#     }
#   }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# skills/wecom-token.sh → SCRIPT_DIR = .../workspace/skills
# 上一级 = workspace 根目录
WORKSPACE_DIR="${WORKSPACE_DIR:-"$(cd "$SCRIPT_DIR/.." && pwd)"}"
CONFIG_FILE="$WORKSPACE_DIR/config.json"

# 提前过期缓冲秒数（避免临界点）
EXPIRE_BUFFER=300

# ---------------------------------------------------------------
# 加载配置（从 config.json 读取 wecom 节点）
# ---------------------------------------------------------------
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: 配置文件不存在: $CONFIG_FILE" >&2
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: 需要 jq 工具，请先安装: brew install jq" >&2
        exit 1
    fi

    CORP_ID=$(jq -r '.wecom.corp_id // empty' "$CONFIG_FILE")
    CORP_SECRET=$(jq -r '.wecom.corp_secret // empty' "$CONFIG_FILE")
    PROXY_URL=$(jq -r '.proxy.url // empty' "$CONFIG_FILE")

    # 如果 config.json 中没有 proxy.url，尝试从 openclaw.json 读取
    if [[ -z "$PROXY_URL" ]] && [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
        PROXY_URL=$(jq -r '.. | objects | select(has("egressProxyUrl")) | .egressProxyUrl // empty' "$HOME/.openclaw/openclaw.json" 2>/dev/null)
    fi

    if [[ -z "$CORP_ID" ]] || [[ -z "$CORP_SECRET" ]]; then
        echo "ERROR: config.json 中缺少 wecom.corp_id 或 wecom.corp_secret" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------
# 从 config.json 读取缓存的 access_token
# ---------------------------------------------------------------
read_cached_token() {
    jq -r '.wecom.access_token // empty' "$CONFIG_FILE" 2>/dev/null
}

# ---------------------------------------------------------------
# 从 config.json 读取缓存的过期时间（Unix 时间戳）
# ---------------------------------------------------------------
read_expires_at() {
    jq -r '.wecom.expires_at // 0' "$CONFIG_FILE" 2>/dev/null
}

# ---------------------------------------------------------------
# 将新的 access_token 写入 config.json
# ---------------------------------------------------------------
save_token() {
    local token="$1"
    local expires_in="$2"
    local now=$(date +%s)
    # 过期时间 = 当前时间 + expires_in - 缓冲
    local expires_at=$((now + expires_in - EXPIRE_BUFFER))

    # 使用 jq 更新 config.json，保留其他字段
    local tmp_file
    tmp_file=$(mktemp)

    jq --arg token "$token" \
       --argjson expires_at "$expires_at" \
       --argjson now "$now" \
       '.wecom.access_token = $token | .wecom.expires_at = $expires_at | .wecom.token_updated_at = $now' \
       "$CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$CONFIG_FILE"

    echo "Token 已写入 config.json，过期时间: $(date -r $expires_at '+%Y-%m-%d %H:%M:%S')" >&2
}

# ---------------------------------------------------------------
# 检查缓存的 token 是否仍然有效
# ---------------------------------------------------------------
is_token_valid() {
    local cached_token
    local expires_at

    cached_token=$(read_cached_token)
    expires_at=$(read_expires_at)

    if [[ -z "$cached_token" ]] || [[ "$cached_token" == "null" ]]; then
        return 1  # 无缓存
    fi

    local now=$(date +%s)
    if [[ $now -lt $expires_at ]]; then
        return 0  # 缓存有效
    else
        return 1  # 已过期
    fi
}

# ---------------------------------------------------------------
# 调用企业微信 gettoken 接口
# ---------------------------------------------------------------
fetch_new_token() {
    local url="https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}"
    local response

    if [[ -n "$PROXY_URL" ]]; then
        response=$(curl -s --proxy "$PROXY_URL" "$url")
    else
        response=$(curl -s "$url")
    fi

    local errcode
    local access_token
    local expires_in

    errcode=$(echo "$response" | jq -r '.errcode // -1')
    access_token=$(echo "$response" | jq -r '.access_token // empty')
    expires_in=$(echo "$response" | jq -r '.expires_in // 7200')

    if [[ "$errcode" != "0" ]] || [[ -z "$access_token" ]]; then
        echo "ERROR: 获取 access_token 失败: $response" >&2
        return 1
    fi

    # 保存到 config.json
    save_token "$access_token" "$expires_in"

    echo "$access_token"
}

# ---------------------------------------------------------------
# 主函数：获取 token（优先使用缓存）
# ---------------------------------------------------------------
get_token_main() {
    load_config

    if is_token_valid; then
        local cached_token
        cached_token=$(read_cached_token)
        echo "使用缓存的 access_token" >&2
        echo "$cached_token"
        return 0
    fi

    echo "缓存已过期或无缓存，重新获取 access_token..." >&2
    fetch_new_token
}

# ---------------------------------------------------------------
# 强制刷新 token
# ---------------------------------------------------------------
force_refresh_token() {
    load_config

    echo "强制刷新 access_token..." >&2
    fetch_new_token
}

# ---------------------------------------------------------------
# 命令行入口
# ---------------------------------------------------------------
main() {
    local cmd="${1:-get}"

    case "$cmd" in
        get)
            get_token_main
            ;;
        force-refresh)
            force_refresh_token
            ;;
        *)
            echo "用法: $0 [get|force-refresh]" >&2
            exit 1
            ;;
    esac
}

# 如果被 source 而不是直接执行，提供 get_wecom_token 函数
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # 被 source：定义函数后直接执行参数（兼容旧调用方式）
    get_wecom_token() {
        load_config >/dev/null 2>&1

        if is_token_valid; then
            read_cached_token
        else
            fetch_new_token
        fi
    }
else
    # 直接执行
    main "$@"
fi
