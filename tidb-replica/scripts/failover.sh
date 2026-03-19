#!/bin/bash
# 主集群故障时执行：将应用切换到从集群（备升主）
# 在任意可访问两集群的机器上执行
set -e

PRIMARY_IP="${PRIMARY_IP:-10.18.1.27}"
SECONDARY_IP="${SECONDARY_IP:-10.18.1.28}"
ROOT_PASS="${ROOT_PASS:-123456}"

echo "=== 主集群故障切换（备升主）==="
echo "原主: $PRIMARY_IP (已故障)"
echo "新主: $SECONDARY_IP"
echo ""

# 确认从集群可用
if ! MYSQL_PWD="$ROOT_PASS" mysql -h"${SECONDARY_IP}" -P4000 -uroot -e 'SELECT 1' 2>/dev/null; then
  echo "错误：从集群 $SECONDARY_IP 不可用"
  exit 1
fi
echo "从集群可用，可承接业务"

# 原主上的 changefeed 会因主故障自动停止，无需操作
echo ""
echo "=== 切换完成 ==="
echo "请将应用连接地址改为: $SECONDARY_IP:4000"
echo "原主 $PRIMARY_IP 恢复后，执行 recovery.sh 建立反向同步（原主不抢占，作为新备）"
