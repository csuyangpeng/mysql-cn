#!/bin/bash
# 原主恢复后执行：建立反向同步，原主作为新备，不抢占
# 在 10.18.1.28（当前主）上执行
set -e

PRIMARY_IP="${PRIMARY_IP:-10.18.1.27}"   # 原主，现为备
SECONDARY_IP="${SECONDARY_IP:-10.18.1.28}" # 原备，现为主
ROOT_PASS="${ROOT_PASS:-123456}"

echo "=== 原主恢复，建立反向同步（不抢占）==="
echo "当前主: $SECONDARY_IP (保持为主)"
echo "原主现为备: $PRIMARY_IP"
echo ""

# 1. 确认两端集群均可用
echo "[1/2] 检查集群..."
for i in 1 2 3 4 5; do
  if MYSQL_PWD="$ROOT_PASS" mysql -h"${SECONDARY_IP}" -P4000 -uroot -e 'SELECT 1' 2>/dev/null; then
    echo "当前主 $SECONDARY_IP OK"
    break
  fi
  [ $i -eq 5 ] && { echo "当前主不可用"; exit 1; }
  sleep 2
done
for i in 1 2 3 4 5; do
  if MYSQL_PWD="$ROOT_PASS" mysql -h"${PRIMARY_IP}" -P4000 -uroot -e 'SELECT 1' 2>/dev/null; then
    echo "原主(现备) $PRIMARY_IP OK"
    break
  fi
  [ $i -eq 5 ] && { echo "原主不可用"; exit 1; }
  sleep 2
done

# 2. 在「当前主」的 TiCDC 上创建反向同步：当前主 -> 原主
echo "[2/2] 创建反向同步（当前主 -> 原主）..."
docker exec tidb-secondary-ticdc cdc cli changefeed remove -c secondary-to-primary --server=http://127.0.0.1:8300 2>/dev/null || true
docker exec tidb-secondary-ticdc cdc cli changefeed create \
  --server="http://127.0.0.1:8300" \
  --sink-uri="mysql://root:${ROOT_PASS}@${PRIMARY_IP}:4000" \
  --changefeed-id="secondary-to-primary"

echo ""
echo "=== 反向同步已建立 ==="
echo "当前主(写): $SECONDARY_IP:4000"
echo "原主(备): $PRIMARY_IP:4000"
echo "应用继续连接 $SECONDARY_IP，原主不抢占。"
