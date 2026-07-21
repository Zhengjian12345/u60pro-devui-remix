#!/bin/sh
# fmsimpin.sh - 飞猫分身切卡控制脚本 (U60 Pro ubus 版)
# 用法: fmsimpin.sh status | switch <pin_num_m> [timeout]

CMD="$1"
PIN_NUM_M="$2"
TIMEOUT="${3:-30}"

LOG="/tmp/devui-fmswitch-action.log"
RESULT="/tmp/fmswitch_result.txt"
PIDFILE="/tmp/fmswitch.pid"
ADMIN_PASS="admin"

log() { stamp=$(TZ=CST-8 date '+%F %T'); echo "[$stamp] $msg" >> "$LOG"; }

get_sault() {
    ubus call zwrt_web web_login_info 2>/dev/null | \
        jsonfilter -e '@.result[1].zte_web_sault' 2>/dev/null
}

calc_password() {
    sault="$1"; pass="$ADMIN_PASS"
    echo -n "${sault}${pass}" | sha256sum | awk '{print $1}' | tr 'a-f' 'A-F'
}

do_login() {
    sault=$(get_sault); [ -z "$sault" ] && return 1
    password=$(calc_password "$sault")
    result=$(ubus call zwrt_web web_login "{\"password\":\"$password\"}" 2>/dev/null)
    token=$(echo "$result" | jsonfilter -e '@.result[1].ubus_rpc_session' 2>/dev/null)
    [ -z "$token" ] && return 1; echo "$token"
}

set_pin_no_decode() {
    ubus call zwrt_zte_mdm.api zwrt_mdm_uci_set \
        "{\"option\":\"pin_no_need_decode\",\"value\":\"1\"}" 2>/dev/null
}

do_switch() {
    token="$1"; pin="$2"
    set_pin_no_decode "$token"
    result=$(ubus call zwrt_zte_mdm.api sim_change_pin_mode \
        "{\"pin_num_m\":\"$pin\",\"pin_mode\":1}" 2>/dev/null)
    code=$(echo "$result" | jsonfilter -e '@.result[0]' 2>/dev/null)
    [ "$code" = "0" ] && return 0 || return 1
}

get_netinfo() {
    ubus call zte_nwinfo_api nwinfo_get_netinfo {} 2>/dev/null
}

parse_netinfo() { echo "$1" | jsonfilter -e "@.result[1].$2" 2>/dev/null; }

wait_for_network() {
    timeout="$1"; elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        result=$(get_netinfo)
        net_type=$(parse_netinfo "$result" "network_type")
        provider=$(parse_netinfo "$result" "network_provider")
        [ "$net_type" = "SA" ] || [ "$net_type" = "NSA" ] || [ "$net_type" = "LTE" ] && {
            log "INFO: 网络已恢复 $provider/$net_type"
            echo "OK:$provider:$net_type"; return 0
        }
        sleep 1; elapsed=$((elapsed + 1))
    done
    log "WARN: 等待网络恢复超时"; echo "TIMEOUT"; return 1
}

get_current_pin() {
    result=$(get_netinfo); mnc=$(parse_netinfo "$result" "rmnc")
    case "$mnc" in 0|00) echo "0100";; 11) echo "0200";; 1|01) echo "0300";; *) echo "-";; esac
}

case "$CMD" in
    status)
        result=$(get_netinfo)
        echo "FM_INSTALLED=1"
        echo "FM_PROVIDER=$(parse_netinfo "$result" "network_provider_fullname")"
        echo "FM_NETTYPE=$(parse_netinfo "$result" "network_type")"
        echo "FM_BAND=$(parse_netinfo "$result" "wan_active_band")"
        echo "FM_SIGNAL=$(parse_netinfo "$result" "signalbar")"
        echo "FM_MCC=$(parse_netinfo "$result" "rmcc")"
        echo "FM_MNC=$(parse_netinfo "$result" "rmnc")"
        echo "FM_PIN=$(get_current_pin)"
        echo "FM_SWITCHING=0"
        [ -f "$PIDFILE" ] && { pid=$(cat "$PIDFILE" 2>/dev/null); [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && echo "FM_SWITCHING=1"; }
        ;;
    switch)
        [ -z "$PIN_NUM_M" ] && { echo "FAIL:MISSING_PIN"; exit 1; }
        echo $$ > "$PIDFILE"; log "START: 开始切卡 pin_num_m=$PIN_NUM_M"
        token=$(do_login)
        [ $? -ne 0 ] && { echo "FAIL:LOGIN" > "$RESULT"; rm -f "$PIDFILE"; exit 1; }
        do_switch "$token" "$PIN_NUM_M" || { echo "FAIL:SWITCH" > "$RESULT"; rm -f "$PIDFILE"; exit 1; }
        wait_result=$(wait_for_network "$TIMEOUT")
        echo "$wait_result" > "$RESULT"
        log "END: 切卡流程结束 result=$wait_result"; rm -f "$PIDFILE"
        ;;
    *) echo "用法: $0 status | switch <pin_num_m> [timeout]"; exit 1;;
esac
