#!/bin/bash

# wecom-groupchat.sh - 企业微信群聊管理脚本
# 用于创建、修改、获取群聊会话以及发送消息

set -e

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${WORKSPACE_DIR:-"$(cd "$SCRIPT_DIR/../../.." && pwd)"}"
CONFIG_FILE="$WORKSPACE_DIR/config.json"
TOKEN_SCRIPT="$WORKSPACE_DIR/skills/wecom-token.sh"

# 默认配置
CORP_ID=""
CORP_SECRET=""
AGENT_ID=""
PROXY_URL=""

# 加载配置文件
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        CORP_ID=$(cat "$CONFIG_FILE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('wecom',{}).get('corp_id',''))" 2>/dev/null || echo "")
        CORP_SECRET=$(cat "$CONFIG_FILE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('wecom',{}).get('corp_secret',''))" 2>/dev/null || echo "")
        AGENT_ID=$(cat "$CONFIG_FILE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('wecom',{}).get('agent_id',''))" 2>/dev/null || echo "")
        PROXY_URL=$(cat "$CONFIG_FILE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('proxy',{}).get('url',''))" 2>/dev/null || echo "")
    fi
}

# 获取 access_token（统一从 wecom-token.sh 获取）
# 外部如需直接调用可使用此函数
get_access_token() {
    if [[ -x "$TOKEN_SCRIPT" ]]; then
        "$TOKEN_SCRIPT" get
    else
        # 回退：直接调用接口
        local url="https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}"
        if [[ -n "$PROXY_URL" ]]; then
            curl -s -x "$PROXY_URL" "$url" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"
        else
            curl -s "$url" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))"
        fi
    fi
}

# 检查响应是否包含 access_token 相关错误码
check_and_retry() {
    local response="$1"
    local errcode
    errcode=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('errcode',-1))" 2>/dev/null || echo "-1")
    # 40014=不合法的access_token, 42001=access_token超时, 42002=access_token刷新次数超限
    case "$errcode" in
        40014|42001|42002) return 0 ;;
        *) return 1 ;;
    esac
}

# 带自动重试的 API 调用（自动拼接 access_token）
# 用法: _api_call "METHOD" "/cgi-bin/xxx" "JSON_BODY"
_api_call() {
    local method="$1"
    local path="$2"
    local json_body="${3:-}"
    local token

    token=$(get_access_token)
    # 如果 path 已包含 ?（如 GET 带查询参数），直接拼接 access_token
    if [[ "$path" == *"?"* ]]; then
        local url="https://qyapi.weixin.qq.com${path}&access_token=${token}"
    else
        local url="https://qyapi.weixin.qq.com${path}?access_token=${token}"
    fi

    local response
    if [[ -n "$json_body" ]]; then
        if [[ -n "$PROXY_URL" ]]; then
            response=$(curl -s -x "$PROXY_URL" -X "$method" -H "Content-Type: application/json" -d "$json_body" "$url")
        else
            response=$(curl -s -X "$method" -H "Content-Type: application/json" -d "$json_body" "$url")
        fi
    else
        if [[ -n "$PROXY_URL" ]]; then
            response=$(curl -s -x "$PROXY_URL" -X "$method" "$url")
        else
            response=$(curl -s -X "$method" "$url")
        fi
    fi

    if check_and_retry "$response"; then
        [[ -x "$TOKEN_SCRIPT" ]] && "$TOKEN_SCRIPT" force-refresh >/dev/null 2>&1
        token=$(get_access_token)
        if [[ "$path" == *"?"* ]]; then
            url="https://qyapi.weixin.qq.com${path}&access_token=${token}"
        else
            url="https://qyapi.weixin.qq.com${path}?access_token=${token}"
        fi
        if [[ -n "$json_body" ]]; then
            if [[ -n "$PROXY_URL" ]]; then
                response=$(curl -s -x "$PROXY_URL" -X "$method" -H "Content-Type: application/json" -d "$json_body" "$url")
            else
                response=$(curl -s -X "$method" -H "Content-Type: application/json" -d "$json_body" "$url")
            fi
        else
            if [[ -n "$PROXY_URL" ]]; then
                response=$(curl -s -x "$PROXY_URL" -X "$method" "$url")
            else
                response=$(curl -s -X "$method" "$url")
            fi
        fi
    fi

    echo "$response"
}

