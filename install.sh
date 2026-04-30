#!/bin/bash
#
# Cloudflare 优选 IP 一键配置脚本
# 用法: wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash
#
# 或一键安装+运行:
# wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash -s -- --run
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO="su8023/cf-auto-speed-test"
INSTALL_DIR="/opt/cf-auto-speed-test"
GITHUB_RAW="https://raw.githubusercontent.com/${REPO}/main"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"

# 颜色函数
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用 root 权限运行 (sudo bash install.sh)"
        exit 1
    fi
}

# 检测系统
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

# 检查依赖
check_deps() {
    info "检查依赖..."
    MISSING=""
    for cmd in curl wget git unzip jq python3; do
        if ! command -v "$cmd" &>/dev/null; then
            MISSING="$MISSING $cmd"
        fi
    done
    if [ -n "$MISSING" ]; then
        info "安装缺失依赖:$MISSING"
        apt-get update -qq
        apt-get install -y -qq $MISSING
        success "依赖安装完成"
    else
        success "依赖检查通过"
    fi
}

# 下载最新版本
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
    
    # 下载核心文件
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

# 获取最新 release 版本号
get_latest_version() {
    TAG=$(curl -s "$GITHUB_API" | grep '"tag_name"' | sed 's/.*"tag_name": "//' | sed 's/",//')
    echo "${TAG:-latest}"
}

# 交互式配置
interactive_config() {
    echo ""
    info "=========================================="
    info "   Cloudflare 优选 IP 配置向导"
    info "=========================================="
    echo ""
    
    CONFIG_FILE="$INSTALL_DIR/config.conf"
    
    # CloudFlare 邮箱
    default_email=$(grep -oP '(?<=auth_email=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "")
    echo -n "CloudFlare 邮箱 [${default_email}]: "
    read auth_email
    auth_email="${auth_email:-$default_email}"
    
    # CloudFlare Key
    default_key=$(grep -oP '(?<=auth_key=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "")
    echo -n "CloudFlare API Key [输入回车保留上次的]: "
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
    echo -n "主域名 (例: example.com) [${default_zone}]: "
    read zone_name
    zone_name="${zone_name:-$default_zone}"
    
    if [ -z "$zone_name" ]; then
        error "主域名不能为空"
        exit 1
    fi
    
    # 测速地区
    echo ""
    info "选择测速地区 (多个用空格分隔):"
    echo "  1) HK  香港"
    echo "  2) JP  日本"
    echo "  3) KR  韩国"
    echo "  4) SG  新加坡"
    echo "  5) US  美国"
    echo "  6) TW  台湾"
    echo "  7) 自定义"
    echo -n "请输入编号 (默认: 1): "
    read area_choice
    area_choice="${area_choice:-1}"
    
    case $area_choice in
        1) area_list="HK" ;;
        2) area_list="JP" ;;
        3) area_list="KR" ;;
        4) area_list="SG" ;;
        5) area_list="US" ;;
        6) area_list="TW" ;;
        7) echo -n "输入国家代码 (如: HK JP KR): "; read area_list ;;
        *) area_list="HK" ;;
    esac
    
    # 端口
    echo ""
    echo -n "测速端口 (默认: 443): "
    read port
    port="${port:-443}"
    
    # IP 数量
    echo -n "每个地区优选 IP 数量 (默认: 4): "
    read ips
    ips="${ips:-4}"
    
    # 飞书 Webhook
    echo ""
    echo -n "飞书 Webhook URL (留空跳过): "
    read feishu_webhook
    
    # GitHub IP 库
    default_githubID=$(grep -oP '(?<=githubID=")[^"]*' "$CONFIG_FILE" 2>/dev/null || echo "ansoncloud8")
    echo -n "GitHub IP 库 ID [${default_githubID}]: "
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
}

# 快速配置（只修改必要项）
quick_config() {
    info "快速配置模式..."
    
    CONFIG_FILE="$INSTALL_DIR/config.conf"
    
    # 读取已有配置
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
}

# 验证 CloudFlare 配置
verify_cf_config() {
    info "验证 CloudFlare 配置..."
    
    auth_email=$(grep -oP '(?<=auth_email=")[^"]*' "$CONFIG_FILE")
    auth_key=$(grep -oP '(?<=auth_key=")[^"]*' "$CONFIG_FILE")
    zone_name=$(grep -oP '(?<=zone_name=")[^"]*' "$CONFIG_FILE")
    
    # 获取 zone_id
    zone_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
        -H "X-Auth-Email: $auth_email" \
        -H "X-Auth-Key: $auth_key" \
        -H "Content-Type: application/json")
    
    success_flag=$(echo "$zone_response" | grep -o '"success":true' || echo "")
    if [ -z "$success_flag" ]; then
        error "CloudFlare 验证失败！请检查 auth_email / auth_key / zone_name 是否正确"
        info "提示: zone_name 应该是主域名如 example.com，不是子域名"
        return 1
    fi
    
    zone_id=$(echo "$zone_response" | grep -oP '(?<="id":")[a-f0-9]{32}' | head -1)
    success "CloudFlare 验证通过 (Zone ID: ${zone_id:0:8}...)"
    return 0
}

