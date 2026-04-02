#!/bin/bash
#
# 企业微信日程管理工具 (Bash + curl 版本，支持代理)
#
# 用法:
#   ./wecom-schedule.sh create-calendar "日历名称" ["描述"]
#   ./wecom-schedule.sh list-cals
#   ./wecom-schedule.sh remove-calendar "cal_id"
#   ./wecom-schedule.sh create --title "会议" --start "2025-01-15 14:00" --end "2025-01-15 15:00"
#   ./wecom-schedule.sh get "schedule_id"
#   ./wecom-schedule.sh delete "schedule_id"
#   ./wecom-schedule.sh add-attendees "schedule_id" "user1" "user2"

# 配置 - 从 workspace/config.json 读取
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${WORKSPACE_DIR:-"$(cd "$SCRIPT_DIR/../../.." && pwd)"}"
CONFIG_FILE="$WORKSPACE_DIR/config.json"
TOKEN_SCRIPT="$WORKSPACE_DIR/skills/wecom-token.sh"

# 需要 jq 来处理 JSON（新版日历功能依赖 jq）
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ 错误: 此版本需要 jq，请先安装: brew install jq" >&2
    exit 1
fi

# 如果 config.json 存在则读取
if [ -f "$CONFIG_FILE" ]; then
    CORP_ID=$(jq -r '.wecom.corp_id // empty' "$CONFIG_FILE")
    CORP_SECRET=$(jq -r '.wecom.corp_secret // empty' "$CONFIG_FILE")
    AGENT_ID=$(jq -r '.wecom.agent_id // empty' "$CONFIG_FILE")
    PROXY_URL=$(jq -r '.proxy.url // empty' "$CONFIG_FILE")
    CALENDARS_JSON=$(jq -r '.wecom.calendars // {}' "$CONFIG_FILE")
    DEFAULT_CALENDAR_COLOR=$(jq -r '.default_calendar_color // empty' "$CONFIG_FILE")
else
    echo "⚠️  警告: 未找到配置文件 $CONFIG_FILE，使用默认配置" >&2
    CALENDARS_JSON="{}"
fi

# 如果配置为空，使用默认值
CORP_ID="${CORP_ID}"
CORP_SECRET="${CORP_SECRET}"
AGENT_ID="${AGENT_ID}"
PROXY_URL="${PROXY_URL}"

# 获取默认日历 ID（calendars 对象中第一个键）
get_default_cal_id() {
    if [ -z "$CALENDARS_JSON" ] || [ "$CALENDARS_JSON" = "null" ] || [ "$CALENDARS_JSON" = "{}" ]; then
        echo ""
    else
        echo "$CALENDARS_JSON" | jq -r 'keys[0]' 2>/dev/null
    fi
}

# 获取日历名称
get_calendar_name() {
    local cal_id="$1"
    if [ -z "$CALENDARS_JSON" ] || [ "$CALENDARS_JSON" = "null" ]; then
        echo ""
    else
        echo "$CALENDARS_JSON" | jq -r ".[\"${cal_id}\"].name // empty" 2>/dev/null
    fi
}

DEFAULT_CAL_ID=$(get_default_cal_id)

# 获取 access_token（统一从 wecom-token.sh 获取，失败才回退直接调用）
get_token() {
    if [[ -x "$TOKEN_SCRIPT" ]]; then
        "$TOKEN_SCRIPT" get
    else
        # 回退：直接调用接口
        local response=$(curl -s -x "$PROXY_URL" \
            "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${CORP_ID}&corpsecret=${CORP_SECRET}")
        local token=$(echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
        if [ -z "$token" ]; then
            echo "❌ 获取 token 失败: $response" >&2
            exit 1
        fi
        echo "$token"
    fi
}

# 检查响应是否包含 access_token 相关错误码
check_and_retry() {
    local response="$1"
    local errcode
    errcode=$(echo "$response" | grep -o '"errcode":[0-9]*' | head -1 | cut -d':' -f2)
    # 40014=不合法的access_token, 42001=access_token超时, 42002=access_token刷新次数超限
    case "$errcode" in
        40014|42001|42002) return 0 ;;
        *) return 1 ;;
    esac
}

# 带自动重试的 API 调用
# 用法: _api_call "METHOD" "/cgi-bin/xxx" "JSON_BODY"
_api_call() {
    local method="$1"
    local path="$2"
    local json_body="${3:-}"
    local token

    token=$(get_token)
    local url="https://qyapi.weixin.qq.com${path}?access_token=${token}"

    local response
    if [[ -n "$json_body" ]]; then
        response=$(curl -s -x "$PROXY_URL" -X "$method" \
            -H "Content-Type: application/json" \
            -d "$json_body" "$url")
    else
        response=$(curl -s -x "$PROXY_URL" -X "$method" "$url")
    fi

    if check_and_retry "$response"; then
        [[ -x "$TOKEN_SCRIPT" ]] && "$TOKEN_SCRIPT" force-refresh >/dev/null 2>&1
        token=$(get_token)
        url="https://qyapi.weixin.qq.com${path}?access_token=${token}"
        if [[ -n "$json_body" ]]; then
            response=$(curl -s -x "$PROXY_URL" -X "$method" \
                -H "Content-Type: application/json" \
                -d "$json_body" "$url")
        else
            response=$(curl -s -x "$PROXY_URL" -X "$method" "$url")
        fi
    fi

    echo "$response"
}

