#!/bin/bash
# TiDB TiUP 集群：启动
# 在 tiup-nocontainer 目录下执行，需 tiup 在 PATH 中
# 适用于已部署、已停止的集群（若已 destroy 则需先执行 deploy-cluster.sh）
set -e

CLUSTER_A="${CLUSTER_A:-tidb-cluster-a}"
CLUSTER_B="${CLUSTER_B:-tidb-cluster-b}"

echo "=== TiDB 集群启动 ==="
echo "cluster-a: $CLUSTER_A (10.18.1.27)"
echo "cluster-b: $CLUSTER_B (10.18.1.28)"
echo ""

echo "[1/2] 启动 cluster-a..."
tiup cluster start $CLUSTER_A

echo ""
echo "[2/2] 启动 cluster-b..."
tiup cluster start $CLUSTER_B

echo ""
echo "=== 完成 ==="
echo "查看状态: tiup cluster display $CLUSTER_A"
echo "          tiup cluster display $CLUSTER_B"
echo "建立同步: ROOT_PASS=123456 ./setup-replication.sh"