# 测试运行
test_run() {
    echo ""
    info "=========================================="
    info "   开始测试运行"
    info "=========================================="
    echo ""
    
    cd "$INSTALL_DIR"
    
    area_GEC="HK"
    port=443
    ips=4
    zone_name=$(grep -oP '(?<=zone_name=")[^"]*' config.conf)
    
    info "测试命令: ./speed_AIO.sh ${area_GEC,,} $port $ips ${zone_name}"
    info "按 Ctrl+C 中途退出，或等待完成..."
    echo ""
    
    timeout 60 ./speed_AIO.sh ${area_GEC,,} $port $ips ${zone_name} || {
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            warn "测试超时 (60秒)，这是正常的——IP 测速需要几分钟"
        else
            warn "测试退出码: $exit_code"
        fi
    }
    
    success "测试完成"
}

# 启动 Web 面板
start_dashboard() {
    info "启动 Web 测速面板..."
    
    cd "$INSTALL_DIR"
    
    # 检查端口是否占用
    if ss -tlnp 2>/dev/null | grep -q ':5001'; then
        warn "端口 5001 已被占用，尝试其他端口"
        PORT=5002
    else
        PORT=5001
    fi
    
    # 后台启动
    nohup python3 app_dashboard.py --port $PORT > /var/log/cf-dashboard.log 2>&1 &
    
    sleep 2
    
    if ss -tlnp 2>/dev/null | grep -q ":$PORT"; then
        success "Web 面板已启动 → http://$(curl -s 4.ipw.cn 2>/dev/null || hostname -I | awk '{print $1}'):${PORT}"
        info "日志: /var/log/cf-dashboard.log"
    else
        error "启动失败，查看日志: /var/log/cf-dashboard.log"
    fi
}

# 设置定时任务
setup_cron() {
    info "设置定时任务..."
    
    # 获取配置值
    zone_name=$(grep -oP '(?<=zone_name=")[^"]*' "$INSTALL_DIR/config.conf")
    area_GEC="HK"
    port=443
    ips=4
    
    cron_cmd="cd $INSTALL_DIR && ./speed_AIO.sh ${area_GEC,,} $port $ips ${zone_name}"
    
    # 移除旧任务
    crontab -l 2>/dev/null | grep -v "cf-auto-speed-test" | crontab - 2>/dev/null || true
    
    # 添加新任务：每天早上6点运行
    (crontab -l 2>/dev/null; echo "0 6 * * * $cron_cmd # cf-auto-speed-test") | crontab -
    
    success "定时任务已设置 (每天 06:00 运行)"
    info "当前 crontab:"
    crontab -l 2>/dev/null | grep "cf-auto-speed-test" || info "无"
}

# 卸载
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

# 启动脚本
show_banner() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Cloudflare 优选 IP 一键配置脚本        ║${NC}"
    echo -e "${BLUE}║   cf-auto-speed-test by su8023           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
    echo ""
}

# 使用说明
usage() {
    show_banner
    echo "用法:"
    echo "  wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash"
    echo ""
    echo "选项:"
    echo "  --config      重新配置"
    echo "  --test        测试运行"
    echo "  --dashboard   启动 Web 面板"
    echo "  --cron        设置定时任务"
    echo "  --uninstall   卸载"
    echo ""
    echo "示例:"
    echo "  wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash -s -- --dashboard"
    echo ""
}

# 主流程
main() {
    check_root
    detect_os
    check_deps
    
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
        --uninstall)
            uninstall
            ;;
        --verify)
            verify_cf_config
            ;;
        "")
            show_banner
            download_latest
            interactive_config
            verify_cf_config
            echo ""
            info "=========================================="
            info "   安装完成！"
            info "=========================================="
            echo ""
            echo "下一步操作:"
            echo "  1) 测试运行:   cd $INSTALL_DIR && ./speed_AIO.sh hk 443 4 yourdomain.com"
            echo "  2) 启动面板:   $(basename $0) --dashboard"
            echo "  3) 定时任务:   $(basename $0) --cron"
            echo ""
            read -p "是否立即测试运行？ [y/N]: " -n 1 -r; echo
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
