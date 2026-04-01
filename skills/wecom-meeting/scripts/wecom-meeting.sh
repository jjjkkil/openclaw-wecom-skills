#!/bin/bash

# 企业微信预约会议管理脚本
# 支持创建、修改、取消、查询预约会议

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
        DEFAULT_MEETING_ADMIN=$(jq -r '.wecom.default_meeting_admin // empty' "$CONFIG_FILE")
    else
        CORP_ID=$(grep -o '"corp_id"[^,]*' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
        CORP_SECRET=$(grep -o '"corp_secret"[^,]*' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
        AGENT_ID=$(grep -o '"agent_id"[^,]*' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
        PROXY_URL=$(grep -o '"url"[^,]*' "$CONFIG_FILE" | tail -1 | cut -d'"' -f4)
        DEFAULT_MEETING_ADMIN=$(grep -o '"default_meeting_admin"[^,]*' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
    fi
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在。请参考 workspace 根目录的 config.json 配置文件。" >&2
    exit 1
fi

DEFAULT_ADMIN="${DEFAULT_MEETING_ADMIN}"  # 从 config.json 读取（必需）

# 获取 access_token（统一从 wecom-token.sh 获取，失败才回退直接调用）
get_access_token() {
    if [[ -x "$TOKEN_SCRIPT" ]]; then
        "$TOKEN_SCRIPT" get
    else
        # 回退：直接调用接口
        if [ -z "$CORP_SECRET" ]; then
            echo "错误: 无法获取 CORP_SECRET，请检查 $CONFIG_FILE" >&2
            exit 1
        fi
        curl -s --proxy "$PROXY_URL" \
            "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}" \
            | jq -r '.access_token // empty'
    fi
}

# 检查响应是否包含 access_token 相关错误码
check_and_retry() {
    local response="$1"
    local errcode
    errcode=$(echo "$response" | jq -r '.errcode // -1' 2>/dev/null || echo "-1")
    # 40014=不合法的access_token, 42001=access_token超时, 42002=access_token刷新次数超限
    case "$errcode" in
        40014|42001|42002) return 0 ;;
        *) return 1 ;;
    esac
}

# 带自动重试的 API 调用（自动将 access_token 拼入 URL）
# 用法: api_call "POST" "/cgi-bin/xxx" "JSON_BODY"
_api_call() {
    local method="$1"
    local path="$2"
    local json_body="${3:-}"
    local token

    token=$(get_access_token)
    local url="https://qyapi.weixin.qq.com${path}?access_token=${token}"

    local response
    if [[ -n "$json_body" ]]; then
        response=$(curl -s --proxy "$PROXY_URL" -X "$method" \
            -H "Content-Type: application/json" \
            -d "$json_body" "$url")
    else
        response=$(curl -s --proxy "$PROXY_URL" -X "$method" "$url")
    fi

    if check_and_retry "$response"; then
        # token 过期，强制刷新后重试
        [[ -x "$TOKEN_SCRIPT" ]] && "$TOKEN_SCRIPT" force-refresh >/dev/null 2>&1
        token=$(get_access_token)
        url="https://qyapi.weixin.qq.com${path}?access_token=${token}"
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

# 将日期时间转换为 Unix 时间戳
datetime_to_timestamp() {
    local datetime="$1"
    # 支持格式: 2026-03-16 09:00
    # macOS 使用 -j -f 参数
    date -j -f "%Y-%m-%d %H:%M" "$datetime" +%s 2>/dev/null || echo ""
}

# 创建会议
create_meeting() {
    local title=""
    local start_time=""
    local duration=3600
    local description=""
    local location=""
    local admin_userid="$DEFAULT_ADMIN"  # 默认使用固定管理员
    local invitees=""
    local hosts=""
    local password=""
    local enable_waiting_room="false"
    local allow_enter_before_host="true"
    local enable_enter_mute="1"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title) title="$2"; shift 2 ;;
            --start) start_time="$2"; shift 2 ;;
            --duration) duration="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --location) location="$2"; shift 2 ;;
            --admin) admin_userid="$2"; shift 2 ;;
            --invitees) invitees="$2"; shift 2 ;;
            --hosts) hosts="$2"; shift 2 ;;
            --password) password="$2"; shift 2 ;;
            --enable_waiting_room) enable_waiting_room="$2"; shift 2 ;;
            --allow_enter_before_host) allow_enter_before_host="$2"; shift 2 ;;
            --enable_enter_mute) enable_enter_mute="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # 验证必需参数
    if [ -z "$title" ] || [ -z "$start_time" ]; then
        echo "错误: 缺少必需参数 --title, --start" >&2
        echo "用法: $0 create --title \"会议标题\" --start \"2026-03-16 09:00\" [--invitees \"user1,user2\"]" >&2
        exit 1
    fi
    
    local start_timestamp=$(datetime_to_timestamp "$start_time")
    if [ -z "$start_timestamp" ]; then
        echo "错误: 时间格式不正确，请使用 'YYYY-MM-DD HH:MM' 格式" >&2
        exit 1
    fi
    
    
    # 构建请求体
    local json_body="{"
    json_body+="\"admin_userid\":\"$admin_userid\","
    json_body+="\"title\":\"$title\","
    json_body+="\"meeting_start\":$start_timestamp,"
    json_body+="\"meeting_duration\":$duration,"
    json_body+="\"agentid\":$AGENT_ID"
    
    if [ -n "$description" ]; then
        json_body+=",\"description\":\"$description\""
    fi
    
    if [ -n "$location" ]; then
        json_body+=",\"location\":\"$location\""
    fi
    
    # 处理参会人 - 自动将管理员加入参会人列表（API要求）
    json_body+=",\"invitees\":{\"userid\":["
    local first=true
    
    # 先添加管理员
    json_body+="\"$admin_userid\""
    first=false
    
    # 再添加其他参会人
    if [ -n "$invitees" ]; then
        IFS=',' read -ra users <<< "$invitees"
        for user in "${users[@]}"; do
            user=$(echo "$user" | xargs)  # 去除空格
            # 避免重复添加管理员
            if [ "$user" != "$admin_userid" ]; then
                json_body+=","
                json_body+="\"$user\""
            fi
        done
    fi
    json_body+="]}"
    
    # 处理设置
    json_body+=",\"settings\":{"
    json_body+="\"remind_scope\":1,"
    json_body+="\"enable_waiting_room\":$enable_waiting_room,"
    json_body+="\"allow_enter_before_host\":$allow_enter_before_host,"
    json_body+="\"enable_enter_mute\":$enable_enter_mute"
    
    if [ -n "$password" ]; then
        json_body+=",\"password\":\"$password\""
    fi
    
    # 处理主持人列表
    if [ -n "$hosts" ]; then
        json_body+=",\"hosts\":{\"userid\":["
        local host_first=true
        IFS=',' read -ra host_users <<< "$hosts"
        for host in "${host_users[@]}"; do
            host=$(echo "$host" | xargs)  # 去除空格
            if [ "$host_first" = true ]; then
                host_first=false
            else
                json_body+=","
            fi
            json_body+="\"$host\""
        done
        json_body+="]}"
    fi
    
    json_body+="}"
    json_body+="}"
    
    echo "📝 创建会议..." >&2
    _api_call "POST" "/cgi-bin/meeting/create" "$json_body"
}

