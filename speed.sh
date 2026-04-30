#!/bin/bash
# Cloudflare Auto Speed Test - Standard Version (Single Domain -> Single IP per record)
# Usage: ./speed.sh [area] [port] [count] [domain] [email] [key] [speedurl]
# All configs can be set in config.conf, command line args override config

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"

# Default values
AREA_GEC="hk"
PORT=443
RECORD_COUNT=4
SPEEDTEST_MB=90
SPEED_LOWER=10
LOSS_MAX=0.75
SPEEDQUEUE_MAX=1
CF_IPS=0

# CloudFlare config (from config.conf)
AUTH_EMAIL=""
AUTH_KEY=""
ZONE_NAME=""
GITHUB_ID="ansoncloud8"

# Notification config
FEISHU_WEBHOOK=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_BOT_USER_ID=""
TELEGRAM_BOT_API=""

# Internal vars
PROXY_GITHUB="https://mirror.ghproxy.com/"
CLOUDFLARE_ST_PASSWORD=""
SPEED_URL=""
LOG_DIR="log"
TEMP_DIR="temp"
IP_DIR="ip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load configuration from config.conf
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        set -a
        source "$CONFIG_FILE"
        set +a
    else
        log_warn "Config file $CONFIG_FILE not found, using defaults"
    fi
}

# Parse command line arguments
parse_args() {
    [[ -n "$1" ]] && AREA_GEC="$1"
    [[ -n "$2" ]] && PORT="$2"
    [[ -n "$3" ]] && RECORD_COUNT="$3"
    [[ -n "$4" ]] && ZONE_NAME="$4"
    [[ -n "$5" ]] && AUTH_EMAIL="$5"
    [[ -n "$6" ]] && AUTH_KEY="$6"
    [[ -n "$7" ]] && SPEED_URL="$7"
}

# Detect CPU architecture
detect_arch() {
    case "$(uname -m)" in
        i386|i686) echo "386" ;;
        x86_64|amd64) echo "amd64" ;;
        armv8|arm64|aarch64) echo "arm64" ;;
        s390x) echo "s390x" ;;
        *) log_error "Unsupported CPU architecture!"; exit 1 ;;
    esac
}

# Check and install dependencies
check_dependencies() {
    local deps=(git curl unzip awk jq python3)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log_info "Installing $dep..."
            apt-get update -qq
            apt-get install -y -qq "$dep"
        fi
    done
    
    if ! command -v mmdblookup &>/dev/null; then
        log_info "Installing mmdb-bin..."
        apt-get install -y -qq mmdb-bin geoip-bin
    fi
}

# Download GeoLite2 mmdb
download_geolite_mmdb() {
    local mmdb_path="/usr/share/GeoIP/GeoLite2-Country.mmdb"
    if [[ ! -f "$mmdb_path" ]]; then
        log_info "Downloading GeoLite2-Country.mmdb..."
        mkdir -p /usr/share/GeoIP
        curl -sL "${PROXY_GITHUB}https://github.com/P3TERX/GeoLite.mmdb/releases/download/latest/GeoLite2-Country.mmdb" -o "$mmdb_path" || \
        curl -sL "https://raw.githubusercontent.com/ansoncloud8/am-cf-auto-speed-test/main/GeoLite2-Country.mmdb" -o "$mmdb_path"
    fi
}

# Download CloudflareST tool
download_cloudflarest() {
    if [[ -f "CloudflareST" ]]; then
        log_info "CloudflareST already exists"
        return
    fi
    
    local arch="$(detect_arch)"
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v2.2.4")
    
    log_info "Downloading CloudflareST ${latest_version}..."
    curl -sL "${PROXY_GITHUB}https://github.com/XIU2/CloudflareSpeedTest/releases/download/${latest_version}/CloudflareST_linux_${arch}.tar.gz" -o CloudflareST.tar.gz
    tar -xzf CloudflareST.tar.gz CloudflareST
    rm -f CloudflareST.tar.gz
    chmod +x CloudflareST
}

# Install Python requests module
install_python_deps() {
    if ! python3 -c "import requests" 2>/dev/null; then
        log_info "Installing Python requests module..."
        pip3 install -q requests
    fi
}

# Feishu webhook notification
send_feishu_notification() {
    local message="$1"
    [[ -z "$FEISHU_WEBHOOK" ]] && return 0
    
    log_info "Sending Feishu notification..."
    local payload="{\"msg_type\":\"text\",\"content\":{\"text\":\"$message\"}}"
    curl -s -X POST "$FEISHU_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 20 || log_warn "Feishu notification failed"
}

