#!/bin/sh
# fmsimpin.sh — 飞猫分身卡 AT 切卡控制脚本
# 由 u60pro-devui 的 act:simswitch 动作调用
#
# 用法: fmsimpin.sh <pin_code>
#   pin_code: 0200(移动) | 0100(联通) | 0300(电信)
#
# 部署: 放到 /data/plugins/u60pro-devui/fmsimpin.sh
#       chmod +x fmsimpin.sh
#
# 安全: 仅接受白名单 PIN 码；AT 命令通过文件描述符操作 /dev/at_* 端口

set -eu

PIN="${1:-}"
LOG_TAG="fmsimpin"

log() {
    echo "[$(TZ=CST-8 date '+%F %T')] $*"
}

# 白名单校验
case "$PIN" in
    0200|0100|0300) ;;
    *)
        log "拒绝: 不支持的PIN码 '$PIN'"
        echo "错误: 不支持的PIN码"
        exit 1
        ;;
esac

# 确定 PIN 对应的运营商名称
case "$PIN" in
    0200) OPERATOR="移动" ;;
    0100) OPERATOR="联通" ;;
    0300) OPERATOR="电信" ;;
esac

log "开始切换到${OPERATOR} (PIN=${PIN})"

# AT 端口检测
detect_at_port() {
    for port in /dev/at_mdm0 /dev/at_mdm1 /dev/at_usb0 /dev/smd7 /dev/smd11; do
        [ -e "$port" ] || continue
        # 尝试发送 AT 命令验证端口可用
        response=$( (cat "$port" & PID=$!; sleep 0.3; printf 'AT\r' > "$port"; sleep 1; kill $PID 2>/dev/null) 2>/dev/null || true )
        if echo "$response" | grep -q "OK"; then
            echo "$port"
            return 0
        fi
    done
    return 1
}

# 发送 AT 命令
send_at() {
    local port="$1" cmd="$2" wait_secs="${3:-3}"
    (cat "$port" & PID=$!; sleep 0.3; printf '%s\r' "$cmd" > "$port"; sleep "$wait_secs"; kill $PID 2>/dev/null) 2>/dev/null || true
}

# 检测 SIM 是否就绪
wait_sim_ready() {
    local port="$1" max_wait="${2:-30}"
    local start=$(date +%s)
    while [ $(( $(date +%s) - start )) -lt "$max_wait" ]; do
        response=$(send_at "$port" 'AT+CPIN?' 1)
        if echo "$response" | grep -q "+CPIN: READY"; then
            return 0
        fi
        sleep 2
    done
    return 1
}

PORT=$(detect_at_port)
if [ -z "$PORT" ]; then
    log "错误: 未找到可用的AT端口"
    echo "错误: 未找到可用的AT端口"
    exit 1
fi

log "使用AT端口: $PORT"

# 发送切卡命令 AT+CLCK="SC",1,"PIN"
log "发送 AT+CLCK=\"SC\",1,\"${PIN}\""
RESPONSE=$(send_at "$PORT" "AT+CLCK=\"SC\",1,\"${PIN}\"" 3)

if echo "$RESPONSE" | grep -q "OK" || echo "$RESPONSE" | grep -q "+CLCK:"; then
    log "AT 命令成功: $RESPONSE"
else
    # SIM 可能已就绪但 AT 响应有延迟，再检查一次
    CPIN_RESP=$(send_at "$PORT" 'AT+CPIN?' 1)
    if echo "$CPIN_RESP" | grep -q "+CPIN: READY"; then
        log "SIM 已就绪，切卡可能已生效"
    else
        log "AT 命令响应异常，尝试重试..."
        # 重试一次
        sleep 2
        RESPONSE=$(send_at "$PORT" "AT+CLCK=\"SC\",1,\"${PIN}\"" 3)
        if echo "$RESPONSE" | grep -q "OK" || echo "$RESPONSE" | grep -q "+CLCK:"; then
            log "重试成功"
        else
            log "失败: AT响应=$RESPONSE"
            echo "失败: AT命令无OK响应"
            exit 1
        fi
    fi
fi

# 等待 SIM 就绪
log "等待 SIM 就绪..."
if wait_sim_ready "$PORT" 30; then
    log "SIM 已就绪"
else
    log "警告: SIM 就绪超时（30秒），网络可能需要更长时间恢复"
fi

# 等待网络恢复
log "等待网络恢复..."
WAIT_NET_START=$(date +%s)
while [ $(( $(date +%s) - WAIT_NET_START )) -lt 45 ]; do
    # 通过检查网络接口状态判断网络是否恢复
    if ip route show default 2>/dev/null | grep -q "dev rmnet\|dev usb0\|dev wwan"; then
        log "网络已恢复"
        break
    fi
    sleep 3
done

# 后台时间校准
(
    sleep 3
    log "开始时间校准..."
    # 方法1: ntpdate
    if command -v ntpdate >/dev/null 2>&1; then
        ntpdate -u ntp.aliyun.com 2>&1 && log "时间校准成功(ntpdate)" && exit 0
    fi
    # 方法2: rdate
    rdate -s time.windows.com 2>/dev/null || rdate -s ntp.aliyun.com 2>/dev/null
    # 方法3: HTTP Date
    HTTP_DATE=$(curl -sI http://www.baidu.com 2>/dev/null | grep -i '^date:' | sed 's/^date:[[:space:]]*//i')
    if [ -n "$HTTP_DATE" ]; then
        TS=$(date -d "$HTTP_DATE" +%s 2>/dev/null)
        if [ -n "$TS" ]; then
            date -s "@$TS" 2>/dev/null && log "时间校准成功(HTTP)"
        fi
    fi
) &

log "切换到${OPERATOR}完成"
echo "切换到${OPERATOR}完成"
