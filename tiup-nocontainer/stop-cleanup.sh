#!/bin/bash
# TiDB TiUP 集群：停止、清理
# 在 tiup-nocontainer 目录下执行，需 tiup 在 PATH 中
set -e

CLUSTER_A="${CLUSTER_A:-tidb-cluster-a}"
CLUSTER_B="${CLUSTER_B:-tidb-cluster-b}"
CLEAN_DATA="${CLEAN_DATA:-false}"  # 设为 true 时删除数据目录

echo "=== TiDB 集群停止与清理 ==="
echo "cluster-a: $CLUSTER_A (10.18.1.27)"
echo "cluster-b: $CLUSTER_B (10.18.1.28)"
echo ""

# 1. 删除 changefeed（避免 destroy 时残留）
echo "[1/4] 删除 Changefeed..."
tiup cdc:v6.5.0 cli changefeed remove -c a-to-b --server=http://10.18.1.27:8300 2>/dev/null || true
echo ""

# 2. 停止集群
echo "[2/4] 停止集群..."
tiup cluster stop $CLUSTER_A
tiup cluster stop $CLUSTER_B
echo ""

# 3. 销毁集群（移除部署）
echo "[3/4] 销毁集群..."
tiup cluster destroy $CLUSTER_A -y
tiup cluster destroy $CLUSTER_B -y
echo ""

# 4. 清理数据目录（可选）
if [ "$CLEAN_DATA" = "true" ]; then
  echo "[4/4] 清理数据目录（需在 10.18.1.27、10.18.1.28 上执行）..."
  echo "  ssh 10.18.1.27 'sudo rm -rf /tidb-data /tidb-deploy'"
  echo "  ssh 10.18.1.28 'sudo rm -rf /tidb-data /tidb-deploy'"
  echo "  请手动执行上述命令完成数据清理"
else
  echo "[4/4] 跳过数据清理（CLEAN_DATA=true 可清理 /tidb-data、/tidb-deploy）"
fi

echo ""
echo "=== 完成 ==="