# 创建群聊
create_chat() {
    local name=""
    local owner=""
    local userlist=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --owner) owner="$2"; shift 2 ;;
            --userlist) userlist="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$userlist" ]]; then
        echo "Error: --userlist is required (comma-separated userids)" >&2
        return 1
    fi
    
    # 构建 userlist 数组
    local user_array=""
    IFS=',' read -ra USERS <<< "$userlist"
    for user in "${USERS[@]}"; do
        if [[ -n "$user_array" ]]; then
            user_array+=","
        fi
        user_array+="\"$user\""
    done
    
    local json_body='{"userlist":['"$user_array"']}'
    
    if [[ -n "$name" ]]; then
        json_body=$(echo "$json_body" | python3 -c "import sys,json; d=json.load(sys.stdin); d['name']='$name'; print(json.dumps(d))")
    fi
    
    if [[ -n "$owner" ]]; then
        json_body=$(echo "$json_body" | python3 -c "import sys,json; d=json.load(sys.stdin); d['owner']='$owner'; print(json.dumps(d))")
    fi
    
    _api_call "POST" "/cgi-bin/appchat/create" "$json_body"
}

# 修改群聊
update_chat() {
    local chatid=""
    local name=""
    local owner=""
    local add_user_list=""
    local del_user_list=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --chatid) chatid="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            --owner) owner="$2"; shift 2 ;;
            --add_user_list) add_user_list="$2"; shift 2 ;;
            --del_user_list) del_user_list="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$chatid" ]]; then
        echo "Error: --chatid is required" >&2
        return 1
    fi
    
    local json_body="{\"chatid\":\"$chatid\"}"
    
    if [[ -n "$name" ]]; then
        json_body=$(echo "$json_body" | python3 -c "import sys,json; d=json.load(sys.stdin); d['name']='$name'; print(json.dumps(d))")
    fi
    
    if [[ -n "$owner" ]]; then
        json_body=$(echo "$json_body" | python3 -c "import sys,json; d=json.load(sys.stdin); d['owner']='$owner'; print(json.dumps(d))")
    fi
    
    if [[ -n "$add_user_list" ]]; then
        local user_array=""
        IFS=',' read -ra USERS <<< "$add_user_list"
        for user in "${USERS[@]}"; do
            if [[ -n "$user_array" ]]; then
                user_array+=","
            fi
            user_array+="\"$user\""
        done
        json_body=$(echo "$json_body" | python3 -c "import sys,json; d=json.load(sys.stdin); d['add_user_list']=[$user_array]; print(json.dumps(d))")
    fi
    
    if [[ -n "$del_user_list" ]]; then
        local user_array=""
        IFS=',' read -ra USERS <<< "$del_user_list"
        for user in "${USERS[@]}"; do
            if [[ -n "$user_array" ]]; then
                user_array+=","
            fi
            user_array+="\"$user\""
        done
        json_body=$(echo "$json_body" | python3 -c "import sys,json; d=json.load(sys.stdin); d['del_user_list']=[$user_array]; print(json.dumps(d))")
    fi
    
    _api_call "POST" "/cgi-bin/appchat/update" "$json_body"
}

# 获取群聊信息
get_chat() {
    local chatid=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --chatid) chatid="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$chatid" ]]; then
        echo "Error: --chatid is required" >&2
        return 1
    fi
    
    _api_call "GET" "/cgi-bin/appchat/get?chatid=${chatid}"
}

