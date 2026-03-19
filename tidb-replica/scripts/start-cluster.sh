#!/bin/bash
# TiDB 容器集群：启动
# 在可 SSH 到 10.18.1.27、10.18.1.28 的机器上执行
# 或分别在 27、28 上执行对应段落
set -e

PRIMARY_HOST="${PRIMARY_HOST:-10.18.1.27}"
SECONDARY_HOST="${SECONDARY_HOST:-10.18.1.28}"
REPLICA_DIR="${REPLICA_DIR:-~/mysql-cn/tidb-replica}"  # 在目标机上的路径

echo "=== TiDB 容器集群启动 ==="
echo "主: $PRIMARY_HOST"
echo "备: $SECONDARY_HOST"
echo ""

echo "[1/2] 启动从集群 (secondary)..."
echo "ssh $SECONDARY_HOST \"cd $REPLICA_DIR/secondary && docker-compose up -d\""
ssh $SECONDARY_HOST "cd $REPLICA_DIR/secondary && docker-compose up -d"

echo ""
echo "[2/2] 启动主集群 (primary)..."
echo "ssh $PRIMARY_HOST \"cd $REPLICA_DIR/primary && docker-compose up -d\""
ssh $PRIMARY_HOST "cd $REPLICA_DIR/primary && docker-compose up -d"

echo ""
echo "=== 完成 ==="
echo "建立同步: 在 $PRIMARY_HOST 上执行 cd $REPLICA_DIR/scripts && ./setup-replication.sh"
echo "或从本机: ssh $PRIMARY_HOST 'cd $REPLICA_DIR/scripts && ROOT_PASS=123456 ./setup-replication.sh'"
