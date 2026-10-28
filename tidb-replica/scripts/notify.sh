#!/bin/bash
# Keepalived 状态通知：只记录日志并落状态标记，不自动停库。
# 部署路径：/etc/keepalived/notify.sh
# 用法（由 keepalived 调用）：notify.sh MASTER|BACKUP|FAULT|STOP

STATE="${1:-UNKNOWN}"
LOG=/var/log/keepalived-tidb.log
STATE_FILE=/run/tidb-dr-state

ts=$(date '+%F %T')
host=$(hostname)
ip=$(hostname -I | awk '{print $1}')

echo "$ts $host state=$STATE" >> "$LOG"

case "$STATE" in
  MASTER)
    echo "MASTER" > "$STATE_FILE"
    ;;
  BACKUP)
    echo "BACKUP" > "$STATE_FILE"
    ;;
  FAULT)
    echo "FAULT" > "$STATE_FILE"
    # 故障时留痕，便于事后判断切换原因
    echo "$ts $host FAULT: check_tidb failed, VIP released" >> "$LOG"
    ;;
  STOP)
    echo "STOP" > "$STATE_FILE"
    ;;
esac

exit 0