# 创建日历
# 用法: create_calendar "名称" ["描述"] ["颜色代码"]
# 颜色示例: #3366CC(蓝) #FF6600(橙) #009900(绿) #CC0000(红) #9900CC(紫)
create_calendar() {
    local name="$1"
    local desc="${2:-}"
    local color="${3:-${DEFAULT_CALENDAR_COLOR:-#3366CC}}"
    
    local json=$(cat <<EOF
{
    "calendar": {
        "summary": "${name}",
        "description": "${desc}",
        "color": "${color}",
        "admins": [],
        "is_public": 1
    },
    "agentid": ${AGENT_ID}
}
EOF
)
    
    local response=$(_api_call "POST" "/cgi-bin/oa/calendar/add" "$json")
    echo "$response"
    
    # 解析返回的 cal_id 并写入 config.json
    local errcode=$(echo "$response" | jq -r '.errcode // empty')
    if [ "$errcode" = "0" ]; then
        local cal_id=$(echo "$response" | jq -r '.cal_id // empty')
        if [ -n "$cal_id" ] && [ "$cal_id" != "null" ]; then
            local created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            local new_cal_entry=$(jq -n \
                --arg id "$cal_id" \
                --arg name "$name" \
                --arg desc "$desc" \
                --arg created "$created_at" \
                '{name: $name, description: $desc, created_at: $created}')
            
            # 检查是否已有 calendars 对象
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "⚠️ 配置文件不存在，无法保存日历信息" >&2
                return
            fi
            
            local existing=$(jq -r '.wecom.calendars // {}' "$CONFIG_FILE")
            local new_calendars=$(echo "$existing" | jq --argjson id "$cal_id" --argjson entry "$new_cal_entry" \
                '.[$id] = $entry')
            
            jq --argjson calendars "$new_calendars" \
                '.wecom.calendars = $calendars' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && \
                mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            
            echo "✅ 日历已保存至 config.json: $cal_id ($name)"
        fi
    else
        local errmsg=$(echo "$response" | jq -r '.errmsg // empty')
        echo "⚠️  日历未保存到 config.json（API 返回错误: $errmsg）" >&2
    fi
}

# 获取日历详情（支持多个日历ID）
# 用法: get_calendar_details "cal_id1" "cal_id2" ...
get_calendar_details() {
    # 构建 cal_id_list 数组
    local cal_id_list=""
    for cal_id in "$@"; do
        if [ -n "$cal_id_list" ]; then
            cal_id_list="${cal_id_list},"
        fi
        cal_id_list="${cal_id_list}\"${cal_id}\""
    done
    
    _api_call "POST" "/cgi-bin/oa/calendar/get" "{\"cal_id_list\": [${cal_id_list}]}"
}

