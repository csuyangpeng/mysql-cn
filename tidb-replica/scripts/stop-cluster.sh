#!/bin/bash
# TiDB 容器集群：停止（先主后备）
# 用法：./stop-cluster.sh
set -euo pipefail

PRIMARY_HOST="${PRIMARY_HOST:-10.18.1.27}"
SECONDARY_HOST="${SECONDARY_HOST:-10.18.1.28}"
REPLICA_DIR="${REPLICA_DIR:-/home/sder/mysql-cn/tidb-replica}"
SSH_USER="${SSH_USER:-sder}"

log() { echo "[$(date '+%F %T')] $*"; }

log "=== TiDB 容器集群停止 ==="

log "[1/2] 停止主集群 (${PRIMARY_HOST})..."
ssh "${SSH_USER}@${PRIMARY_HOST}" "cd ${REPLICA_DIR}/primary && docker compose down"

log "[2/2] 停止从集群 (${SECONDARY_HOST})..."
ssh "${SSH_USER}@${SECONDARY_HOST}" "cd ${REPLICA_DIR}/secondary && docker compose down"

log "完成（数据目录保留）"
