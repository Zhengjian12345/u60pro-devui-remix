#!/bin/sh
# fmsimpin.sh - 飞猫分身切卡控制脚本 (U60 Pro ubus/goform 混合版) v2.0
# 用法: fmsimpin.sh status | switch <pin_num_m> [timeout]
# 修复: 1)去除jsonfilter依赖 2)增加goform fallback 3)增加详细调试日志

CMD="$1"
PIN_NUM_M="$2"
TIMEOUT="${3:-30}"

LOG="/tmp/devui-fmswitch-action.log"
RESULT="/tmp/fmswitch_result.txt"
PIDFILE="/tmp/fmswitch.pid"
ADMIN_PASS="admin"
DEBUG=1

# ---------- 工具函数 ----------
log() {
    stamp=$(date '+%F %T')
    echo "[$stamp] $1" >> "$LOG"
}

# 安全的 JSON 值提取（纯 POSIX，不依赖 jsonfilter）
json_get() {
    echo "$1" | sed -n 's/.*"'$2'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

json_get_num() {
    echo "$1" | sed -n 's/.*"'$2'"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1
}

# 从 goform 获取网络信息（fallback 方案）
get_netinfo_goform() {
    # 使用设备本地回环调用 goform，避免 401
    curl -s "http://127.0.0.1/goform/goform_get_cmd_process?isTest=false&cmd=network_type,network_provider_fullname,wan_active_band,signalbar,rmcc,rmnc,imsi" \
        -H "Referer: http://127.0.0.1/index.html" 2>/dev/null
}

# 从 ubus 获取网络信息
get_netinfo_ubus() {
    ubus call zte_nwinfo_api nwinfo_get_netinfo {} 2>/dev/null
}

# 统一获取网络信息（优先 ubus，失败回退 goform）
get_netinfo() {
    result=$(get_netinfo_ubus)
    if [ -z "$result" ] || [ "$result" = "{}" ]; then
        [ "$DEBUG" = "1" ] && log "DEBUG: ubus 获取失败，回退到 goform"
        result=$(get_netinfo_goform)
    fi
    echo "$result"
}

# ---------- 登录相关 ----------
get_admin_pass() {
    if [ -f "/etc/config/zwrt_zte_web" ]; then
        pass=$(uci -q get zwrt_zte_web.@user[0].password 2>/dev/null)
        [ -n "$pass" ] && { echo "$pass"; return; }
    fi
    echo "$ADMIN_PASS"
}

get_sault() {
    result=$(ubus call zwrt_web web_login_info 2>/dev/null)
    [ "$DEBUG" = "1" ] && log "DEBUG get_sault raw: $(echo "$result" | head -c 200)"
    echo "$result" | sed -n 's/.*"zte_web_sault"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

calc_password() {
    sault="$1"; pass=$(get_admin_pass)
    echo -n "${sault}${pass}" | sha256sum | awk '{print $1}' | tr 'a-f' 'A-F'
}

do_login() {
    sault=$(get_sault)
    if [ -z "$sault" ]; then
        log "ERROR: 无法获取登录盐值"
        return 1
    fi
    [ "$DEBUG" = "1" ] && log "DEBUG sault=$sault"
    password=$(calc_password "$sault")
    result=$(ubus call zwrt_web web_login "{\"password\":\"$password\"}" 2>/dev/null)
    [ "$DEBUG" = "1" ] && log "DEBUG login result: $(echo "$result" | head -c 200)"
    token=$(echo "$result" | sed -n 's/.*"ubus_rpc_session"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    if [ -z "$token" ]; then
        log "ERROR: 登录失败"
        return 1
    fi
    [ "$DEBUG" = "1" ] && log "DEBUG token=$token"
    echo "$token"
}

# ---------- 切卡相关 ----------
set_pin_no_decode() {
    result=$(ubus call zwrt_zte_mdm.api zwrt_mdm_uci_set \
        "{\"option\":\"pin_no_need_decode\",\"value\":\"1\"}" 2>/dev/null)
    [ "$DEBUG" = "1" ] && log "DEBUG set_pin_no_decode: $(echo "$result" | head -c 100)"
}

do_switch() {
    token="$1"; pin="$2"
    set_pin_no_decode
    log "INFO: 开始切换 pin=$pin"
    result=$(ubus call zwrt_zte_mdm.api sim_change_pin_mode \
        "{\"pin_num_m\":\"$pin\",\"pin_mode\":1}" 2>/dev/null)
    [ "$DEBUG" = "1" ] && log "DEBUG switch result: $(echo "$result" | head -c 200)"
    code=$(echo "$result" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*\[[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
    if [ "$code" = "0" ]; then
        log "SUCCESS: 切卡成功 pin=$pin"
        return 0
    else
        log "ERROR: 切卡失败 code=${code:-unknown}"
        return 1
    fi
}

wait_for_network() {
    timeout="$1"; elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        result=$(get_netinfo)
        net_type=$(json_get "$result" "network_type")
        provider=$(json_get "$result" "network_provider_fullname")
        [ "$DEBUG" = "1" ] && log "DEBUG wait net_type=$net_type provider=$provider elapsed=$elapsed"
        if [ "$net_type" = "SA" ] || [ "$net_type" = "NSA" ] || [ "$net_type" = "LTE" ]; then
            log "INFO: 网络已恢复 $provider/$net_type"
            echo "OK:$provider:$net_type"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    log "WARN: 等待网络恢复超时"
    echo "TIMEOUT"
    return 1
}

get_current_pin() {
    result=$(get_netinfo)
    mnc=$(json_get "$result" "rmnc")
    [ "$DEBUG" = "1" ] && log "DEBUG current mnc=$mnc"
    case "$mnc" in
        0|00)  echo "0100" ;;
        11)    echo "0200" ;;
        1|01)  echo "0300" ;;
        *)     echo "-" ;;
    esac
}

# ---------- 主逻辑 ----------
case "$CMD" in
    status)
        result=$(get_netinfo)
        [ "$DEBUG" = "1" ] && log "DEBUG status raw: $(echo "$result" | head -c 300)"

        provider=$(json_get "$result" "network_provider_fullname")
        net_type=$(json_get "$result" "network_type")
        band=$(json_get "$result" "wan_active_band")
        signal=$(json_get "$result" "signalbar")
        mcc=$(json_get "$result" "rmcc")
        mnc=$(json_get "$result" "rmnc")
        pin=$(get_current_pin)

        [ -z "$provider" ] && provider="未知"
        [ -z "$net_type" ] && net_type="无服务"
        [ -z "$band" ] && band="-"
        [ -z "$signal" ] && signal="-"
        [ -z "$mcc" ] && mcc="-"
        [ -z "$mnc" ] && mnc="-"

        echo "FM_INSTALLED=1"
        echo "FM_PROVIDER=$provider"
        echo "FM_NETTYPE=$net_type"
        echo "FM_BAND=$band"
        echo "FM_SIGNAL=$signal"
        echo "FM_MCC=$mcc"
        echo "FM_MNC=$mnc"
        echo "FM_PIN=$pin"
        echo "FM_SWITCHING=0"

        if [ -f "$PIDFILE" ]; then
            pid=$(cat "$PIDFILE" 2>/dev/null)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                echo "FM_SWITCHING=1"
            fi
        fi
        [ "$DEBUG" = "1" ] && log "DEBUG status output done"
        ;;

    switch)
        [ -z "$PIN_NUM_M" ] && { echo "FAIL:MISSING_PIN"; exit 1; }
        echo $$ > "$PIDFILE"
        log "START: 开始切卡 pin_num_m=$PIN_NUM_M"

        token=$(do_login)
        if [ $? -ne 0 ]; then
            echo "FAIL:LOGIN" > "$RESULT"
            rm -f "$PIDFILE"
            exit 1
        fi

        if ! do_switch "$token" "$PIN_NUM_M"; then
            echo "FAIL:SWITCH" > "$RESULT"
            rm -f "$PIDFILE"
            exit 1
        fi

        wait_result=$(wait_for_network "$TIMEOUT")
        echo "$wait_result" > "$RESULT"

        log "END: 切卡流程结束 result=$wait_result"
        rm -f "$PIDFILE"
        ;;

    *)
        echo "用法: $0 status | switch <pin_num_m> [timeout]"
        echo "  pin_num_m: 0100=移动 0200=电信 0300=联通"
        exit 1
        ;;
esac