# 创建日程
# 注意：只有被艾特或发起人要求时，才通过 --attendees 添加 ${USER_X}
# 发起人由 attendees 的第一个成员决定，admins 为必填的管理员
create_schedule() {
    local title=""
    local start=""
    local end=""
    local cal_id=""
    local desc=""
    local location=""
    local attendees=""  # 存储参与者（逗号分隔），第一个成员为发起人
    local admins=""     # 存储管理员（逗号分隔），最多3人
    
    # 重复日程参数
    local is_repeat="0"
    local repeat_type=""
    local repeat_until=""
    local is_custom_repeat="0"
    local repeat_interval=""
    local repeat_day_of_week=""
    local repeat_day_of_month=""
    local timezone="8"
    
    # 提醒参数
    local is_remind="1"
    local remind_before_event_secs="3600"
    local remind_time_diffs=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --title) title="$2"; shift 2 ;;
            --start) start="$2"; shift 2 ;;
            --end) end="$2"; shift 2 ;;
            --calId) cal_id="$2"; shift 2 ;;
            --description) desc="$2"; shift 2 ;;
            --location) location="$2"; shift 2 ;;
            --attendees) attendees="$2"; shift 2 ;;  # 参与者，逗号分隔（第一个为发起人）
            --admins) admins="$2"; shift 2 ;;        # 管理员，逗号分隔，最多3人
            --is_repeat) is_repeat="$2"; shift 2 ;;  # 是否重复：0-否，1-是
            --repeat_type) repeat_type="$2"; shift 2 ;;  # 重复类型：0-每日，1-每周，2-每月，5-每年，7-工作日
            --repeat_until) repeat_until="$2"; shift 2 ;;  # 重复结束日期，格式：2025-12-31
            --is_custom_repeat) is_custom_repeat="$2"; shift 2 ;;  # 是否自定义重复：0-否，1-是
            --repeat_interval) repeat_interval="$2"; shift 2 ;;  # 重复间隔
            --repeat_day_of_week) repeat_day_of_week="$2"; shift 2 ;;  # 每周周几重复，逗号分隔：1,3,5
            --repeat_day_of_month) repeat_day_of_month="$2"; shift 2 ;;  # 每月哪几天重复，逗号分隔：1,15
            --timezone) timezone="$2"; shift 2 ;;  # 时区，默认东八区（8）
            --is_remind) is_remind="$2"; shift 2 ;;  # 是否提醒：0-否，1-是
            --remind_before_event_secs) remind_before_event_secs="$2"; shift 2 ;;  # 提前多少秒提醒
            --remind_time_diffs) remind_time_diffs="$2"; shift 2 ;;  # 提醒时间差值数组，逗号分隔：0,-3600
            *) shift ;;
        esac
    done
    
    if [ -z "$title" ] || [ -z "$start" ] || [ -z "$end" ]; then
        echo "❌ 缺少必要参数: --title, --start, --end" >&2
        exit 1
    fi
    
    # 转换时间为时间戳 (macOS 兼容)
    local start_ts=$(date -j -f "%Y-%m-%d %H:%M" "$start" +%s 2>/dev/null || echo "")
    local end_ts=$(date -j -f "%Y-%m-%d %H:%M" "$end" +%s 2>/dev/null || echo "")
    
    if [ -z "$start_ts" ] || [ -z "$end_ts" ]; then
        echo "❌ 时间格式错误，请使用: 2025-01-15 14:00" >&2
        exit 1
    fi
    
    
    # 默认日历 ID: 从 config.json 的 calendars 动态读取第一个
    local default_cal_id
    default_cal_id=$(get_default_cal_id)
    if [ -z "$default_cal_id" ]; then
        echo "❌ 错误: 未配置默认日历 ID (calendars)，请先创建日历" >&2
        exit 1
    fi
    cal_id="${cal_id:-$default_cal_id}"
    
    local cal_id_json='"cal_id": "'"$cal_id"'",'
    
    # 构建参与者 JSON 数组
    local attendees_array=""
    if [ -n "$attendees" ]; then
        IFS=',' read -ra attendee_list <<< "$attendees"
        for user in "${attendee_list[@]}"; do
            user=$(echo "$user" | xargs)  # 去除前后空格
            if [ -n "$user" ]; then
                if [ -n "$attendees_array" ]; then
                    attendees_array="${attendees_array},"
                fi
                attendees_array="${attendees_array}{\"userid\":\"${user}\"}"
            fi
        done
    fi
    
    # 构建管理员 JSON 数组（最多3人）
    local admins_array=""
    if [ -n "$admins" ]; then
        IFS=',' read -ra admin_list <<< "$admins"
        local count=0
        for admin in "${admin_list[@]}"; do
            admin=$(echo "$admin" | xargs)  # 去除前后空格
            if [ -n "$admin" ] && [ $count -lt 3 ]; then
                if [ -n "$admins_array" ]; then
                    admins_array="${admins_array},"
                fi
                admins_array="${admins_array}\"${admin}\""
                ((count++))
            fi
        done
    fi
    
    # 构建 admins 字段 JSON
    local admins_json=""
    if [ -n "$admins_array" ]; then
        admins_json="\"admins\": [${admins_array}],"
    fi
    
    # 构建 reminders 对象
    local reminders_fields="\"is_remind\": ${is_remind}"
    
    if [ "$is_remind" = "1" ]; then
        reminders_fields="${reminders_fields}, \"remind_before_event_secs\": ${remind_before_event_secs}"
        
        # 构建 remind_time_diffs 数组
        if [ -n "$remind_time_diffs" ]; then
            local diffs_array=""
            IFS=',' read -ra diff_list <<< "$remind_time_diffs"
            for diff in "${diff_list[@]}"; do
                diff=$(echo "$diff" | xargs)
                if [ -n "$diff" ]; then
                    if [ -n "$diffs_array" ]; then
                        diffs_array="${diffs_array},"
                    fi
                    diffs_array="${diffs_array}${diff}"
                fi
            done
            reminders_fields="${reminders_fields}, \"remind_time_diffs\": [${diffs_array}]"
        fi
    fi
    
    # 构建重复日程参数
    if [ "$is_repeat" = "1" ]; then
        reminders_fields="${reminders_fields}, \"is_repeat\": 1"
        
        if [ -n "$repeat_type" ]; then
            reminders_fields="${reminders_fields}, \"repeat_type\": ${repeat_type}"
        fi
        
        if [ -n "$repeat_until" ]; then
            # 转换结束日期为时间戳（当天的23:59:59）
            local repeat_until_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$repeat_until 23:59:59" +%s 2>/dev/null || echo "")
            if [ -n "$repeat_until_ts" ]; then
                reminders_fields="${reminders_fields}, \"repeat_until\": ${repeat_until_ts}"
            fi
        fi
        
        reminders_fields="${reminders_fields}, \"is_custom_repeat\": ${is_custom_repeat}"
        
        if [ "$is_custom_repeat" = "1" ]; then
            if [ -n "$repeat_interval" ]; then
                reminders_fields="${reminders_fields}, \"repeat_interval\": ${repeat_interval}"
            fi
            
            if [ -n "$repeat_day_of_week" ]; then
                # 构建周几数组
                local week_array=""
                IFS=',' read -ra week_list <<< "$repeat_day_of_week"
                for day in "${week_list[@]}"; do
                    day=$(echo "$day" | xargs)
                    if [ -n "$day" ]; then
                        if [ -n "$week_array" ]; then
                            week_array="${week_array},"
                        fi
                        week_array="${week_array}${day}"
                    fi
                done
                reminders_fields="${reminders_fields}, \"repeat_day_of_week\": [${week_array}]"
            fi
            
            if [ -n "$repeat_day_of_month" ]; then
                # 构建月几数组
                local month_array=""
                IFS=',' read -ra month_list <<< "$repeat_day_of_month"
                for day in "${month_list[@]}"; do
                    day=$(echo "$day" | xargs)
                    if [ -n "$day" ]; then
                        if [ -n "$month_array" ]; then
                            month_array="${month_array},"
                        fi
                        month_array="${month_array}${day}"
                    fi
                done
                reminders_fields="${reminders_fields}, \"repeat_day_of_month\": [${month_array}]"
            fi
        fi
        
        reminders_fields="${reminders_fields}, \"timezone\": ${timezone}"
    fi
    
    local json=$(cat <<EOF
{
    "schedule": {
        ${admins_json}
        ${cal_id_json}
        "start_time": ${start_ts},
        "end_time": ${end_ts},
        "summary": "${title}",
        "description": "${desc}",
        "location": "${location}",
        "attendees": [${attendees_array}],
        "reminders": {
            ${reminders_fields}
        }
    },
    "agentid": ${AGENT_ID}
}
EOF
)
    
    # 移除不再需要的 local token=$(get_token)
    _api_call "POST" "/cgi-bin/oa/schedule/add" "$json"
}

