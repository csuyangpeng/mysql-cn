#!/bin/bash
# TiDB 容器集群：停止
# 在可 SSH 到 10.18.1.27、10.18.1.28 的机器上执行
set -e

PRIMARY_HOST="${PRIMARY_HOST:-10.18.1.27}"
SECONDARY_HOST="${SECONDARY_HOST:-10.18.1.28}"
REPLICA_DIR="${REPLICA_DIR:-~/mysql-cn/tidb-replica}"
CLEAN_DATA="${CLEAN_DATA:-false}"

echo "=== TiDB 容器集群停止 ==="
echo ""

echo "[1/2] 停止主集群..."
ssh $PRIMARY_HOST "cd $REPLICA_DIR/primary && docker compose down"

echo ""
echo "[2/2] 停止从集群..."
ssh $SECONDARY_HOST "cd $REPLICA_DIR/secondary && docker compose down"

if [ "$CLEAN_DATA" = "true" ]; then
  echo ""
  echo "清理数据目录（需手动执行）:"
  echo "  ssh $PRIMARY_HOST 'rm -rf $REPLICA_DIR/primary/data'"
  echo "  ssh $SECONDARY_HOST 'rm -rf $REPLICA_DIR/secondary/data'"
fi

echo ""
echo "=== 完成 ==="
