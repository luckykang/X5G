#!/bin/bash
set -euo pipefail

LOG_FILE="/mnt/sda/logs/5g.log"
DEVICE_NAME="pcie1"

log() {
    # 调整顺序：1. 时间戳  2. [级别]  3. 消息内容
    printf "%s [%-5s] %s\n" "$(date '+%F %T')" "$1" "$2" >> "$LOG_FILE"
}

fatal() {
    printf "[FATAL] %s [%s] %s\n" "$(date '+%F %T')" "$1" "$2" >> "$LOG_FILE"
    exit 1
}

hw_exists() {
    lsusb 2>/dev/null | grep -Eiq '2c7c:|05c6:|1199:|1e0e:|1bc7:|2dee:' ||
    lspci 2>/dev/null | grep -Eiq 'Quectel|Wireless|Modem|5G|Communication'
}

device_exists() {
    nmcli -t -f DEVICE device | grep -Fxq "$DEVICE_NAME"
}

log "START" "------ 5G Precheck ------"
log "CHECK" "等待 NetworkManager 启动..."

for _ in $(seq 1 60); do
    nmcli -t -f RUNNING general status 2>/dev/null | grep -qx running && break
    sleep 1
done

nmcli -t -f RUNNING general status | grep -qx running \
    || fatal "E00" "NetworkManager 未运行"
log "DONE" "NetworkManager 已就绪"

log "CHECK" "检测 5G 硬件..."
hw_exists || fatal "E01" "未检测到 5G 硬件"

log "CHECK" "检测设备 $DEVICE_NAME..."
device_exists || fatal "E02" "设备 $DEVICE_NAME 未就绪"

log "DONE" "5G 硬件与设备 $DEVICE_NAME 已就绪"
exit 0