# 获取指定用户的日程列表
# 注意：企业微信没有直接的 get_by_user 接口，我们通过 get_by_calendar 获取所有日程后筛选
get_user_schedules() {
    local userid="$1"
    local start_date="$2"  # 格式: 2025-01-15
    local end_date="$3"    # 格式: 2025-01-15
    
    
    # 转换为时间戳 (macOS 兼容)
    local start_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$start_date 00:00:00" +%s 2>/dev/null || echo "")
    local end_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$end_date 23:59:59" +%s 2>/dev/null || echo "")
    
    if [ -z "$start_ts" ] || [ -z "$end_ts" ]; then
        echo "❌ 日期格式错误，请使用: 2025-01-15" >&2
        exit 1
    fi
    
    # 使用已知的日历 ID 查询（企业微信 API 需要先知道日历 ID 才能查询）
    # 默认日历 ID: 从 config.json 的 calendars 动态读取第一个
    local default_cal_id
    default_cal_id=$(get_default_cal_id)
    if [ -z "$default_cal_id" ]; then
        echo "❌ 错误: 未配置默认日历 ID (calendars)，请先创建日历" >&2
        exit 1
    fi
    
    # 循环获取所有分页数据
    local all_schedules="[]"
    local offset=0
    local limit=500
    local has_more=1
    
    while [ $has_more -eq 1 ]; do
        local response=$(_api_call "POST" "/cgi-bin/oa/schedule/get_by_calendar" "{\"cal_id\": \"${default_cal_id}\", \"offset\": ${offset}, \"limit\": ${limit}, \"start_time\": ${start_ts}, \"end_time\": ${end_ts}}")
        
        # 检查是否有错误
        local errcode=$(echo "$response" | grep -o '"errcode":[0-9]*' | head -1 | cut -d':' -f2)
        if [ "$errcode" != "0" ]; then
            echo "$response"
            return
        fi
        
        # 提取本次返回的日程列表
        local page_schedules=""
        if command -v jq >/dev/null 2>&1; then
            page_schedules=$(echo "$response" | jq '.schedule_list // []')
        else
            # 如果没有 jq，直接返回第一页数据（带警告）
            echo "⚠️ 警告：未安装 jq，无法进行客户端日期过滤和分页合并" >&2
            echo "$response"
            return
        fi
        
        # 检查是否还有数据
        local page_count=$(echo "$page_schedules" | jq 'length')
        if [ "$page_count" -eq 0 ]; then
            has_more=0
        else
            # 合并到总列表
            all_schedules=$(echo "$all_schedules $page_schedules" | jq -s 'add')
            offset=$((offset + limit))
            
            # 如果本次返回的数据少于 limit，说明已经到最后了
            if [ "$page_count" -lt "$limit" ]; then
                has_more=0
            fi
        fi
    done
    
    # 使用 jq 筛选：
    # 1. 包含指定用户的日程
    # 2. 日程开始时间在查询范围内（start_time >= start_ts 且 start_time <= end_ts）
    # 3. 日程状态为正常（status == 0）
    local filtered=$(echo "$all_schedules" | jq --arg uid "$userid" --argjson start_ts "$start_ts" --argjson end_ts "$end_ts" '{
        errcode: 0, 
        errmsg: "ok", 
        schedule_list: [
            .[]? 
            | select(
                .attendees[]?.userid == $uid 
                and .start_time >= $start_ts 
                and .start_time <= $end_ts
                and .status == 0
            )
        ]
    }')
    echo "$filtered"
}

