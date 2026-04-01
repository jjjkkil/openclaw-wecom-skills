#!/bin/bash
#
# init-wecom-config.sh - 从 OpenClaw 配置初始化企业微信凭证
#
# 用法: ./scripts/init-wecom-config.sh [account]
#   account: 可选，指定账号 (business/lab/ops)，省略则交互式选择
#
# 依赖: Python3 (用于解析 openclaw.json)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../" && pwd)"
OPENCLAW_CONFIG="${HOME}/.openclaw/openclaw.json"
TARGET_CONFIG="${WORKSPACE_DIR}/config.json"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# 检查 openclaw.json
if [ ! -f "$OPENCLAW_CONFIG" ]; then
    error "未找到 OpenClaw 配置文件: $OPENCLAW_CONFIG"
    exit 1
fi

# 从 openclaw.json 提取配置
extract_config() {
    local account="$1"
    local path="$2"

    python3 - "$OPENCLAW_CONFIG" "$account" "$path" <<'EOF'
import sys, json

config_path = sys.argv[1]
account = sys.argv[2]
key_path = sys.argv[3]  # e.g. "agent.corpId"

with open(config_path) as f:
    config = json.load(f)

try:
    # Navigate nested path like "agent.corpId"
    value = config.get("channels", {}).get("wecom", {}).get("accounts", {}).get(account, {})
    for k in key_path.split("."):
        value = value[k]
    print(value if value is not None else "", end="")
except (KeyError, TypeError):
    print("", end="")
EOF
}

# 获取账号列表
list_accounts() {
    python3 - "$OPENCLAW_CONFIG" <<'EOF'
import sys, json
with open(sys.argv[1]) as f:
    config = json.load(f)
accounts = config.get("channels", {}).get("wecom", {}).get("accounts", {})
for name, info in accounts.items():
    enabled = info.get("enabled", False)
    display = info.get("name", name)
    marker = "" if enabled else " (disabled)"
    print(f"{name}|{display}{marker}")
EOF
}

# 主逻辑
ACCOUNT="$1"

if [ -z "$ACCOUNT" ]; then
    echo ""
    echo "请选择要使用的企业微信账号:"
    echo ""
    while IFS='|' read -r name display rest; do
        echo "  $name  - $display $rest"
    done < <(list_accounts)
    echo ""
    read -p "请输入账号名称 (business/lab/ops): " ACCOUNT
    ACCOUNT="${ACCOUNT:-business}"
fi

# 提取各字段
CORP_ID=$(extract_config "$ACCOUNT" "agent.corpId")
AGENT_ID=$(extract_config "$ACCOUNT" "agent.agentId")
AGENT_SECRET=$(extract_config "$ACCOUNT" "agent.agentSecret")
ACCOUNT_NAME=$(python3 - "$OPENCLAW_CONFIG" "$ACCOUNT" <<'EOF'
import sys, json
with open(sys.argv[1]) as f:
    c = json.load(f)
name = c.get("channels",{}).get("wecom",{}).get("accounts",{}).get(sys.argv[2],{}).get("name","")
print(name)
EOF
)

if [ -z "$CORP_ID" ] || [ -z "$AGENT_SECRET" ]; then
    error "账号 '$ACCOUNT' 未找到或配置不完整"
    exit 1
fi

# 判断是否有 proxy 配置（lab/ops 账号可能没有）
PROXY_URL=$(extract_config "$ACCOUNT" "proxy.url")
if [ -z "$PROXY_URL" ]; then
    warn "未找到代理配置，proxy.url 将留空"
    PROXY_URL=""
fi

# 读取现有的 config.json，看是否有 default_meeting_admin 等自定义字段
MEETING_ADMIN=$(python3 - "$TARGET_CONFIG" 2>/dev/null <<'EOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        c = json.load(f)
    print(c.get("wecom",{}).get("default_meeting_admin",""))
except: print("")
EOF

)
CAL_ID=$(python3 - "$TARGET_CONFIG" 2>/dev/null <<'EOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        c = json.load(f)
    print(c.get("wecom",{}).get("default_calendar_id",""))
except: print("")
EOF
)
ORGANIZER=$(python3 - "$TARGET_CONFIG" 2>/dev/null <<'EOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        c = json.load(f)
    print(c.get("wecom",{}).get("default_organizer",""))
except: print("")
EOF
)
EXISTING_PROXY=$(python3 - "$TARGET_CONFIG" 2>/dev/null <<'EOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        c = json.load(f)
    print(c.get("proxy",{}).get("url",""))
except: print("")
EOF
)

# 写入 config.json
python3 - "$TARGET_CONFIG" <<EOF
import sys, json

config = {
    "wecom": {
        "corp_id": "$CORP_ID",
        "corp_secret": "$AGENT_SECRET",
        "agent_id": str($AGENT_ID),
    },
    "proxy": {}
}

# 保留用户已有的自定义字段
existing = {}
try:
    with open("$TARGET_CONFIG") as f:
        existing = json.load(f)
except: pass

wecom = config.get("wecom", {})
ew = existing.get("wecom", {})

# 合并：保留用户已设置的非敏感字段
for k in ["default_meeting_admin", "default_calendar_id", "default_organizer"]:
    v = ew.get(k, "")
    if v and v not in ("", "YOUR_MEETING_ADMIN_USERID", "YOUR_CALENDAR_ID", "YOUR_DEFAULT_ORGANIZER_USERID"):
        wecom[k] = v
    elif k not in wecom or not wecom.get(k):
        wecom[k] = ""

proxy = config.get("proxy", {})
ep = existing.get("proxy", {})
pu = ep.get("url", "")
if pu and pu not in ("", "YOUR_PROXY_URL", "http://user:password@YOUR_PROXY_IP:PORT"):
    proxy["url"] = pu
elif "$PROXY_URL":
    proxy["url"] = "$PROXY_URL"

config["wecom"] = wecom
config["proxy"] = proxy

with open("$TARGET_CONFIG", "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print("done")
EOF

info "配置文件已写入: $TARGET_CONFIG"
info "账号: $ACCOUNT_NAME ($ACCOUNT)"
info "corp_id: $CORP_ID"
info "agent_id: $AGENT_ID"

if [ -n "$PROXY_URL" ]; then
    info "proxy_url: $PROXY_URL"
else
    warn "proxy_url: 未配置（请手动补充）"
fi

# 提示用户检查自定义字段
if [ -z "$MEETING_ADMIN" ] || [ "$MEETING_ADMIN" = "YOUR_MEETING_ADMIN_USERID" ]; then
    echo ""
    warn "请在 config.json 中补充以下字段（如果需要）:"
    warn "  - default_meeting_admin: 预约会议的默认管理员用户ID"
    warn "  - default_calendar_id:   日程使用的日历ID"
    warn "  - default_organizer:     日程默认发起人用户ID"
fi

echo ""
info "完成!"
