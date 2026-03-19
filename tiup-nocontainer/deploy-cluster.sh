#!/bin/bash
# TiDB TiUP 集群：首次部署
# 在 tiup-nocontainer 目录下执行，需 tiup 在 PATH 中
# 部署前需配置 SSH 公钥免密登录，见 README「免密部署」
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLUSTER_A="${CLUSTER_A:-tidb-cluster-a}"
CLUSTER_B="${CLUSTER_B:-tidb-cluster-b}"
TIUP_VER="${TIUP_VER:-v6.5.0}"
DEPLOY_USER="${DEPLOY_USER:-sder}"  # 部署时使用的 SSH 用户
# 需密码时：USE_PASSWORD=1 ./deploy-cluster.sh
USE_PASSWORD="${USE_PASSWORD:-0}"
SSH_OPTS=""
[ "$USE_PASSWORD" = "1" ] && SSH_OPTS="-p"

echo "=== TiDB 集群部署 ==="
echo "cluster-a: $CLUSTER_A (10.18.1.27)"
echo "cluster-b: $CLUSTER_B (10.18.1.28)"
echo "版本: $TIUP_VER"
[ "$USE_PASSWORD" = "1" ] && echo "用户: $DEPLOY_USER (密码)" || echo "用户: $DEPLOY_USER (公钥)"
echo ""

echo "[1/2] 部署 cluster-a..."
echo y | tiup cluster deploy $CLUSTER_A $TIUP_VER ./topology-a.yaml --user $DEPLOY_USER $SSH_OPTS

echo ""
echo "[2/2] 部署 cluster-b..."
echo y | tiup cluster deploy $CLUSTER_B $TIUP_VER ./topology-b.yaml --user $DEPLOY_USER $SSH_OPTS

echo ""
echo "=== 部署完成 ==="
echo "启动集群: ./start-cluster.sh"
echo "建立同步: ROOT_PASS=123456 ./setup-replication.sh"
