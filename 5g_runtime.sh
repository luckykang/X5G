#!/bin/bash
set -euo pipefail

LOG_FILE="/mnt/sda/logs/5g.log"
CONN_NAME="有线连接 4"
DEVICE_NAME="pcie1"

FAST_RETRY_SEC=10
STABLE_CHECK_SEC=300
MAX_FAIL_TIMES=5
MAX_LOG_SIZE=5242880
PRECHECK_INTERVAL_SEC=5
PRECHECK_TIMEOUT_SEC=600

# 开关：1=失败重启系统；0=失败不重启
REBOOT_ON_FAIL=0

mkdir -p "$(dirname "$LOG_FILE")"
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d%H%M%S')"
fi

log() {
    printf "%s [%-5s] %s\n" "$(date '+%F %T')" "$1" "$2" >> "$LOG_FILE"
}

log_section() {
    log "START" "=============================================================="
    log "START" "$1"
    log "START" "=============================================================="
}

log_table_header() {
    log "CHECK" "轮次 | 激活连接 | IP/SIM | 路由/链路 | WARN      | 原因               | IP"
    log "CHECK" "-----+----------+--------+-----------+-----------+--------------------+---------------"
}

log_precheck_header() {
    log "CHECK" "项目        | 状态   | WARN | 说明"
    log "CHECK" "------------+--------+------+------------------------------"
}

print_precheck_row() {
    local item="$1"
    local status="$2"
    local warn="$3"
    local detail="$4"

    printf -v line "%-10s | %-6s | %-4s | %s" \
        "$item" "$status" "$warn" "$detail"
    log "CHECK" "$line"
}

do_reboot() {
    log "ERROR" "$1"
    systemctl reboot
    exit 1
}

nm_running() {
    nmcli -t -f RUNNING general status 2>/dev/null | grep -qx running
}

hw_exists() {
    lsusb 2>/dev/null | grep -Eiq '2c7c:|05c6:|1199:|1e0e:|1bc7:|2dee:' ||
    lspci 2>/dev/null | grep -Eiq 'Quectel|Wireless|Modem|5G|Communication'
}

device_exists() {
    nmcli -t -f DEVICE device 2>/dev/null | grep -Fxq "$DEVICE_NAME"
}

conn_active() {
    nmcli -t -f NAME,DEVICE con show --active 2>/dev/null \
        | grep -Fxq "$CONN_NAME:$DEVICE_NAME"
}

has_ip() {
    ip -4 addr show "$DEVICE_NAME" 2>/dev/null | grep -q "inet "
}

route_ok() {
    ip route | grep -q "^default.*dev $DEVICE_NAME"
}

ready_for_activation() {
    nm_running && hw_exists && device_exists
}

network_ok() {
    ready_for_activation && conn_active && has_ip && route_ok
}

activate() {
    nmcli con up "$CONN_NAME" >/dev/null 2>&1 || true
}

get_ip() {
    ip -4 addr show "$DEVICE_NAME" 2>/dev/null \
        | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1
}

join_items() {
    local sep="$1"
    shift

    if [ "$#" -eq 0 ]; then
        printf -- "-"
        return
    fi

    local first=1
    local item
    for item in "$@"; do
        if [ "$first" -eq 1 ]; then
            printf "%s" "$item"
            first=0
        else
            printf "%s%s" "$sep" "$item"
        fi
    done
}

print_network_row() {
    local round="$1"
    local conn_stat="WAIT"
    local ip_stat="WAIT"
    local route_stat="WAIT"
    local warns=()
    local reasons=()
    local warn
    local reason
    local ip_val="-"

    conn_active && conn_stat="OK" || { warns+=("E03"); reasons+=("连接未激活"); }
    has_ip && ip_stat="OK" || { warns+=("E04"); reasons+=("未获取IP"); }
    route_ok && route_stat="OK" || { warns+=("E05"); reasons+=("默认路由异常"); }

    if has_ip; then
        ip_val="$(get_ip)"
    fi

    if network_ok; then
        conn_stat="OK"
        ip_stat="OK"
        route_stat="OK"
        ip_val="$(get_ip)"
    fi

    warn="$(join_items " " "${warns[@]}")"
    reason="$(join_items "; " "${reasons[@]}")"
    printf -v line "%-4s | %-8s | %-6s | %-9s | %-9s | %-18s | %s" \
        "$round" "$conn_stat" "$ip_stat" "$route_stat" "$warn" "$reason" "$ip_val"
    log "CHECK" "$line"
}