# 修改会议
update_meeting() {
    local meetingid=""
    local title=""
    local start_time=""
    local duration=""
    local description=""
    local location=""
    local invitees=""
    local password=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --meetingid) meetingid="$2"; shift 2 ;;
            --title) title="$2"; shift 2 ;;
            --start) start_time="$2"; shift 2 ;;
            --duration) duration="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --location) location="$2"; shift 2 ;;
            --invitees) invitees="$2"; shift 2 ;;
            --password) password="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [ -z "$meetingid" ]; then
        echo "错误: 缺少必需参数 --meetingid" >&2
        exit 1
    fi
    
    
    # 构建请求体
    local json_body="{\"meetingid\":\"$meetingid\"}"
    
    # 添加可选参数
    if [ -n "$title" ]; then
        json_body=$(echo "$json_body" | jq ".title = \"$title\"")
    fi
    
    if [ -n "$start_time" ]; then
        local start_timestamp=$(datetime_to_timestamp "$start_time")
        if [ -n "$start_timestamp" ]; then
            json_body=$(echo "$json_body" | jq ".meeting_start = $start_timestamp")
        fi
    fi
    
    if [ -n "$duration" ]; then
        json_body=$(echo "$json_body" | jq ".meeting_duration = $duration")
    fi
    
    if [ -n "$description" ]; then
        json_body=$(echo "$json_body" | jq ".description = \"$description\"")
    fi
    
    if [ -n "$location" ]; then
        json_body=$(echo "$json_body" | jq ".location = \"$location\"")
    fi
    
    # 处理参会人
    if [ -n "$invitees" ]; then
        local invitees_json="["
        local first=true
        IFS=',' read -ra users <<< "$invitees"
        for user in "${users[@]}"; do
            user=$(echo "$user" | xargs)
            if [ "$first" = true ]; then
                first=false
            else
                invitees_json+=","
            fi
            invitees_json+="\"$user\""
        done
        invitees_json+="]"
        json_body=$(echo "$json_body" | jq ".invitees.userid = $invitees_json")
    fi
    
    echo "📝 修改会议..." >&2
    _api_call "POST" "/cgi-bin/meeting/update" "$json_body"
}

# 取消会议
cancel_meeting() {
    local meetingid="$1"
    
    if [ -z "$meetingid" ]; then
        echo "错误: 缺少必需参数 meetingid" >&2
        echo "用法: $0 cancel <meetingid>" >&2
        exit 1
    fi
    
    
    local json_body="{\"meetingid\":\"$meetingid\"}"
    
    echo "🗑️  取消会议..." >&2
    _api_call "POST" "/cgi-bin/meeting/cancel" "$json_body"
}

