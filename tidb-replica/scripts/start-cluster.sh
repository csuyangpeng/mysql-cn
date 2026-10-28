#!/bin/bash
# TiDB 容器集群：启动（先备后主）
# 用法：./start-cluster.sh
# 在可 SSH 到 10.18.1.27、10.18.1.28 的机器上执行
set -euo pipefail

PRIMARY_HOST="${PRIMARY_HOST:-10.18.1.27}"
SECONDARY_HOST="${SECONDARY_HOST:-10.18.1.28}"
REPLICA_DIR="${REPLICA_DIR:-/home/sder/mysql-cn/tidb-replica}"
SSH_USER="${SSH_USER:-sder}"

log() { echo "[$(date '+%F %T')] $*"; }

log "=== TiDB 容器集群启动 ==="

log "[1/2] 启动从集群 (${SECONDARY_HOST})..."
ssh "${SSH_USER}@${SECONDARY_HOST}" "cd ${REPLICA_DIR}/secondary && docker compose up -d"

log "[2/2] 启动主集群 (${PRIMARY_HOST})..."
ssh "${SSH_USER}@${PRIMARY_HOST}" "cd ${REPLICA_DIR}/primary && docker compose up -d"

log "等待 TiDB 就绪..."
for h in "$SECONDARY_HOST" "$PRIMARY_HOST"; do
  for i in $(seq 1 30); do
    if curl -fsS --max-time 2 "http://${h}:10080/status" >/dev/null 2>&1; then
      log "$h TiDB 就绪"
      break
    fi
    [ "$i" -eq 30 ] && { echo "错误：$h TiDB 未就绪"; exit 1; }
    sleep 3
  done
done

cat <<EOF

=== 完成 ===
首次部署请执行：ssh ${SSH_USER}@${PRIMARY_HOST} "cd ${REPLICA_DIR}/scripts && ./setup-replication.sh"
EOF
