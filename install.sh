#!/bin/bash
#
# Cloudflare 优选 IP 一键配置脚本
# 用法: wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO="su8023/cf-auto-speed-test"
INSTALL_DIR="/opt/cf-auto-speed-test"
GITHUB_RAW="https://raw.githubusercontent.com/${REPO}/main"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"

# ── 颜色函数 ──────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
echo_step() { echo -e "${CYAN}▶ $1${NC}"; }

# ── 环境依赖 ──────────────────────────────────────
check_deps() {
    info "检查环境依赖..."
    MISSING=""
    for cmd in curl wget git unzip jq python3; do
        if ! command -v "$cmd" &>/dev/null; then
            MISSING="$MISSING $cmd"
        fi
    done
    if [ -n "$MISSING" ]; then
        echo ""
        warn "检测到缺失依赖:$MISSING"
        echo -n "是否自动安装？ [Y/n]: "
        read -n 1 -r; echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            error "依赖缺失，无法继续。请手动安装: apt-get install -y $MISSING"
            exit 1
        fi
        echo_step "安装缺失依赖..."
        apt-get update -qq
        apt-get install -y -qq $MISSING
        success "依赖安装完成"
    else
        success "环境依赖检查通过 ✓"
    fi
}

# ── 检查 root ─────────────────────────────────────
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用 root 权限运行 (sudo bash install.sh)"
        exit 1
    fi
}

# ── 检测系统 ─────────────────────────────────────
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
        VER="$VERSION_ID"
    else
        OS="unknown"
        VER="unknown"
    fi
    info "检测系统: $OS $VER"
}

# ── 测速地址列表 ──────────────────────────────────
show_speedtest_addresses() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  可选测速地址列表（Cloudflare 数据中心）${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  [亚洲]"
    echo "   1) HK  香港     7) TW  台湾     13) PH  菲律宾"
    echo "   2) JP  日本     8) TH  泰国    14) VN  越南"
    echo "   3) KR  韩国     9) MY  马来西亚 15) ID  印尼"
    echo "   4) SG  新加坡  10) IN  印度"
    echo "                  11) JP2 日本大阪"
    echo ""
    echo "  [欧美]"
    echo "  16) US  美国    18) DE  德国    20) FR  法国"
    echo "  17) UK  英国    19) NL  荷兰    21) IT  意大利"
    echo "  22) ES  西班牙  23) PL  波兰    24) SE  瑞典"
    echo ""
    echo "  [其他]"
    echo "  25) AU  澳洲    27) BR  巴西"
    echo "  26) CA  加拿大  28) ZA  南非"
    echo ""
    echo -e "  ${YELLOW}0) 全部地区（亚洲+欧美+其他，全部跑一遍）${NC}"
    echo ""
}

# ── 解析测速编号 → 地区代码列表 ──────────────────
parse_speedtest_choices() {
    local choices="$1"
    local result=""

    # 全部
    if [[ "$choices" == *"0"* ]]; then
        echo "HK JP JP2 KR SG TW TH MY PH VN ID IN US UK DE NL FR IT ES PL SE AU CA BR ZA"
        return
    fi

    # 逐个解析
    for ch in $choices; do
        case $ch in
            1)  result="$result HK" ;;
            2)  result="$result JP" ;;
            3)  result="$result KR" ;;
            4)  result="$result SG" ;;
            5)  result="$result US" ;;
            6)  result="$result TW" ;;
            7)  result="$result TW" ;;
            8)  result="$result TH" ;;
            9)  result="$result MY" ;;
            10) result="$result IN" ;;
            11) result="$result JP2" ;;
            12) result="$result PH" ;;
            13) result="$result PH" ;;
            14) result="$result VN" ;;
            15) result="$result ID" ;;
            16) result="$result US" ;;
            17) result="$result UK" ;;
            18) result="$result DE" ;;
            19) result="$result NL" ;;
            20) result="$result FR" ;;
            21) result="$result IT" ;;
            22) result="$result ES" ;;
            23) result="$result PL" ;;
            24) result="$result SE" ;;
            25) result="$result AU" ;;
            26) result="$result CA" ;;
            27) result="$result BR" ;;
            28) result="$result ZA" ;;
        esac
    done

    echo "$result" | tr -s ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/^ //;s/ $//'
}