# 获取日程列表（通过日历ID）
# 支持客户端日期筛选（企业微信API返回所有日程，需要本地过滤）
get_schedules_by_calendar() {
    local cal_id="$1"
    local start_date="$2"  # 可选: 格式 2025-01-15
    local end_date="$3"    # 可选: 格式 2025-01-15
    
    
    # 计算日期范围的时间戳（用于客户端筛选）
    local filter_start_ts=""
    local filter_end_ts=""
    if [ -n "$start_date" ] && [ -n "$end_date" ]; then
        filter_start_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$start_date 00:00:00" +%s 2>/dev/null || echo "")
        filter_end_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$end_date 23:59:59" +%s 2>/dev/null || echo "")
    fi
    
    # 循环获取所有分页数据
    local all_schedules="[]"
    local offset=0
    local limit=500
    local has_more=1
    
    while [ $has_more -eq 1 ]; do
        local response=$(_api_call "POST" "/cgi-bin/oa/schedule/get_by_calendar" "{\"cal_id\": \"${cal_id}\", \"offset\": ${offset}, \"limit\": ${limit}}")
        
        # 检查是否有错误
        local errcode=$(echo "$response" | grep -o '"errcode":[0-9]*' | head -1 | cut -d':' -f2)
        if [ "$errcode" != "0" ]; then
            echo "$response"
            return
        fi
        
        # 提取本次返回的日程列表
        local page_schedules=""
        if command -v jq >/dev/null 2>&1; then
            page_schedules=$(echo "$response" | jq '.schedule_list // []')
        else
            # 如果没有 jq，直接返回第一页数据（带警告）
            echo "⚠️ 警告：未安装 jq，无法进行客户端日期过滤和分页合并" >&2
            echo "$response"
            return
        fi
        
        # 检查是否还有数据
        local page_count=$(echo "$page_schedules" | jq 'length')
        if [ "$page_count" -eq 0 ]; then
            has_more=0
        else
            # 合并到总列表
            all_schedules=$(echo "$all_schedules $page_schedules" | jq -s 'add')
            offset=$((offset + limit))
            
            # 如果本次返回的数据少于 limit，说明已经到最后了
            if [ "$page_count" -lt "$limit" ]; then
                has_more=0
            fi
        fi
    done
    
    # 如果提供了日期范围，进行客户端筛选
    if [ -n "$filter_start_ts" ] && [ -n "$filter_end_ts" ]; then
        local filtered=$(echo "$all_schedules" | jq --argjson start_ts "$filter_start_ts" --argjson end_ts "$filter_end_ts" '{
            errcode: 0,
            errmsg: "ok",
            schedule_list: [
                .[]?
                | select(
                    .start_time >= $start_ts
                    and .start_time <= $end_ts
                )
            ]
        }')
        echo "$filtered"
    else
        # 没有日期范围，返回所有日程
        echo "{\"errcode\": 0, \"errmsg\": \"ok\", \"schedule_list\": $all_schedules}"
    fi
}

# 获取日程详情
get_schedule() {
    local schedule_id="$1"
    _api_call "POST" "/cgi-bin/oa/schedule/get" "{\"schedule_id_list\": [\"${schedule_id}\"]}"
}

# 添加日程参与者
add_attendees() {
    local schedule_id="$1"
    shift
    
    # 构建参与者数组
    local attendees_array=""
    for user in "$@"; do
        if [ -n "$attendees_array" ]; then
            attendees_array="${attendees_array},"
        fi
        attendees_array="${attendees_array}{\"userid\":\"${user}\"}"
    done
    
    local json="{\"schedule_id\": \"${schedule_id}\", \"attendees\": [${attendees_array}]}"
    _api_call "POST" "/cgi-bin/oa/schedule/add_attendees" "$json"
}

# 删除日程参与者
delete_attendees() {
    local schedule_id="$1"
    shift
    
    # 构建参与者数组
    local attendees_array=""
    for user in "$@"; do
        if [ -n "$attendees_array" ]; then
            attendees_array="${attendees_array},"
        fi
        attendees_array="${attendees_array}{\"userid\":\"${user}\"}"
    done
    
    local json="{\"schedule_id\": \"${schedule_id}\", \"attendees\": [${attendees_array}]}"
    _api_call "POST" "/cgi-bin/oa/schedule/del_attendees" "$json"
}

# 删除/取消日程
delete_schedule() {
    local schedule_id="$1"
    _api_call "POST" "/cgi-bin/oa/schedule/del" "{\"schedule_id\": \"${schedule_id}\"}"
}