# Telegram notification
send_telegram_notification() {
    local message="$1"
    [[ -z "$TELEGRAM_BOT_TOKEN" ]] && return 0
    
    local api="${TELEGRAM_BOT_API:-api.telegram.org}"
    local url="https://${api}/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    
    curl -s -X POST "$url" \
        -d "chat_id=${TELEGRAM_BOT_USER_ID}" \
        -d "parse_mode=HTML" \
        -d "text=$message" \
        --max-time 20 || log_warn "Telegram notification failed"
}

# Send notification (both Feishu and Telegram)
send_notification() {
    local message="$1"
    send_feishu_notification "$message"
    send_telegram_notification "$message"
}

# Update IP library from various sources
update_ip_library() {
    log_info "Updating IP library..."
    
    mkdir -p "$TEMP_DIR" "$IP_DIR"
    rm -rf "${TEMP_DIR:?}"/* "${IP_DIR:?}"/* 2>/dev/null || true
    
    # Download from baipiao.eu.org
    log_info "Downloading IP list from baipiao.eu.org..."
    curl -sL "https://zip.baipiao.eu.org" -o txt.zip
    unzip -o txt.zip -d "$TEMP_DIR/temp" 2>/dev/null || true
    mv "$TEMP_DIR/temp"/*-"${PORT}.txt" "$TEMP_DIR/" 2>/dev/null || true
    rm -rf txt.zip "$TEMP_DIR/temp"
    
    # Download hello-earth IP library (port 443 only)
    if [[ "$PORT" -eq 443 ]]; then
        log_info "Updating hello-earth IP library..."
        if git clone -q --depth 1 "${PROXY_GITHUB}https://github.com/hello-earth/cloudflare-better-ip.git" 2>/dev/null; then
            if [[ -d "cloudflare-better-ip/cloudflare" ]] && [[ -n "$(ls -A cloudflare-better-ip/cloudflare)" ]]; then
                cat cloudflare-better-ip/cloudflare/*.txt > cloudflare-better-ip/cloudflare-ip.txt
                awk -F ":443" '{print $1}' cloudflare-better-ip/cloudflare-ip.txt > "$TEMP_DIR/hello-earth-ip.txt"
                log_info "hello-earth IP library updated"
            fi
            rm -rf cloudflare-better-ip
        fi
    fi
    
    # Download user's IP library
    if [[ -n "$GITHUB_ID" ]]; then
        log_info "Updating ${GITHUB_ID} IP library..."
        if git clone -q --depth 1 "${PROXY_GITHUB}https://github.com/${GITHUB_ID}/cloudflare-better-ip.git" 2>/dev/null; then
            if [[ -d "cloudflare-better-ip" ]] && [[ -n "$(ls -A cloudflare-better-ip)" ]]; then
                cp -r cloudflare-better-ip/*"${PORT}".txt "$TEMP_DIR/" 2>/dev/null || true
                log_info "${GITHUB_ID} IP library updated"
            fi
            rm -rf cloudflare-better-ip
        fi
    fi
    
    # Custom IP library with password
    if [[ -n "$CLOUDFLARE_ST_PASSWORD" ]]; then
        log_info "Checking custom IP library..."
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" -k "https://xvxvxv:${CLOUDFLARE_ST_PASSWORD}@ip.ssrc.cf/CloudFlareIP-${PORT}.txt" || echo "000")
        if [[ "$status" == "200" ]]; then
            curl -sk "https://xvxvxv:${CLOUDFLARE_ST_PASSWORD}@ip.ssrc.cf/CloudFlareIP-${PORT}.txt" -o "$TEMP_DIR/CloudFlareIP-${PORT}.txt"
            log_info "Custom IP library updated"
        fi
    fi
    
    # Domain.txt support
    if [[ -f "Domain.txt" ]] && [[ "$PORT" -eq 443 || "$PORT" -eq 80 ]]; then
        if [[ -f "Domain2IP.py" ]]; then
            python3 Domain2IP.py
        else
            curl -s -o Domain2IP.py "${PROXY_GITHUB}https://raw.githubusercontent.com/ansoncloud8/am-cf-auto-speed-test/main/Domain2IP.py"
            python3 Domain2IP.py 2>/dev/null || true
        fi
    fi
    
    # Merge and deduplicate
    cat "$TEMP_DIR"/*.txt > ip_temp.txt 2>/dev/null || true
    if [[ -f "ip-${PORT}.txt" ]]; then
        rm -f "ip-${PORT}.txt"
    fi
    awk '!a[$0]++' ip_temp.txt > "ip-${PORT}.txt" 2>/dev/null || true
    rm -f ip_temp.txt
    
    log_info "IP library update complete"
}

# Filter out official Cloudflare IPs
filter_cf_ips() {
    if [[ "$CF_IPS" -ne 0 ]]; then
        log_info "Keeping official Cloudflare IPs"
        return
    fi
    
    log_info "Filtering official Cloudflare IPs..."
    install_python_deps
    
    if [[ ! -f "RemoveCFIPs.py" ]]; then
        curl -s -o RemoveCFIPs.py "${PROXY_GITHUB}https://raw.githubusercontent.com/ansoncloud8/am-cf-auto-speed-test/main/RemoveCFIPs.py"
    fi
    
    if [[ -f "RemoveCFIPs.py" ]]; then
        python3 RemoveCFIPs.py "ip-${PORT}.txt"
    fi
}

# Classify IPs by country
classify_ips_by_country() {
    log_info "Classifying IPs by country..."
    
    if [[ ! -f "ip-${PORT}.txt" ]]; then
        log_error "IP file ip-${PORT}.txt not found"
        return 1
    fi
    
    mkdir -p "$IP_DIR"
    
    while IFS= read -r line; do
        ip=$(echo "$line" | awk '{print $1}')
        [[ -z "$ip" ]] && continue
        
        result=$(mmdblookup --file /usr/share/GeoIP/GeoLite2-Country.mmdb --ip "$ip" country iso_code 2>/dev/null || echo "")
        country_code=$(echo "$result" | awk -F'"' '{print $2}')
        country_code="${country_code:-Unknown}"
        
        echo "$ip" >> "${IP_DIR}/${country_code}-${PORT}.txt"
    done < "ip-${PORT}.txt"
    
    log_info "IPs classified into ${IP_DIR}/"
}

# Check if IP file needs update
check_ip_file_freshness() {
    if [[ -f "ip-${PORT}.txt" ]]; then
        local file_age=$(($(date +%s) - $(stat -c %Y "ip-${PORT}.txt" 2>/dev/null || echo 0)))
        local six_hours=21600
        if [[ "$file_age" -lt "$six_hours" ]]; then
            log_info "IP file is fresh (less than 6 hours old)"
            return 0
        fi
    fi
    return 1
}

# Get local IP and verify location
verify_local_location() {
    log_info "Verifying local network..."
    
    local local_ip
    local_ip=$(curl -s 4.ipw.cn || curl -s ifconfig.me)
    
    local geo_info
    geo_info=$(curl -s "http://ip-api.com/json/${local_ip}?lang=zh-CN")
    local status
    status=$(echo "$geo_info" | jq -r '.status' 2>/dev/null || echo "fail")
    
    if [[ "$status" == "success" ]]; then
        local country_code
        local country
        local region
        local city
        country_code=$(echo "$geo_info" | jq -r '.countryCode')
        country=$(echo "$geo_info" | jq -r '.country')
        region=$(echo "$geo_info" | jq -r '.regionName')
        city=$(echo "$geo_info" | jq -r '.city')
        
        log_info "Local IP: $local_ip ($country$region$city)"
        
        if [[ "$country_code" != "CN" ]]; then
            log_error "Proxy detected! Please disable proxy and retry."
            exit 1
        fi
    else
        log_warn "Could not verify IP location, please ensure no proxy is used"
    fi
}

# Get Cloudflare zone and record identifiers
get_cf_identifiers() {
    log_info "Getting Cloudflare zone/record identifiers..."
    
    # Get zone identifier
    ZONE_IDENTIFIER=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
        -H "X-Auth-Email: ${AUTH_EMAIL}" \
        -H "X-Auth-Key: ${AUTH_KEY}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id' 2>/dev/null)
    
    if [[ -z "$ZONE_IDENTIFIER" || "$ZONE_IDENTIFIER" == "null" ]]; then
        log_error "Failed to get zone identifier for ${ZONE_NAME}"
        exit 1
    fi
    
    log_info "Zone identifier: ${ZONE_IDENTIFIER}"
}

# Run speed test
run_speed_test() {
    log_info "Starting speed test..."
    
    local area_upper="${AREA_GEC^^}"
    local ip_file="${IP_DIR}/${area_upper}-${PORT}.txt"
    local result_csv="${LOG_DIR}/${area_upper}-${PORT}.csv"
    
    if [[ ! -f "$ip_file" ]]; then
        log_error "IP file $ip_file not found"
        exit 1
    fi
    
    mkdir -p "$LOG_DIR"
    
    local speed_url="${SPEED_URL:-https://speed.cloudflare.com/__down?bytes=$((SPEEDTEST_MB * 1000000))}"
    local speedqueue=$((RECORD_COUNT + SPEEDQUEUE_MAX))
    
    ./CloudflareST -tp "$PORT" \
        -url "$speed_url" \
        -f "$ip_file" \
        -dn "$speedqueue" \
        -tl 280 \
        -tlr "$LOSS_MAX" \
        -p 0 \
        -sl "$SPEED_LOWER" \
        -o "$result_csv"
    
    log_info "Speed test complete: $result_csv"
}

# Update DNS records with best IPs
update_dns_records() {
    log_info "Updating DNS records..."
    
    local area_upper="${AREA_GEC^^}"
    local result_csv="${LOG_DIR}/${area_upper}-${PORT}.csv"
    local record_name="${AREA_GEC}-${PORT}-"
    
    local tg_message="ACFST_DDNS 更新完成！%0A地区: ${AREA_GEC} 端口: ${PORT}"
    local count=$RECORD_COUNT
    
    sed -n '2,20p' "$result_csv" | while read -r line; do
        [[ $count -le 0 ]] && break
        
        local ip="${line%%,*}"
        [[ -z "$ip" ]] && continue
        
        # Delete existing record first
        local record_identifier
        record_identifier=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records?name=${record_name}${count}.${ZONE_NAME}" \
            -H "X-Auth-Email: ${AUTH_EMAIL}" \
            -H "X-Auth-Key: ${AUTH_KEY}" \
            -H "Content-Type: application/json" | jq -r '.result[0].id' 2>/dev/null)
        
        if [[ -n "$record_identifier" && "$record_identifier" != "null" ]]; then
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records/${record_identifier}" \
                -H "X-Auth-Email: ${AUTH_EMAIL}" \
                -H "X-Auth-Key: ${AUTH_KEY}" \
                -H "Content-Type: application/json" | jq -rq '.success' 2>/dev/null && \
                log_info "Deleted ${record_name}${count}.${ZONE_NAME}"
        fi
        
        # Create new record
        local attempt=0
        local success=false
        
        while [[ $attempt -lt 3 ]]; do
            local result
            result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records" \
                -H "X-Auth-Email: ${AUTH_EMAIL}" \
                -H "X-Auth-Key: ${AUTH_KEY}" \
                -H "Content-Type: application/json" \
                --data "{
                    \"type\": \"A\",
                    \"name\": \"${record_name}${count}.${ZONE_NAME}\",
                    \"content\": \"${ip}\",
                    \"ttl\": 60,
                    \"proxied\": false
                }")
            
            if echo "$result" | jq -rq '.success' 2>/dev/null; then
                log_info "${record_name}${count}.${ZONE_NAME} -> ${ip} [OK]"
                tg_message="${tg_message}%0A${record_name}${count}.${ZONE_NAME} -> ${ip} [OK]"
                success=true
                break
            else
                local msg
                msg=$(echo "$result" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
                log_warn "Update failed: $msg"
                attempt=$((attempt + 1))
                [[ $attempt -lt 3 ]] && sleep 60
            fi
        done
        
        if [[ "$success" == "false" ]]; then
            log_error "Failed to update ${record_name}${count}.${ZONE_NAME} after 3 attempts"
            tg_message="${tg_message}%0A${record_name}${count}.${ZONE_NAME} -> FAILED"
        fi
        
        count=$((count - 1))
    done
    
    send_notification "$tg_message"
}

# Main function
main() {
    export LANG=zh_CN.UTF-8
    
    log_info "=========================================="
    log_info "Cloudflare Auto Speed Test (Standard Mode)"
    log_info "=========================================="
    
    # Load config and parse args
    load_config
    parse_args "$@"
    
    # Validate required params
    if [[ -z "$AUTH_EMAIL" || -z "$AUTH_KEY" || -z "$ZONE_NAME" ]]; then
        log_error "Missing required config: auth_email, auth_key, zone_name"
        exit 1
    fi
    
    # Setup
    check_dependencies
    download_geolite_mmdb
    
    # Check/update IP library
    if ! check_ip_file_freshness; then
        update_ip_library
        filter_cf_ips
        classify_ips_by_country
    fi
    
    # Verify location
    verify_local_location
    
    # Ensure CloudflareST exists
    download_cloudflarest
    
    # Get CF identifiers
    get_cf_identifiers
    
    # Run speed test
    run_speed_test
    
    # Update DNS records
    update_dns_records
    
    log_info "=========================================="
    log_info "Speed test completed!"
    log_info "=========================================="
}

# Run main
main "$@"