# ── 选择测速地区 ──────────────────────────────────
select_speedtest_areas() {
    show_speedtest_addresses

    local default="1"
    echo -n "请输入测速地区编号（支持多选如 1 2 3，默认: $default）: "
    read choices
    choices="${choices:-$default}"

    # 验证输入
    for ch in $choices; do
        if ! [[ "$ch" =~ ^[0-9]+$ ]] || [ "$ch" -gt 28 ]; then
            error "无效编号: $ch，请输入 0~28"
            exit 1
        fi
    done

    SPEEDTEST_AREAS=$(parse_speedtest_choices "$choices")
    success "已选择测速地区: $SPEEDTEST_AREAS"
}

# ── 下载最新版本 ──────────────────────────────────
download_latest() {
    info "下载最新版本..."

    if [ -d "$INSTALL_DIR" ]; then
        warn "检测到已有安装，是否更新？"
        read -p "输入 y 更新，n 退出: " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "退出安装"
            exit 0
        fi
        rm -rf "$INSTALL_DIR"
    fi

    mkdir -p "$INSTALL_DIR"

    info "下载脚本文件..."
    for file in speed_AIO.sh speed.sh CDNDomainUpdate.sh Domain2IP.py RemoveCFIPs.py app_dashboard.py config.conf; do
        info "  下载 $file..."
        wget -q -O "$INSTALL_DIR/$file" "${GITHUB_RAW}/${file}" || {
            error "$file 下载失败"
            exit 1
        }
    done

    chmod +x "$INSTALL_DIR"/*.sh
    success "下载完成 → $INSTALL_DIR"
}

# ── 交互式配置 ───────────────────────────────────
interactive_config() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Cloudflare 优选 IP 配置向导${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"

    CONFIG_FILE="$INSTALL_DIR/config.conf"

    # CloudFlare 邮箱
    default_email=$(grep -oP '(?<=auth_email=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "")
    echo ""
    echo -n "  CloudFlare 邮箱 [${default_email}]: "
    read auth_email
    auth_email="${auth_email:-$default_email}"

    # CloudFlare Key
    default_key=$(grep -oP '(?<=auth_key=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "")
    echo -n "  CloudFlare API Key [输入回车保留上次的]: "
    read -s auth_key; echo
    if [ -z "$auth_key" ]; then
        auth_key="$default_key"
    fi

    if [ -z "$auth_key" ] || [ -z "$auth_email" ]; then
        error "CloudFlare 邮箱和 API Key 不能为空"
        exit 1
    fi

    # 主域名
    default_zone=$(grep -oP '(?<=zone_name=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "")
    echo -n "  主域名 (例: example.com) [${default_zone}]: "
    read zone_name
    zone_name="${zone_name:-$default_zone}"

    if [ -z "$zone_name" ]; then
        error "主域名不能为空"
        exit 1
    fi

    # 测速地区选择
    select_speedtest_areas

    # 端口
    echo ""
    echo -n "  测速端口 (默认: 443): "
    read port
    port="${port:-443}"

    # IP 数量
    echo -n "  每个地区优选 IP 数量 (默认: 4): "
    read ips
    ips="${ips:-4}"

    # 飞书 Webhook
    echo ""
    echo -n "  飞书 Webhook URL (留空跳过): "
    read feishu_webhook

    # GitHub IP 库
    default_githubID=$(grep -oP '(?<=githubID=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "ansoncloud8")
    echo -n "  GitHub IP 库 ID [${default_githubID}]: "
    read githubID
    githubID="${githubID:-$default_githubID}"

    # 写配置文件
    info "生成配置文件..."
    cat > "$CONFIG_FILE" << EOF
# Cloudflare API Configuration
auth_email="${auth_email}"
auth_key="${auth_key}"
zone_name="${zone_name}"

# GitHub IP Library
githubID="${githubID}"

# Feishu Webhook Notification (leave empty to disable)
feishu_webhook="${feishu_webhook}"

# Telegram Notification (leave empty to disable)
telegramBotToken=""
telegramBotUserId=""
telegramBotAPI=""

# Proxy for GitHub (leave empty to disable)
proxygithub="https://mirror.ghproxy.com/"
EOF

    success "配置文件已保存"
    # 保存测速地区供后续使用
    echo "SPEEDTEST_AREAS=\"$SPEEDTEST_AREAS\"" >> "$CONFIG_FILE"
    echo "PORT=$port" >> "$CONFIG_FILE"
    echo "IP_COUNT=$ips" >> "$CONFIG_FILE"
}

# ── 快速配置 ─────────────────────────────────────
quick_config() {
    info "快速配置模式..."

    CONFIG_FILE="$INSTALL_DIR/config.conf"

    auth_email=$(grep -oP '(?<=auth_email=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "")
    auth_key=$(grep -oP '(?<=auth_key=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "")
    zone_name=$(grep -oP '(?<=zone_name=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "")

    if [ -z "$auth_email" ] || [ -z "$auth_key" ] || [ -z "$zone_name" ]; then
        warn "配置文件不完整，进入交互模式..."
        interactive_config
        return
    fi

    info "使用已有配置"
    info "  域名: $zone_name"
    info "  邮箱: $auth_email"

    # 读取保存的测速参数
    SPEEDTEST_AREAS=$(grep -oP '(?<=SPEEDTEST_AREAS=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "HK")
    PORT=$(grep -oP '(?<=^PORT=)[0-9]+' "$CONFIG_FILE" 2>/dev/null || echo "443")
    IPS=$(grep -oP '(?<=^IP_COUNT=)[0-9]+' "$CONFIG_FILE" 2>/dev/null || echo "4")
}

# ── 验证 CloudFlare 配置 ──────────────────────────
verify_cf_config() {
    info "验证 CloudFlare 配置..."

    auth_email=$(grep -oP '(?<=auth_email=")[^"]*' "$CONFIG_FILE")
    auth_key=$(grep -oP '(?<=auth_key=")[^"]*' "$CONFIG_FILE")
    zone_name=$(grep -oP '(?<=zone_name=")[^"]*' "$CONFIG_FILE")

    zone_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
        -H "X-Auth-Email: $auth_email" \
        -H "X-Auth-Key: $auth_key" \
        -H "Content-Type: application/json")

    success_flag=$(echo "$zone_response" | grep -o '"success":true' || echo "")
    if [ -z "$success_flag" ]; then
        error "CloudFlare 验证失败！请检查 auth_email / auth_key / zone_name"
        info "提示: zone_name 应该是主域名如 example.com，不是子域名"
        return 1
    fi

    zone_id=$(echo "$zone_response" | grep -oP '(?<="id":")[a-f0-9]{32}' | head -1)
    success "CloudFlare 验证通过 (Zone ID: ${zone_id:0:8}...)"
    return 0
}

# ── 测试运行 ──────────────────────────────────────
test_run() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  开始测速${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""

    cd "$INSTALL_DIR"

    # 从配置读取，没有则用默认值
    SPEEDTEST_AREAS="${SPEEDTEST_AREAS:-HK}"
    PORT="${PORT:-443}"
    IPS="${IPS:-4}"
    zone_name=$(grep -oP '(?<=zone_name=")[^"]*' config.conf)

    info "测速地区: $SPEEDTEST_AREAS"
    info "测速端口: $PORT"
    info "每地区IP数: $IPS"
    info "按 Ctrl+C 中途退出..."
    echo ""

    for area in $SPEEDTEST_AREAS; do
        echo -e "${YELLOW}── 测速地区: $area ──${NC}"
        timeout 90 ./speed_AIO.sh ${area,,} $PORT $IPS ${zone_name} || {
            exit_code=$?
            if [ $exit_code -eq 124 ]; then
                warn "$area 测速超时 (90秒)，正常——等待下一地区"
            else
                warn "$area 退出码: $exit_code"
            fi
        }
        echo ""
    done

    success "全部测速完成"
}

# ── 启动 Web 面板 ────────────────────────────────
start_dashboard() {
    info "启动 Web 测速面板..."

    cd "$INSTALL_DIR"

    if ss -tlnp 2>/dev/null | grep -q ':5001'; then
        warn "端口 5001 已被占用，尝试 5002"
        PORT=5002
    else
        PORT=5001
    fi

    nohup python3 app_dashboard.py --port $PORT > /var/log/cf-dashboard.log 2>&1 &

    sleep 2

    if ss -tlnp 2>/dev/null | grep -q ":$PORT"; then
        local ip=$(curl -s 4.ipw.cn 2>/dev/null || hostname -I | awk '{print $1}')
        success "Web 面板已启动 → http://${ip}:${PORT}"
        info "日志: /var/log/cf-dashboard.log"
    else
        error "启动失败，查看日志: /var/log/cf-dashboard.log"
    fi
}

# ── 设置定时任务 ──────────────────────────────────
setup_cron() {
    info "设置定时任务..."

    zone_name=$(grep -oP '(?<=zone_name=")[^"]*' "$INSTALL_DIR/config.conf")
    PORT="${PORT:-443}"
    IPS="${IPS:-4}"
    SPEEDTEST_AREAS="${SPEEDTEST_AREAS:-HK}"

    # 定时任务只跑第一个地区，完整测速建议手动
    first_area=$(echo $SPEEDTEST_AREAS | awk '{print $1}')
    cron_cmd="cd $INSTALL_DIR && ./speed_AIO.sh ${first_area,,} $PORT $IPS ${zone_name}"

    crontab -l 2>/dev/null | grep -v "cf-auto-speed-test" | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "0 6 * * * $cron_cmd # cf-auto-speed-test") | crontab -

    success "定时任务已设置 (每天 06:00 运行，地区: $first_area)"
    info "当前 crontab:"
    crontab -l 2>/dev/null | grep "cf-auto-speed-test" || info "无"
}

# ── 卸载 ─────────────────────────────────────────
uninstall() {
    warn "确定要卸载吗？"
    read -p "输入 y 确认: " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "取消卸载"
        return
    fi

    crontab -l 2>/dev/null | grep -v "cf-auto-speed-test" | crontab - 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    pkill -f "app_dashboard.py" 2>/dev/null || true
    success "卸载完成"
}

# ── Banner ────────────────────────────────────────
show_banner() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Cloudflare 优选 IP 一键配置脚本        ║${NC}"
    echo -e "${BLUE}║  cf-auto-speed-test by su8023           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

# ── 使用说明 ──────────────────────────────────────
usage() {
    show_banner
    echo "用法:"
    echo "  wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash"
    echo ""
    echo "选项:"
    echo "  --config      重新配置（可重新选择测速地区）"
    echo "  --test        测试运行"
    echo "  --dashboard   启动 Web 面板"
    echo "  --cron        设置定时任务"
    echo "  --verify      验证 CloudFlare 配置"
    echo "  --uninstall   卸载"
    echo ""
    echo "示例:"
    echo "  # 一键安装+配置"
    echo "  wget -qO- .../install.sh | bash"
    echo ""
    echo "  # 重新配置测速地区"
    echo "  wget -qO- .../install.sh | bash -s -- --config"
    echo ""
    echo "  # 启动面板"
    echo "  wget -qO- .../install.sh | bash -s -- --dashboard"
    echo ""
}

# ── 主流程 ────────────────────────────────────────
main() {
    check_root
    detect_os
    check_deps          # <-- 核心新增：先检测依赖再继续

    case "${1:-}" in
        --config)
            if [ ! -d "$INSTALL_DIR" ]; then
                download_latest
            fi
            interactive_config
            verify_cf_config
            ;;
        --test)
            quick_config
            test_run
            ;;
        --dashboard)
            quick_config
            start_dashboard
            ;;
        --cron)
            quick_config
            setup_cron
            ;;
        --verify)
            quick_config
            verify_cf_config
            ;;
        --uninstall)
            uninstall
            ;;
        "")
            show_banner
            download_latest
            interactive_config
            verify_cf_config
            echo ""
            echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}  安装完成！${NC}"
            echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
            echo ""
            echo "  安装目录: $INSTALL_DIR"
            echo ""
            echo "  下一步操作:"
            echo "    1) 测试运行   → $(basename $0) --test"
            echo "    2) Web 面板   → $(basename $0) --dashboard"
            echo "    3) 定时任务   → $(basename $0) --cron"
            echo "    4) 重新配置   → $(basename $0) --config"
            echo ""
            read -p "  是否立即测速？ [y/N]: " -n 1 -r; echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                test_run
            fi
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