# 更新日程
update_schedule() {
    local schedule_id=""
    local title=""
    local start=""
    local end=""
    local desc=""
    local location=""
    local attendees=""
    local skip_attendees="0"
    local op_mode=""
    local op_start_time=""
    
    # 重复日程参数
    local is_repeat=""
    local repeat_type=""
    local repeat_until=""
    local is_custom_repeat=""
    local repeat_interval=""
    local repeat_day_of_week=""
    local repeat_day_of_month=""
    local timezone=""
    
    # 提醒参数
    local is_remind=""
    local remind_before_event_secs=""
    local remind_time_diffs=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --schedule_id) schedule_id="$2"; shift 2 ;;
            --title) title="$2"; shift 2 ;;
            --start) start="$2"; shift 2 ;;
            --end) end="$2"; shift 2 ;;
            --description) desc="$2"; shift 2 ;;
            --location) location="$2"; shift 2 ;;
            --attendees) attendees="$2"; shift 2 ;;
            --skip_attendees) skip_attendees="$2"; shift 2 ;;
            --op_mode) op_mode="$2"; shift 2 ;;
            --op_start_time) op_start_time="$2"; shift 2 ;;
            --is_repeat) is_repeat="$2"; shift 2 ;;
            --repeat_type) repeat_type="$2"; shift 2 ;;
            --repeat_until) repeat_until="$2"; shift 2 ;;
            --is_custom_repeat) is_custom_repeat="$2"; shift 2 ;;
            --repeat_interval) repeat_interval="$2"; shift 2 ;;
            --repeat_day_of_week) repeat_day_of_week="$2"; shift 2 ;;
            --repeat_day_of_month) repeat_day_of_month="$2"; shift 2 ;;
            --timezone) timezone="$2"; shift 2 ;;
            --is_remind) is_remind="$2"; shift 2 ;;
            --remind_before_event_secs) remind_before_event_secs="$2"; shift 2 ;;
            --remind_time_diffs) remind_time_diffs="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [ -z "$schedule_id" ] || [ -z "$start" ] || [ -z "$end" ]; then
        echo "❌ 缺少必要参数: --schedule_id, --start, --end" >&2
        exit 1
    fi
    
    # 转换时间为时间戳 (macOS 兼容)
    local start_ts=$(date -j -f "%Y-%m-%d %H:%M" "$start" +%s 2>/dev/null || echo "")
    local end_ts=$(date -j -f "%Y-%m-%d %H:%M" "$end" +%s 2>/dev/null || echo "")
    
    if [ -z "$start_ts" ] || [ -z "$end_ts" ]; then
        echo "❌ 时间格式错误，请使用: 2025-01-15 14:00" >&2
        exit 1
    fi
    
    
    # 获取原有日程信息（用于保留未提供的字段）
    local original_schedule=$(_api_call "POST" "/cgi-bin/oa/schedule/get" "{\"schedule_id_list\": [\"${schedule_id}\"]}")
    
    # 如果未提供title/desc/location，从原日程获取
    if [ -z "$title" ]; then
        title=$(echo "$original_schedule" | grep -o '"summary":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    if [ -z "$desc" ]; then
        desc=$(echo "$original_schedule" | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    if [ -z "$location" ]; then
        location=$(echo "$original_schedule" | grep -o '"location":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    # 构建 schedule 对象内的字段
    local schedule_fields="\"schedule_id\": \"${schedule_id}\", \"start_time\": ${start_ts}, \"end_time\": ${end_ts}"
    
    if [ -n "$title" ]; then
        schedule_fields="${schedule_fields}, \"summary\": \"${title}\""
    fi
    
    if [ -n "$desc" ]; then
        schedule_fields="${schedule_fields}, \"description\": \"${desc}\""
    fi
    
    if [ -n "$location" ]; then
        schedule_fields="${schedule_fields}, \"location\": \"${location}\""
    fi
    
    # 构建参与者数组
    if [ -n "$attendees" ] && [ "$skip_attendees" != "1" ]; then
        local attendees_array=""
        IFS=',' read -ra attendee_list <<< "$attendees"
        for user in "${attendee_list[@]}"; do
            user=$(echo "$user" | xargs)
            if [ -n "$user" ]; then
                if [ -n "$attendees_array" ]; then
                    attendees_array="${attendees_array},"
                fi
                attendees_array="${attendees_array}{\"userid\":\"${user}\"}"
            fi
        done
        schedule_fields="${schedule_fields}, \"attendees\": [${attendees_array}]"
    fi
    
    # 构建 reminders 对象
    local reminders_fields=""
    
    # 从原日程获取提醒设置
    local orig_is_remind=$(echo "$original_schedule" | grep -o '"is_remind":[0-9]*' | head -1 | cut -d':' -f2)
    local orig_remind_before=$(echo "$original_schedule" | grep -o '"remind_before_event_secs":[0-9]*' | head -1 | cut -d':' -f2)
    
    # 使用新值或保留原值
    if [ -n "$is_remind" ]; then
        reminders_fields="\"is_remind\": ${is_remind}"
    elif [ -n "$orig_is_remind" ]; then
        reminders_fields="\"is_remind\": ${orig_is_remind}"
    else
        reminders_fields="\"is_remind\": 1"
    fi
    
    if [ -n "$remind_before_event_secs" ]; then
        reminders_fields="${reminders_fields}, \"remind_before_event_secs\": ${remind_before_event_secs}"
    elif [ -n "$orig_remind_before" ]; then
        reminders_fields="${reminders_fields}, \"remind_before_event_secs\": ${orig_remind_before}"
    fi
    
    if [ -n "$remind_time_diffs" ]; then
        local diffs_array=""
        IFS=',' read -ra diff_list <<< "$remind_time_diffs"
        for diff in "${diff_list[@]}"; do
            diff=$(echo "$diff" | xargs)
            if [ -n "$diff" ]; then
                if [ -n "$diffs_array" ]; then
                    diffs_array="${diffs_array},"
                fi
                diffs_array="${diffs_array}${diff}"
            fi
        done
        reminders_fields="${reminders_fields}, \"remind_time_diffs\": [${diffs_array}]"
    fi
    
    # 构建重复日程参数
    if [ -n "$is_repeat" ]; then
        reminders_fields="${reminders_fields}, \"is_repeat\": ${is_repeat}"
        
        if [ "$is_repeat" = "1" ]; then
            if [ -n "$repeat_type" ]; then
                reminders_fields="${reminders_fields}, \"repeat_type\": ${repeat_type}"
            fi
            
            if [ -n "$repeat_until" ]; then
                local repeat_until_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$repeat_until 23:59:59" +%s 2>/dev/null || echo "")
                if [ -n "$repeat_until_ts" ]; then
                    reminders_fields="${reminders_fields}, \"repeat_until\": ${repeat_until_ts}"
                fi
            fi
            
            if [ -n "$is_custom_repeat" ]; then
                reminders_fields="${reminders_fields}, \"is_custom_repeat\": ${is_custom_repeat}"
                
                if [ "$is_custom_repeat" = "1" ]; then
                    if [ -n "$repeat_interval" ]; then
                        reminders_fields="${reminders_fields}, \"repeat_interval\": ${repeat_interval}"
                    fi
                    
                    if [ -n "$repeat_day_of_week" ]; then
                        local week_array=""
                        IFS=',' read -ra week_list <<< "$repeat_day_of_week"
                        for day in "${week_list[@]}"; do
                            day=$(echo "$day" | xargs)
                            if [ -n "$day" ]; then
                                if [ -n "$week_array" ]; then
                                    week_array="${week_array},"
                                fi
                                week_array="${week_array}${day}"
                            fi
                        done
                        reminders_fields="${reminders_fields}, \"repeat_day_of_week\": [${week_array}]"
                    fi
                    
                    if [ -n "$repeat_day_of_month" ]; then
                        local month_array=""
                        IFS=',' read -ra month_list <<< "$repeat_day_of_month"
                        for day in "${month_list[@]}"; do
                            day=$(echo "$day" | xargs)
                            if [ -n "$day" ]; then
                                if [ -n "$month_array" ]; then
                                    month_array="${month_array},"
                                fi
                                month_array="${month_array}${day}"
                            fi
                        done
                        reminders_fields="${reminders_fields}, \"repeat_day_of_month\": [${month_array}]"
                    fi
                fi
            fi
            
            if [ -n "$timezone" ]; then
                reminders_fields="${reminders_fields}, \"timezone\": ${timezone}"
            else
                reminders_fields="${reminders_fields}, \"timezone\": 8"
            fi
        fi
    fi
    
    # 添加 reminders 到 schedule_fields
    if [ -n "$reminders_fields" ]; then
        schedule_fields="${schedule_fields}, \"reminders\": {${reminders_fields}}"
    fi
    
    # 构建完整请求体
    local json="{\"skip_attendees\": ${skip_attendees}, \"schedule\": {${schedule_fields}}}"
    
    # 添加可选参数
    if [ -n "$op_mode" ]; then
        json="${json%,}, \"op_mode\": ${op_mode}"
    fi
    
    if [ -n "$op_start_time" ]; then
        json="${json%,}, \"op_start_time\": ${op_start_time}"
    fi
    
    _api_call "POST" "/cgi-bin/oa/schedule/update" "$json"
}

# 主命令处理
case "$1" in
    create-calendar)
        if [ -z "$2" ]; then
            echo "用法: $0 create-calendar \"日历名称\" [\"描述\"]"
            exit 1
        fi
        create_calendar "$2" "$3"
        ;;
        
    list-calendars|list-cals)
        echo "📅 config.json 中保存的日历列表:"
        if [ -z "$CALENDARS_JSON" ] || [ "$CALENDARS_JSON" = "null" ] || [ "$CALENDARS_JSON" = "{}" ]; then
            echo "  （无）"
        else
            echo "$CALENDARS_JSON" | jq -r 'to_entries[] | "  [\(.key)] \(.value.name) — \(.value.description // "")"'
        fi
        echo ""
        echo "默认日历: $(get_default_cal_id)"
        ;;

    get-calendar)
        if [ -z "$2" ]; then
            echo "用法: $0 get-calendar \"cal_id1\" [\"cal_id2\" ...]" >&2
            echo "示例: $0 get-calendar \"$(get_default_cal_id)\"" >&2
            exit 1
        fi
        echo "📅 获取日历详情..." >&2
        get_calendar_details "$@"
        ;;

    create)
        shift
        echo "📝 创建日程..."
        create_schedule "$@"
        ;;
        
    list-cal)
        if [ -z "$2" ]; then
            echo "用法: $0 list-cal \"cal_id\" [\"开始日期\" \"结束日期\"]"
            echo "示例: $0 list-cal \"$(get_default_cal_id)\" \"\$DATE_TODAY\" \"\$DATE_TODAY\""
            exit 1
        fi
        echo "📅 查询日历日程..."
        get_schedules_by_calendar "$2" "$3" "$4"
        ;;
        
    remove-calendar)
        if [ -z "$2" ]; then
            echo "用法: $0 remove-calendar \"cal_id\""
            echo "从 config.json 中移除日历记录（不影响企业微信实际日历）"
            exit 1
        fi
        local remove_id="$2"
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "❌ 配置文件不存在" >&2
            exit 1
        fi
        local existing=$(jq -r '.wecom.calendars // {}' "$CONFIG_FILE")
        local exists=$(echo "$existing" | jq -r "has(\"$remove_id\")")
        if [ "$exists" != "true" ]; then
            echo "❌ config.json 中未找到日历: $remove_id" >&2
            exit 1
        fi
        local new_calendars=$(echo "$existing" | jq --argjson id "$remove_id" 'del(.[$id])')
        jq --argjson calendars "$new_calendars" \
            '.wecom.calendars = $calendars' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && \
            mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "✅ 已从 config.json 移除日历: $remove_id"
        ;;
        
    get)
        if [ -z "$2" ]; then
            echo "用法: $0 get \"schedule_id\""
            exit 1
        fi
        echo "📅 获取日程详情..."
        get_schedule "$2"
        ;;
        
    list-user)
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            echo "用法: $0 list-user \"userid\" \"开始日期\" \"结束日期\""
            echo "示例: $0 list-user \"\${USER_X}\" \"\$DATE_TODAY\" \"\$DATE_TODAY\""
            exit 1
        fi
        echo "📅 查询用户日程..."
        result=$(get_user_schedules "$2" "$3" "$4")
        echo "$result"
        ;;
        
    add-attendees)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "用法: $0 add-attendees \"schedule_id\" \"user1\" [\"user2\" ...]"
            exit 1
        fi
        sid="$2"
        shift 2
        echo "👥 添加参与者..."
        add_attendees "$sid" "$@"
        ;;
        
    delete|cancel)
        if [ -z "$2" ]; then
            echo "用法: $0 delete \"schedule_id\""
            exit 1
        fi
        echo "🗑️  取消日程..."
        delete_schedule "$2"
        ;;
        
    update)
        shift
        echo "📝 更新日程..."
        update_schedule "$@"
        ;;
        
    *)
        cat <<'EOF'
