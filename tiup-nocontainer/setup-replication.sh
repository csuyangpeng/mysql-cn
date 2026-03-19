#!/bin/bash
# TiDB 主从复制配置（TiUP 部署版）
# 在 tiup-container 目录下执行，建立 10.18.1.27 -> 10.18.1.28 的 TiCDC 同步
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLUSTER_A_IP="${CLUSTER_A_IP:-10.18.1.27}"
CLUSTER_B_IP="${CLUSTER_B_IP:-10.18.1.28}"
CDC_PORT="${CDC_PORT:-8300}"
ROOT_PASS="${ROOT_PASS:-123456}"
CHANGEFEED_ID="${CHANGEFEED_ID:-a-to-b}"
TIUP_CDC_VER="${TIUP_CDC_VER:-v6.5.0}"

echo "=== TiDB TiUP 主从复制配置 ==="
echo "源集群 (cluster-a): $CLUSTER_A_IP:4000"
echo "目标集群 (cluster-b): $CLUSTER_B_IP:4000"
echo "TiCDC: $CLUSTER_A_IP:$CDC_PORT"
echo ""

# 1. 验证 TiCDC
echo "[1/4] 验证 TiCDC..."
tiup cdc:${TIUP_CDC_VER} cli capture list --server="http://${CLUSTER_A_IP}:${CDC_PORT}" || {
  echo "错误：无法连接 TiCDC"
  exit 1
}
echo ""

# 2. 检查 TiDB 连通性
echo "[2/4] 检查 TiDB..."
for i in 1 2 3 4 5; do
  if MYSQL_PWD="$ROOT_PASS" mysql -h"${CLUSTER_A_IP}" -P4000 -uroot -e 'SELECT 1' 2>/dev/null; then
    echo "cluster-a OK"
    break
  fi
  [ $i -eq 5 ] && { echo "cluster-a 连接失败"; exit 1; }
  sleep 2
done
for i in 1 2 3 4 5; do
  if MYSQL_PWD="$ROOT_PASS" mysql -h"${CLUSTER_B_IP}" -P4000 -uroot -e 'SELECT 1' 2>/dev/null; then
    echo "cluster-b OK"
    break
  fi
  [ $i -eq 5 ] && { echo "cluster-b 连接失败 (root 密码: $ROOT_PASS?)"; exit 1; }
  sleep 2
done
echo ""

# 3. 删除已存在的 changefeed
echo "[3/4] 创建 Changefeed..."
tiup cdc:${TIUP_CDC_VER} cli changefeed remove -c ${CHANGEFEED_ID} --server="http://${CLUSTER_A_IP}:${CDC_PORT}" 2>/dev/null || true

# 4. 创建 changefeed（使用 cdc-config.toml 确保 DDL 同步）
tiup cdc:${TIUP_CDC_VER} cli changefeed create \
  --server="http://${CLUSTER_A_IP}:${CDC_PORT}" \
  --sink-uri="mysql://root:${ROOT_PASS}@${CLUSTER_B_IP}:4000/" \
  --changefeed-id="${CHANGEFEED_ID}" \
  --start-ts=0 \
  --config="${SCRIPT_DIR}/cdc-config.toml"

echo ""
echo "[4/4] 状态..."
sleep 3
tiup cdc:${TIUP_CDC_VER} cli changefeed list --server="http://${CLUSTER_A_IP}:${CDC_PORT}"
echo ""
echo "=== 完成 ==="
echo "验证: mysql -h${CLUSTER_A_IP} -P4000 -uroot -p -e \"INSERT INTO test.t1 VALUES(1);\""
echo "      mysql -h${CLUSTER_B_IP} -P4000 -uroot -p -e \"SELECT * FROM test.t1;\""