precheck_wait_loop() {
    local check_func="$1"
    local item_label="$2"
    local done_message="$3"
    local timeout_message="$4"
    local warn_code="$5"
    local waited=0
    local timeout_handled=0

    while ! "$check_func"; do
        if [ "$timeout_handled" -eq 0 ] && [ "$waited" -ge "$PRECHECK_TIMEOUT_SEC" ]; then
            if [ "$REBOOT_ON_FAIL" -eq 1 ]; then
                do_reboot "$timeout_message"
            fi

            print_precheck_row "$item_label" "WAIT" "$warn_code" "$timeout_message，继续等待"
            timeout_handled=1
        fi

        sleep "$PRECHECK_INTERVAL_SEC"
        waited=$((waited + PRECHECK_INTERVAL_SEC))
    done

    print_precheck_row "$item_label" "OK" "-" "$done_message"
}

wait_for_precheck() {
    log_section "5G Precheck"
    log_precheck_header
    precheck_wait_loop \
        nm_running \
        "NetworkMgr" \
        "NetworkManager 已就绪" \
        "NetworkManager 等待超过 $PRECHECK_TIMEOUT_SEC 秒" \
        "E00"
    precheck_wait_loop \
        hw_exists \
        "5G 硬件" \
        "5G 硬件已就绪" \
        "5G 硬件等待超过 $PRECHECK_TIMEOUT_SEC 秒" \
        "E01"
    precheck_wait_loop \
        device_exists \
        "设备 $DEVICE_NAME" \
        "5G 硬件与设备 $DEVICE_NAME 已就绪" \
        "设备 $DEVICE_NAME 等待超过 $PRECHECK_TIMEOUT_SEC 秒" \
        "E02"
}

activate_until_ready() {
    local phase="$1"
    local reboot_reason="$2"
    local fail_warn="$3"
    local fail_count=0
    local round=1

    while ! network_ok; do
        if ! ready_for_activation; then
            log "WARN" "$phase 检测到硬件或设备未就绪，进入预检查"
            wait_for_precheck
        fi

        activate
        print_network_row "$round"

        if network_ok; then
            log "DONE" "$phase 激活成功，IP=$(get_ip)"
            return 0
        fi

        fail_count=$((fail_count + 1))

        if [ "$fail_count" -ge "$MAX_FAIL_TIMES" ]; then
            if [ "$REBOOT_ON_FAIL" -eq 1 ]; then
                do_reboot "$reboot_reason"
            fi

            log "WARN" "$fail_warn"
            return 1
        fi

        sleep "$FAST_RETRY_SEC"
        round=$((round + 1))
    done

    return 0
}

wait_for_precheck

log_section "5G Runtime Check"
log "START" "REBOOT_ON_FAIL=$REBOOT_ON_FAIL  MAX_FAIL_TIMES=$MAX_FAIL_TIMES"
log_table_header

activate_until_ready \
    "启动阶段" \
    "启动阶段连续 $MAX_FAIL_TIMES 次激活失败，触发系统重启" \
    "启动阶段连续 $MAX_FAIL_TIMES 次激活失败，重启关闭，进入慢检测"

while true; do
    sleep "$STABLE_CHECK_SEC"
    print_network_row "-"

    if network_ok; then
        continue
    fi

    log "WARN" "检测到 5G 异常，进入快速重试"
    activate_until_ready \
        "恢复阶段" \
        "恢复阶段连续 $MAX_FAIL_TIMES 次激活失败，触发系统重启" \
        "恢复阶段连续 $MAX_FAIL_TIMES 次激活失败，重启关闭，返回慢检测"
done
