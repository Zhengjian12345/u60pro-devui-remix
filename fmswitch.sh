#!/bin/sh
# fmswitch.sh - 飞猫分身切卡后台脚本
# 用法: sh /data/ufi-tools/u60pro-devui/fmswitch.sh <target_carrier> <pin_code> <log_file>

TARGET="$1"
PIN="$2"
LOG="${3:-/tmp/devui-fmswitch-action.log}"
FMSIMPIN="/data/ufi-tools/u60pro-devui/fmsimpin.sh"

TMP="${LOG}.out.$$"
export TZ=CST-8

echo "[$(date '+%F %T')] 开始切卡到 ${TARGET} (PIN: ${PIN})" >>"$LOG"

# 调用 fmsimpin.sh 执行实际切卡
sh "$FMSIMPIN" switch "$PIN" "$TARGET" >"$TMP" 2>&1
rc=$?

# 读取输出并记录
while IFS= read -r line || [ -n "$line" ]; do
    echo "[$(date '+%F %T')] $line" >>"$LOG"
done <"$TMP"

rm -f "$TMP"
echo "[$(date '+%F %T')] 切卡完成，退出码 $rc" >>"$LOG"

# 限制日志大小
tail -n 30 "$LOG" >"${LOG}.trim" && mv "${LOG}.trim" "$LOG"

exit $rc