企业微信日程管理工具

用法:
  create-calendar "名称" ["描述"]     创建日历
  list-calendars                       列出所有日历（已弃用）
  get-calendar "cal_id" [...]          获取日历详情（支持多ID）
  create --title "xxx" --start "xxx" --end "xxx" [--calId "xxx"] [--attendees "user1,user2"] [--admins "admin1,admin2"]
                                       创建日程（attendees第一个成员为发起人，admins必填且最多3人）
                                       重复日程参数：
                                       [--is_repeat 1] [--repeat_type 0|1|2|5|7] [--repeat_until "2025-12-31"]
                                       [--is_custom_repeat 1] [--repeat_interval N]
                                       [--repeat_day_of_week "1,3,5"] [--repeat_day_of_month "1,15"]
  get "schedule_id"                    获取日程详情
  list-cal "cal_id" ["开始日期" "结束日期"]  查询日历日程
  list-user "userid" "开始日期" "结束日期"  查询用户日程
  add-attendees "schedule_id" "user1" ["user2" ...]
                                       添加参与者
  delete "schedule_id"                 取消/删除日程
  update --schedule_id "xxx" --start "xxx" --end "xxx" [--title "xxx"] [--description "xxx"] [--location "xxx"] [--skip_attendees 1] [--op_mode 0|1|2]
                                       更新日程
                                       重复日程修改模式：
                                       --op_mode 0: 修改全部周期（默认）
                                       --op_mode 1: 仅修改此日程
                                       --op_mode 2: 修改将来的所有日程
                                       --op_start_time: 操作起始时间（Unix时间戳）

