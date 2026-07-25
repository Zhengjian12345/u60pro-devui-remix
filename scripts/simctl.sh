#!/bin/sh
# simctl.sh - Dual-SIM control for U60Pro DevUI
# Refuse switching to an unready/empty slot to avoid offline.
set -u

LOG=/tmp/devui-sim-action.log
TRAFFIC_STATE=/data/plugins/dual-sim-traffic/state.json

log() {
  export TZ=CST-8
  printf '[%s] %s\n' "$(date '+%F %T' 2>/dev/null || echo -)" "$*" >>"$LOG" 2>/dev/null || true
  tail -n 50 "$LOG" >"$LOG.trim" 2>/dev/null && mv "$LOG.trim" "$LOG" 2>/dev/null || true
}

json() {
  ubus -t 6 call zwrt_zte_mdm.api get_sim_info_before '{}' 2>/dev/null || true
}

jget() {
  printf '%s' "$RAW" | jsonfilter -e "$1" 2>/dev/null || true
}

op_name() {
  case "$1" in
    CMCC|46000|46002|46004|46007|46008|46013) echo '中国移动' ;;
    CUCC|46001|46006|46009) echo '中国联通' ;;
    CTCC|46003|46005|46011|46012) echo '中国电信' ;;
    ''|null) echo '未识别' ;;
    *) echo "$1" ;;
  esac
}

# Prefer mcc/mnc for SIM1 operator when Operator field is blank/wrong.
op1_detect() {
  o=$(jget '@.Operator')
  mcc=$(jget '@.mdm_mcc')
  mnc=$(jget '@.mdm_mnc')
  if [ -n "$o" ] && [ "$o" != "null" ]; then
    op_name "$o"
    return
  fi
  if [ -n "$mcc" ] && [ -n "$mnc" ]; then
    op_name "${mcc}${mnc}"
    return
  fi
  echo '未识别'
}

slot_ready() {
  # $1 = 1|2 ; return 0 if ready
  RAW=$(json)
  if [ "$1" = "1" ]; then
    s=$(jget '@.sim_states')
  else
    s=$(jget '@.sim2_states')
  fi
  case "$s" in
    *ready*|*Ready*|*READY*) return 0 ;;
    *) return 1 ;;
  esac
}

bytes_human() {
  b=${1:-}
  case "$b" in ''|null|-) echo '-' ; return ;; esac
  if [ "$b" -ge 1073741824 ] 2>/dev/null; then
    awk -v n="$b" 'BEGIN{printf "%.2f GB", n/1073741824}'
  elif [ "$b" -ge 1048576 ] 2>/dev/null; then
    awk -v n="$b" 'BEGIN{printf "%.1f MB", n/1048576}'
  elif [ "$b" -ge 1024 ] 2>/dev/null; then
    awk -v n="$b" 'BEGIN{printf "%.0f KB", n/1024}'
  else
    printf '%s B' "$b"
  fi
}

