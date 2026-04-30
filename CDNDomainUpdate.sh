#!/bin/bash
# Cloudflare Auto Speed Test - CDN Domain Update (Aggregate IPs from multiple regions)
# Usage: ./CDNDomainUpdate.sh [record_name] [domain] [email] [key]
# All configs can be set in config.conf, command line args override config

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"

# Default values
RECORD_NAME="cdn"
AREA_PER_REGION=1

# CloudFlare config (from config.conf)
AUTH_EMAIL=""
AUTH_KEY=""
ZONE_NAME=""

# Notification config
FEISHU_WEBHOOK=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_BOT_USER_ID=""
TELEGRAM_BOT_API=""

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
    [[ -n "$1" ]] && RECORD_NAME="$1"
    [[ -n "$2" ]] && ZONE_NAME="$2"
    [[ -n "$3" ]] && AUTH_EMAIL="$3"
    [[ -n "$4" ]] && AUTH_KEY="$4"
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
    
    # Get record identifiers
    RECORD_IDENTIFIERS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records?name=${RECORD_NAME}.${ZONE_NAME}" \
        -H "X-Auth-Email: ${AUTH_EMAIL}" \
        -H "X-Auth-Key: ${AUTH_KEY}" \
        -H "Content-Type: application/json" | jq -r '.result[].id' 2>/dev/null)
    
    RECORD_COUNT=$(echo "$RECORD_IDENTIFIERS" | grep -c . || echo 0)
    log_info "Found $RECORD_COUNT existing DNS records for ${RECORD_NAME}.${ZONE_NAME}"
}

# Aggregate IPs from log files
aggregate_ips() {
    log_info "Aggregating IPs from log files..."
    
    local log_dir="log"
    mkdir -p "$log_dir"
    
    # Check if specific region log exists
    local specific_log="${log_dir}/${RECORD_NAME^^}-443.csv"
    
    if [[ -f "$specific_log" ]]; then
        log_info "Using specific log: $specific_log"
        local line_count=$(wc -l < "$specific_log")
        line_count=$((line_count - 1))
        
        if [[ "$RECORD_COUNT" -gt "$line_count" ]]; then
            log_error "Record count ($RECORD_COUNT) > available IPs ($line_count)"
            exit 1
        fi
        
        echo "待更新域名数: $RECORD_COUNT"
        echo "待处理IP总数: $line_count"
        log_info "Using ${specific_log} with $line_count IPs"
        
        # Use specific log file
        local result_csv="$specific_log"
        local start=2
        local rows=$((RECORD_COUNT + 1))
        
        aggregate_from_csv "$result_csv" "$start" "$rows"
    else
        # Aggregate from all region logs
        log_info "Aggregating from all region logs..."
        
        local cdn_csv="${log_dir}/CDN.csv"
        > "$cdn_csv"  # Clear/create file
        
        # Get all CSV files except CDN.csv
        local log_files=()
        for f in "${log_dir}"/*.csv; do
            [[ "$f" != "$cdn_csv" && -f "$f" ]] && log_files+=("$f")
        done
        
        local total_lines=0
        for file in "${log_files[@]}"; do
            # Extract 2nd to (area_per_region+1)th lines
            sed -n "2,$((AREA_PER_REGION+1))p" "$file" >> "$cdn_csv"
        done
        
        local line_count=$(wc -l < "$cdn_csv")
        
        # Increase area_per_region if not enough IPs
        while [[ "$RECORD_COUNT" -gt "$line_count" ]]; do
            log_warn "Need more IPs, increasing area_per_region..."
            ((AREA_PER_REGION++))
            > "$cdn_csv"
            for file in "${log_files[@]}"; do
                sed -n "2,$((AREA_PER_REGION+1))p" "$file" >> "$cdn_csv"
            done
            line_count=$(wc -l < "$cdn_csv")
        done
        
        echo "待更新域名数: $RECORD_COUNT"
        echo "待处理IP总数: $line_count"
        
        aggregate_from_csv "$cdn_csv" 1 "$RECORD_COUNT"
    fi
}

# Aggregate IPs from a CSV file
aggregate_from_csv() {
    local csv_file="$1"
    local start="$2"
    local rows="$3"
    
    log_info "Updating DNS from $csv_file (lines $start to $rows)"
    
    local count=0
    local tg_message="CDN 更新完成！%0A域名: ${RECORD_NAME}.${ZONE_NAME}"
    
    sed -n "${start},${rows}p" "$csv_file" | while read -r line; do
        local ip="${line%%,*}"
        [[ -z "$ip" ]] && continue
        
        # Update DNS record
        local result
        result=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records/${RECORD_IDENTIFIER}" \
            -H "X-Auth-Email: ${AUTH_EMAIL}" \
            -H "X-Auth-Key: ${AUTH_KEY}" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"${RECORD_NAME}.${ZONE_NAME}\",
                \"content\": \"${ip}\",
                \"ttl\": 60,
                \"proxied\": false
            }")
        
        if echo "$result" | jq -rq '.success' 2>/dev/null; then
            log_info "${RECORD_NAME}.${ZONE_NAME} -> ${ip} [OK]"
            tg_message="${tg_message}%0A${RECORD_NAME}.${ZONE_NAME} -> ${ip} [OK]"
        else
            local msg
            msg=$(echo "$result" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
            log_error "Update failed: $msg"
            tg_message="${tg_message}%0A${RECORD_NAME}.${ZONE_NAME} -> FAILED"
        fi
        
        # Get next record identifier
        RECORD_IDENTIFIER=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records?name=${RECORD_NAME}.${ZONE_NAME}" \
            -H "X-Auth-Email: ${AUTH_EMAIL}" \
            -H "X-Auth-Key: ${AUTH_KEY}" \
            -H "Content-Type: application/json" | jq -r ".[${count}].id" 2>/dev/null)
        
        ((count++))
    done
    
    send_notification "$tg_message"
}

# Main function
main() {
    export LANG=zh_CN.UTF-8
    
    log_info "=========================================="
    log_info "Cloudflare CDN Domain Update"
    log_info "=========================================="
    
    # Load config and parse args
    load_config
    parse_args "$@"
    
    # Validate required params
    if [[ -z "$AUTH_EMAIL" || -z "$AUTH_KEY" || -z "$ZONE_NAME" ]]; then
        log_error "Missing required config: auth_email, auth_key, zone_name"
        exit 1
    fi
    
    # Get CF identifiers
    get_cf_identifiers
    
    # Aggregate and update
    aggregate_ips
    
    log_info "=========================================="
    log_info "CDN update completed!"
    log_info "=========================================="
}

# Run main
main "$@"