重复类型说明:
  0 - 每日重复
  1 - 每周重复
  2 - 每月重复
  5 - 每年重复
  7 - 工作日重复

示例:
  ./wecom-schedule.sh create-calendar "团队日历" "用于团队会议"
  # 创建日程（attendees第一个成员为发起人，admins为必填管理员）
  # 日历创建后自动保存到 config.json，无需手动记录
  # 默认取 calendars 中的第一个日历作为默认日历
  
  ./wecom-schedule.sh list-cals
  # 查看所有已保存的日历及默认日历

  ./wecom-schedule.sh create --title "周会" --start "$DATE_TODAY 14:00" --end "$DATE_TODAY 15:00" --attendees "${USER_CREATOR}" --admins "${USER_CREATOR}"
  # 群聊场景：attendees第一个成员为群主/@机器人的用户，admins为其本人
  # 私聊场景：attendees第一个成员为当前私聊用户，admins为其本人
  ./wecom-schedule.sh create --title "周会" --start "$DATE_TODAY 14:00" --end "$DATE_TODAY 15:00" --attendees "${USER_CREATOR}" --admins "${USER_CREATOR}"
  # USER_X, USER_Y 示例：user1,user2
  ./wecom-schedule.sh create --title "评审会" --start "$DATE_TODAY 14:00" --end "$DATE_TODAY 15:00" --attendees "${USER_CREATOR},${USER_X},${USER_Y}" --admins "${USER_CREATOR}"
  
  # 创建每周三重复的会议
  ./wecom-schedule.sh create --title "周例会" --start "$DATE_TODAY 14:00" --end "$DATE_TODAY 15:00" \
    --attendees "${USER_CREATOR}" --admins "${USER_CREATOR}" \
    --is_repeat 1 --repeat_type 1 --is_custom_repeat 1 --repeat_day_of_week "3" --repeat_until "$DATE_FUTURE"
  
  # 创建工作日每天重复的提醒
  ./wecom-schedule.sh create --title "日报提醒" --start "$DATE_TODAY 18:00" --end "$DATE_TODAY 18:30" \
    --attendees "${USER_CREATOR}" --admins "${USER_CREATOR}" \
    --is_repeat 1 --repeat_type 7
  
  ./wecom-schedule.sh list-cal "$(./wecom-schedule.sh list-cals | grep '^默认' | grep -o '\[.*\]' | tr -d '[]')" "$DATE_TODAY" "$DATE_TODAY"
  ./wecom-schedule.sh list-user "${USER_X}" "$DATE_TODAY" "$DATE_TODAY"
  ./wecom-schedule.sh update --schedule_id "xxx" --start "$DATE_TOMORROW 16:00" --end "$DATE_TOMORROW 17:00" --title "新标题"
  
  # 仅修改重复日程的这一次
  ./wecom-schedule.sh update --schedule_id "xxx" --start "$DATE_TOMORROW 15:00" --end "$DATE_TOMORROW 16:00" \
    --op_mode 1 --op_start_time 1737003600
    
  # 从 config.json 移除日历记录（不影响企业微信实际日历）
  ./wecom-schedule.sh remove-calendar "cal_id_xxx"
EOF
        ;;
esac