status() {
  RAW=$(json)
  dual=$(jget '@.support_dual_sim')
  slot=$(jget '@.current_sim_slot')
  op1=$(jget '@.Operator')
  op2=$(jget '@.Operator2')
  p1=$(jget '@.sim1_provision_state')
  p2=$(jget '@.sim2_provision_state')
  s1=$(jget '@.sim_states')
  s2=$(jget '@.sim2_states')
  modem=$(jget '@.modem_main_state')
  auto=$(uci -q get zwrt_zte_mdm.sim_info.st_auto_switch_card_flag 2>/dev/null || echo 0)
  op1s=$(op1_detect)
  op2s=$(op_name "$op2")

  if [ "$dual" = "1" ]; then ready='双卡支持'; else ready='未报告双卡'; fi
  if [ "$p1" = "1" ] && [ "$p2" = "1" ]; then mode='双卡双待'; else mode='单卡模式'; fi
  case "$slot" in
    1) current="SIM1 · $op1s"; use1='正在使用'; use2='待机' ;;
    2) current="SIM2 · $op2s"; use1='待机'; use2='正在使用' ;;
    *) current='读取中'; use1='未知'; use2='未知' ;;
  esac
  if [ "$auto" = "1" ]; then auto_txt='已开启'; else auto_txt='已关闭'; fi

  d1='-'; d2='-'; u1='-'; u2='-'; l1='-'; l2='-'; r1='-'; r2='-'; src='无collector'
  if [ -f "$TRAFFIC_STATE" ]; then
    src='dual-sim-traffic/state.json'
    d1b=$(jsonfilter -i "$TRAFFIC_STATE" -e '@.sims["1"].day_bytes' 2>/dev/null || true)
    d2b=$(jsonfilter -i "$TRAFFIC_STATE" -e '@.sims["2"].day_bytes' 2>/dev/null || true)
    r1b=$(jsonfilter -i "$TRAFFIC_STATE" -e '@.sims["1"].remaining_bytes' 2>/dev/null || true)
    r2b=$(jsonfilter -i "$TRAFFIC_STATE" -e '@.sims["2"].remaining_bytes' 2>/dev/null || true)
    t1b=$(jsonfilter -i "$TRAFFIC_STATE" -e '@.sims["1"].package_total_bytes' 2>/dev/null || true)
    t2b=$(jsonfilter -i "$TRAFFIC_STATE" -e '@.sims["2"].package_total_bytes' 2>/dev/null || true)
    rd1=$(jsonfilter -i "$TRAFFIC_STATE" -e '@.sims["1"].reset_day' 2>/dev/null || true)
    rd2=$(jsonfilter -i "$TRAFFIC_STATE" -e '@.sims["2"].reset_day' 2>/dev/null || true)
    d1=$(bytes_human "${d1b:--}")
    d2=$(bytes_human "${d2b:--}")
    l1=$(bytes_human "${r1b:--}")
    l2=$(bytes_human "${r2b:--}")
    if [ -n "${t1b:-}" ] && [ -n "${r1b:-}" ] 2>/dev/null; then
      u1=$(bytes_human $((t1b - r1b))) 2>/dev/null || u1='-'
    fi
    if [ -n "${t2b:-}" ] && [ -n "${r2b:-}" ] 2>/dev/null; then
      u2=$(bytes_human $((t2b - r2b))) 2>/dev/null || u2='-'
    fi
    [ -n "$rd1" ] && r1="每月${rd1}日" || r1='-'
    [ -n "$rd2" ] && r2="每月${rd2}日" || r2='-'
  fi

  cat <<EOF
READY=$ready
DUAL=${dual:-0}
SLOT=${slot:-0}
MODE=$mode
CURRENT=$current
AUTO=$auto_txt
AUTO_FLAG=${auto:-0}
OP1=$op1s
OP2=$op2s
USE1=$use1
USE2=$use2
STATE1=${s1:-}
STATE2=${s2:-}
P1=${p1:-0}
P2=${p2:-0}
MODEM=${modem:-}
DAY1=$d1
DAY2=$d2
USED1=$u1
USED2=$u2
LEFT1=$l1
LEFT2=$l2
RESET1=$r1
RESET2=$r2
SRC=$src
EOF
}

activate_slot() {
  n=$1
  # Multiple fallback methods used by U60 firmware variants
  ubus -t 15 call zwrt_zte_mdm.api zwrt_mdm_change_provision_session "{\"active_slot\":$n,\"active_flag\":1}" >/dev/null 2>&1 || true
  ubus -t 12 call zwrt_zte_mdm.api zwrt_zte_mdm_activate_sim "{\"sim_card_id\":$n}" >/dev/null 2>&1 || true
  ubus -t 12 call zwrt_zte_mdm.api zwrt_mdm_activate_sim "{\"sim_card_id\":$n}" >/dev/null 2>&1 || true
  ubus -t 12 call zwrt_zte_mdm.api sim_switch_slot "{\"slot\":$n}" >/dev/null 2>&1 || true
}

