#!/bin/bash
# TiDB 主从复制配置（简化版，无需 MinIO/BR）
# 在 10.18.1.27 (主节点) 上执行，需确保两台集群均已启动
set -e

PRIMARY_IP="${PRIMARY_IP:-10.18.1.27}"
SECONDARY_IP="${SECONDARY_IP:-10.18.1.28}"
ROOT_PASS="${ROOT_PASS:-123456}"

echo "=== TiDB 主从复制配置（简化版）==="
echo "主集群: $PRIMARY_IP:4000"
echo "从集群: $SECONDARY_IP:4000"
echo ""

# 1. 检查主从集群连通性
echo "[1/2] 检查集群连通性..."
for i in 1 2 3 4 5; do
  if MYSQL_PWD="$ROOT_PASS" mysql -h"${PRIMARY_IP}" -P4000 -uroot -e 'SELECT 1' 2>/dev/null; then
    echo "主集群 OK"
    break
  fi
  [ $i -eq 5 ] && { echo "主集群连接失败"; exit 1; }
  sleep 2
done
for i in 1 2 3 4 5; do
  if MYSQL_PWD="$ROOT_PASS" mysql -h"${SECONDARY_IP}" -P4000 -uroot -e 'SELECT 1' 2>/dev/null; then
    echo "从集群 OK"
    break
  fi
  [ $i -eq 5 ] && { echo "从集群连接失败，请确保 ${SECONDARY_IP}:4000 可访问"; exit 1; }
  sleep 2
done

# 2. 创建 TiCDC Changefeed（含 DDL 同步，使用 config/cdc-config.toml）
echo "[2/2] 创建 TiCDC 同步任务..."
docker exec tidb-primary-ticdc cdc cli changefeed remove -c primary-to-secondary --server=http://127.0.0.1:8300 2>/dev/null || true
echo y | docker exec -i tidb-primary-ticdc cdc cli changefeed create \
  --server="http://127.0.0.1:8300" \
  --sink-uri="mysql://root:${ROOT_PASS}@${SECONDARY_IP}:4000/" \
  --changefeed-id="primary-to-secondary" \
  --start-ts=0 \
  --config=/etc/cdc/cdc-config.toml

echo ""
echo "=== 主从复制配置完成 ==="
echo "主集群(写): mysql -h${PRIMARY_IP} -P4000 -uroot -p${ROOT_PASS}"
echo "从集群(读): mysql -h${SECONDARY_IP} -P4000 -uroot -p${ROOT_PASS}"
echo ""
echo "注意：两集群均需为空或从集群已有主集群数据，否则可能有数据不一致。"
echo "若有历史数据，请先手动同步后再创建 changefeed。"
