#!/bin/bash
set -euo pipefail

# ============================================================
# 基本配置
# ============================================================
LOG_FILE="/mnt/sda/logs/5g.log"
CONN_NAME="有线连接 4"
DEVICE_NAME="pcie1"

FAST_RETRY_SEC=10
STABLE_CHECK_SEC=300
MAX_FAIL_TIMES=5
MAX_LOG_SIZE=5242880   # 5MB

# 开关：1=失败重启系统；0=失败不重启
REBOOT_ON_FAIL=0

# ============================================================
# 日志轮转
# ============================================================
mkdir -p "$(dirname "$LOG_FILE")"
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d%H%M%S')"
fi

# ============================================================
# 日志函数
# ============================================================
log() {
    printf "%s [%-5s] %s\n" "$(date '+%F %T')" "$1" "$2" >> "$LOG_FILE"
}

# ============================================================
# 网络检测函数
# ============================================================
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

network_ok() {
    conn_active && has_ip && route_ok 
}

activate() {
    nmcli con up "$CONN_NAME" >/dev/null 2>&1 || true
}

get_ip() {
    ip -4 addr show "$DEVICE_NAME" | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1
}

# ============================================================
# 表格打印
# ============================================================
print_table_row() {
    local round="$1"
    local ip_stat="WAIT"
    local route_stat="WAIT"
    local warn=""
    local ip_val="-"

    has_ip && ip_stat="OK" || warn="E03"
    route_ok && route_stat="OK" || warn="${warn:+$warn }E04"

    if network_ok; then
        ip_val="$(get_ip)"
        warn="-"
    fi

    printf -v LINE "%-4s | %-10s | %-8s | %-10s | %-8s | %s" \
        "$round" "OK" "$ip_stat" "$route_stat" "$warn" "$ip_val"
    log "CHECK" "$LINE"
}

# ============================================================
# 重启封装
# ============================================================
do_reboot() {
    log "ERROR" "$1"
    systemctl reboot
    exit 1
}

# ============================================================
# 启动日志
# ============================================================
log "START" "------ 5G Runtime Check ------"
log "START" "REBOOT_ON_FAIL=$REBOOT_ON_FAIL  MAX_FAIL_TIMES=$MAX_FAIL_TIMES"
log "CHECK" "轮次 | 激活连接   | IP/SIM   | 路由/链路  | WARN     | IP"

# ============================================================
# 阶段 1：开机激活
# ============================================================
FAIL_COUNT=0
round=1

while ! network_ok; do
    activate
    print_table_row "$round"

    if network_ok; then
        break
    fi

    FAIL_COUNT=$((FAIL_COUNT + 1))

    if [ "$FAIL_COUNT" -ge "$MAX_FAIL_TIMES" ]; then
        if [ "$REBOOT_ON_FAIL" -eq 1 ]; then
            do_reboot "开机连续 $MAX_FAIL_TIMES 次激活失败，触发系统重启"
        else
            log "WARN" "开机失败已达 $MAX_FAIL_TIMES 次，重启关闭，进入慢检测"
            break
        fi
    fi

    sleep "$FAST_RETRY_SEC"
    round=$((round + 1))
done

# ============================================================
# 阶段 2：稳态检测（每 5 分钟）
# ============================================================
while true; do
    sleep "$STABLE_CHECK_SEC"
    print_table_row "-"

    if network_ok; then
        continue
    fi

    log "WARN" "检测到 5G 掉线，进入快速重试"

    FAIL_COUNT=0
    round=1

    while ! network_ok; do
        activate
        print_table_row "$round"

        if network_ok; then
            break
        fi

        FAIL_COUNT=$((FAIL_COUNT + 1))

        if [ "$FAIL_COUNT" -ge "$MAX_FAIL_TIMES" ]; then
            if [ "$REBOOT_ON_FAIL" -eq 1 ]; then
                do_reboot "掉线后连续 $MAX_FAIL_TIMES 次激活失败，触发系统重启"
            else
                log "WARN" "掉线重试失败达 $MAX_FAIL_TIMES 次，重启关闭，返回慢检测"
                break
            fi
        fi

        sleep "$FAST_RETRY_SEC"
        round=$((round + 1))
    done
done