cmd_slot() {
  n=${1:-}
  case "$n" in
    1|2) ;;
    *) echo "usage: $0 slot 1|2" >&2; exit 2 ;;
  esac

  if ! slot_ready "$n"; then
    log "REFUSE switch to SIM$n: card not ready"
    echo "ERROR SIM${n}_NOT_READY"
    echo "卡槽 SIM$n 未就绪/未识别，已禁止切换，避免断网"
    exit 3
  fi

  log "activate SIM$n"
  activate_slot "$n"
  # wait for settle
  i=0
  while [ $i -lt 8 ]; do
    sleep 1
    RAW=$(json)
    cur=$(jget '@.current_sim_slot')
    modem=$(jget '@.modem_main_state')
    if [ "$cur" = "$n" ] && [ "$modem" = "modem_init_complete" -o "$modem" = "modem_online" -o -n "$modem" ]; then
      break
    fi
    i=$((i+1))
  done
  RAW=$(json)
  echo "OK SLOT=$(jget '@.current_sim_slot') MODEM=$(jget '@.modem_main_state') STATE1=$(jget '@.sim_states') STATE2=$(jget '@.sim2_states') OP1=$(jget '@.Operator') OP2=$(jget '@.Operator2')"
}

cmd_single() {
  RAW=$(json)
  slot=$(jget '@.current_sim_slot')
  [ -n "$slot" ] || slot=2
  if [ "$slot" = "2" ]; then p1=0; p2=1; else p1=1; p2=0; fi
  log "single mode keep slot=$slot"
  ubus -t 15 call zwrt_zte_mdm.api zwrt_mdm_change_provision_session "{\"active_slot\":2,\"active_flag\":$p2}" >/dev/null 2>&1 || true
  ubus -t 15 call zwrt_zte_mdm.api zwrt_mdm_change_provision_session "{\"active_slot\":1,\"active_flag\":$p1}" >/dev/null 2>&1 || true
  ubus -t 10 call zwrt_zte_mdm.api st_set_auto_switch_slot '{"auto_switch_slot_flag":0}' >/dev/null 2>&1 || true
  echo OK single slot="$slot"
}

cmd_dual() {
  log "dual standby"
  ubus -t 15 call zwrt_zte_mdm.api zwrt_mdm_change_provision_session '{"active_slot":1,"active_flag":1}' >/dev/null 2>&1 || true
  ubus -t 15 call zwrt_zte_mdm.api zwrt_mdm_change_provision_session '{"active_slot":2,"active_flag":1}' >/dev/null 2>&1 || true
  echo OK dual
}

cmd_auto() {
  flag=${1:-0}
  case "$flag" in
    on) flag=1 ;;
    off) flag=0 ;;
    0|1) ;;
    toggle)
      cur=$(uci -q get zwrt_zte_mdm.sim_info.st_auto_switch_card_flag 2>/dev/null || echo 0)
      if [ "$cur" = "1" ]; then flag=0; else flag=1; fi
      ;;
    *) echo "usage: $0 auto 0|1|toggle" >&2; exit 2 ;;
  esac
  log "auto=$flag"
  ubus -t 10 call zwrt_zte_mdm.api st_set_auto_switch_slot "{\"auto_switch_slot_flag\":$flag}" >/dev/null 2>&1 || true
  echo OK auto "$flag"
}

case "${1:-status}" in
  status) status ;;
  slot) cmd_slot "${2:-}" ;;
  single) cmd_single ;;
  dual) cmd_dual ;;
  auto) cmd_auto "${2:-0}" ;;
  *)
    echo "usage: $0 {status|slot 1|2|single|dual|auto 0|1|toggle}" >&2
    exit 2
    ;;
esac
