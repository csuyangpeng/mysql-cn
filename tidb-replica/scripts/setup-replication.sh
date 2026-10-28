#!/bin/bash
# 初始正向同步：主（10.18.1.27）-> 备（10.18.1.28）
# 在 10.18.1.27 上执行，前提是两端集群已启动且备库为空。
# 全程使用 TiDB HTTP 接口与 TiCDC 自带 CLI，不使用 MySQL 客户端。
set -euo pipefail

PRIMARY_IP="${PRIMARY_IP:-10.18.1.27}"
SECONDARY_IP="${SECONDARY_IP:-10.18.1.28}"
ROOT_PASS="${ROOT_PASS:-123456}"

log() { echo "[$(date '+%F %T')] $*"; }

log "=== 初始正向同步：$PRIMARY_IP -> $SECONDARY_IP ==="

# 1. 连通性检查
log "[1/2] 检查集群..."
for i in $(seq 1 10); do
  if curl -fsS --max-time 3 http://127.0.0.1:10080/status >/dev/null 2>&1; then
    log "主集群 OK"
    break
  fi
  [ "$i" -eq 10 ] && { echo "错误：主集群不可用"; exit 1; }
  sleep 3
done
for i in $(seq 1 10); do
  if curl -fsS --max-time 3 "http://${SECONDARY_IP}:10080/status" >/dev/null 2>&1; then
    log "备集群 OK"
    break
  fi
  [ "$i" -eq 10 ] && { echo "错误：备集群 ${SECONDARY_IP}:10080 不可访问"; exit 1; }
  sleep 3
done

# 2. 创建 changefeed
log "[2/2] 创建 TiCDC 同步任务..."
docker exec tidb-primary-ticdc /cdc cli changefeed remove \
  -c primary-to-secondary --server=http://127.0.0.1:8300 >/dev/null 2>&1 || true
docker exec tidb-primary-ticdc /cdc cli changefeed create \
  --server="http://127.0.0.1:8300" \
  --sink-uri="mysql://root:${ROOT_PASS}@${SECONDARY_IP}:4000/" \
  --changefeed-id="primary-to-secondary" \
  --config=/etc/cdc/cdc-config.toml

log "changefeed 状态："
docker exec tidb-primary-ticdc /cdc cli changefeed query \
  -c primary-to-secondary --server=http://127.0.0.1:8300 --simple 2>/dev/null || true

cat <<EOF

=== 同步任务已创建 ===
主集群（写）: $PRIMARY_IP:4000 / VIP 10.18.1.100:4000
备集群（只读）: $SECONDARY_IP:4000

注意：
  1. 备集群为独立集群，请勿写入；写入会造成与主库分叉。
  2. 若创建前主库已有历史数据，需先用 Dumpling/BR 做一次全量，
     再创建 changefeed，否则历史数据不会自动补齐。
EOF