# 获取会议详情
get_meeting_info() {
    local meetingid="$1"
    
    if [ -z "$meetingid" ]; then
        echo "错误: 缺少必需参数 meetingid" >&2
        echo "用法: $0 info <meetingid>" >&2
        exit 1
    fi
    
    
    local json_body="{\"meetingid\":\"$meetingid\"}"
    
    echo "📋 获取会议详情..." >&2
    _api_call "POST" "/cgi-bin/meeting/get_info" "$json_body"
}

# 列出用户的会议列表
list_meetings() {
    local userid="$1"
    local begin_time="$2"
    local end_time="$3"
    local cursor=""
    local limit=100
    
    if [ -z "$userid" ]; then
        echo "错误: 缺少必需参数 userid" >&2
        echo "用法: $0 list <userid> [开始时间] [结束时间]" >&2
        echo "时间格式: YYYY-MM-DD HH:MM" >&2
        exit 1
    fi
    
    
    # 默认查询今天到7天后的会议
    if [ -z "$begin_time" ]; then
        begin_time=$(date +%Y-%m-%d)" 00:00"
    fi
    if [ -z "$end_time" ]; then
        end_time=$(date -v+7d +%Y-%m-%d)" 23:59"
    fi
    
    local begin_timestamp=$(datetime_to_timestamp "$begin_time")
    local end_timestamp=$(datetime_to_timestamp "$end_time")
    
    if [ -z "$begin_timestamp" ] || [ -z "$end_timestamp" ]; then
        echo "错误: 时间格式不正确，请使用 'YYYY-MM-DD HH:MM' 格式" >&2
        exit 1
    fi
    
    echo "📋 查询用户 $userid 的会议列表 ($begin_time ~ $end_time)..." >&2
    
    local json_body="{"
    json_body+="\"userid\":\"$userid\","
    json_body+="\"begin_time\":$begin_timestamp,"
    json_body+="\"end_time\":$end_timestamp,"
    json_body+="\"limit\":$limit"
    json_body+="}"
    
    _api_call "POST" "/cgi-bin/meeting/get_user_meetingid" "$json_body"
}

# 主函数
main() {
    local cmd="$1"
    shift
    
    case "$cmd" in
        create)
            create_meeting "$@"
            ;;
        update)
            update_meeting "$@"
            ;;
        cancel)
            cancel_meeting "$@"
            ;;
        info|get)
            get_meeting_info "$@"
            ;;
        list|ls)
            list_meetings "$@"
            ;;
        help|--help|-h)
            cat << EOF
企业微信预约会议管理工具

用法:
  ./wecom-meeting.sh create [选项]    创建会议
  ./wecom-meeting.sh update [选项]    修改会议
  ./wecom-meeting.sh cancel <会议ID>  取消会议
  ./wecom-meeting.sh info <会议ID>    获取会议详情
  ./wecom-meeting.sh list <用户ID> [开始时间] [结束时间]  列出用户会议

创建会议选项:
  --title          会议标题 (必需)
  --start          开始时间, 格式: "2026-03-16 09:00" (必需)
  --duration       会议时长(秒), 默认3600(1小时)
  --description    会议描述
  --location       会议地点
  --invitees       参会人, 逗号分隔: "user1,user2,user3"
                   (管理员 $DEFAULT_ADMIN 会自动加入)
  --hosts          主持人列表, 逗号分隔: "user1,user2"
                   (最多10个, 若包含创建者会自动过滤)
  --password       会议密码
  --admin          管理员用户ID (必需，从 config.json 读取)

修改会议选项:
  --meetingid      会议ID (必需)
  --title          新标题
  --start          新开始时间
  --duration       新时长
  --description    新描述
  --location       新地点
  --invitees       新参会人列表

示例:
  # 创建一个会议 (管理员从 config.json 读取)
  ./wecom-meeting.sh create --title "产品评审会" --start "2026-03-16 09:00" --invitees "${USER_X},${USER_Y}"

  # 只给自己创建会议
  ./wecom-meeting.sh create --title "个人会议" --start "2026-03-16 09:00"

  # 修改会议时间
  ./wecom-meeting.sh update --meetingid "hyxxxx" --start "2026-03-16 14:00" --duration 7200

  # 取消会议
  ./wecom-meeting.sh cancel "hyxxxx"

  # 查看会议详情
  ./wecom-meeting.sh info "hyxxxx"

  # 列出用户的会议列表（默认查询未来7天）
  ./wecom-meeting.sh list "${USER_X}"
  
  # 列出指定时间范围的会议
  ./wecom-meeting.sh list "${USER_X}" "2026-03-24 00:00" "2026-03-24 23:59"
EOF
            ;;
        *)
            echo "未知命令: $cmd" >&2
            echo "使用 './wecom-meeting.sh help' 查看帮助" >&2
            exit 1
            ;;
    esac
}

main "$@"