# 发送文本消息
send_text() {
    local chatid=""
    local content=""
    local mentioned_list=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --chatid) chatid="$2"; shift 2 ;;
            --content) content="$2"; shift 2 ;;
            --mentioned_list) mentioned_list="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$chatid" ]] || [[ -z "$content" ]]; then
        echo "Error: --chatid and --content are required" >&2
        return 1
    fi
    
    local json_body="{\"chatid\":\"$chatid\",\"msgtype\":\"text\",\"text\":{\"content\":\"$content\"}}"
    
    if [[ -n "$mentioned_list" ]]; then
        local user_array=""
        IFS=',' read -ra USERS <<< "$mentioned_list"
        for user in "${USERS[@]}"; do
            if [[ -n "$user_array" ]]; then
                user_array+=","
            fi
            user_array+="\"$user\""
        done
        json_body=$(echo "$json_body" | python3 -c "import sys,json; d=json.load(sys.stdin); d['text']['mentioned_list']=[$user_array]; print(json.dumps(d))")
    fi
    
    _api_call "POST" "/cgi-bin/appchat/send" "$json_body"
}

# 发送 Markdown 消息
send_markdown() {
    local chatid=""
    local content=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --chatid) chatid="$2"; shift 2 ;;
            --content) content="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$chatid" ]] || [[ -z "$content" ]]; then
        echo "Error: --chatid and --content are required" >&2
        return 1
    fi
    
    # 转义特殊字符
    content=$(echo "$content" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    local json_body="{\"chatid\":\"$chatid\",\"msgtype\":\"markdown\",\"markdown\":{\"content\":\"$content\"}}"
    
    _api_call "POST" "/cgi-bin/appchat/send" "$json_body"
}

# 发送图片消息
send_image() {
    local chatid=""
    local media_id=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --chatid) chatid="$2"; shift 2 ;;
            --media_id) media_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$chatid" ]] || [[ -z "$media_id" ]]; then
        echo "Error: --chatid and --media_id are required" >&2
        return 1
    fi
    
    local access_token=$(get_access_token)
    local json_body="{\"chatid\":\"$chatid\",\"msgtype\":\"image\",\"image\":{\"media_id\":\"$media_id\"}}"
    
    _api_call "POST" "/cgi-bin/appchat/send" "$json_body"
}

# 发送文件消息
send_file() {
    local chatid=""
    local media_id=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --chatid) chatid="$2"; shift 2 ;;
            --media_id) media_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$chatid" ]] || [[ -z "$media_id" ]]; then
        echo "Error: --chatid and --media_id are required" >&2
        return 1
    fi
    
    local access_token=$(get_access_token)
    local json_body="{\"chatid\":\"$chatid\",\"msgtype\":\"file\",\"file\":{\"media_id\":\"$media_id\"}}"
    
    _api_call "POST" "/cgi-bin/appchat/send" "$json_body"
}

# 显示帮助
show_help() {
    cat << EOF
企业微信群聊管理脚本

用法:
    $0 <command> [options]

命令:
    create          创建群聊
    update          修改群聊
    get             获取群聊信息
    send-text       发送文本消息
    send-markdown   发送 Markdown 消息
    send-image      发送图片消息
    send-file       发送文件消息
    help            显示帮助

示例:
    # 创建群聊
    $0 create --name "测试群" --owner "userid1" --userlist "user1,user2,user3"

    # 修改群聊
    $0 update --chatid "CHATID" --name "新名称" --add_user_list "user4"

    # 获取群聊信息
    $0 get --chatid "CHATID"

    # 发送文本消息
    $0 send-text --chatid "CHATID" --content "Hello World"

    # 发送 Markdown 消息
    $0 send-markdown --chatid "CHATID" --content "**加粗** 内容"

    # 发送图片消息
    $0 send-image --chatid "CHATID" --media_id "MEDIA_ID"

    # 发送文件消息
    $0 send-file --chatid "CHATID" --media_id "MEDIA_ID"
EOF
}

# 主函数
main() {
    # 加载配置
    load_config
    
    # 检查参数
    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        create)
            create_chat "$@"
            ;;
        update)
            update_chat "$@"
            ;;
        get)
            get_chat "$@"
            ;;
        send-text)
            send_text "$@"
            ;;
        send-markdown)
            send_markdown "$@"
            ;;
        send-image)
            send_image "$@"
            ;;
        send-file)
            send_file "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $command" >&2
            show_help
            exit 1
            ;;
    esac
}

main "$@"
