#!/bin/bash
# 原主恢复后：在当前主（10.18.1.28）上执行，建立反向同步
# 用法：sudo ./recovery.sh [START_TS]
#   START_TS 不传时读取 failover.sh 写入的 /tmp/tso_failover
#
# 反向同步从切换位点开始，覆盖故障期间新主上的全部写入。
# 全程使用 TiCDC 自带 CLI，不使用 MySQL 客户端。
set -euo pipefail

PRIMARY_IP="${PRIMARY_IP:-10.18.1.27}"     # 原主，现为备
SECONDARY_IP="${SECONDARY_IP:-10.18.1.28}" # 原备，现为主
ROOT_PASS="${ROOT_PASS:-123456}"
TSO_FILE="${TSO_FILE:-/var/lib/tidb-dr/failover-tso}"
REMOVE_FORWARD="${REMOVE_FORWARD:-true}"

log() { echo "[$(date '+%F %T')] $*"; }

START_TS="${1:-${START_TS:-}}"
if [ -z "$START_TS" ] && [ -r "$TSO_FILE" ]; then
  START_TS=$(cat "$TSO_FILE")
fi
if ! [[ "${START_TS:-}" =~ ^[0-9]+$ ]]; then
  echo "错误：缺少有效的切换位点 TSO。请显式传入 START_TS，或确认 $TSO_FILE 存在。"
  exit 1
fi

log "=== 建立反向同步 $SECONDARY_IP -> $PRIMARY_IP，起始 TSO=$START_TS ==="

# 1. 两端 TiDB 均可用
log "[1/4] 检查集群..."
curl -fsS --max-time 3 http://127.0.0.1:10080/status >/dev/null \
  || { echo "错误：当前主 $SECONDARY_IP 的 TiDB 不可用"; exit 1; }
curl -fsS --max-time 3 "http://${PRIMARY_IP}:10080/status" >/dev/null \
  || { echo "错误：原主 $PRIMARY_IP 的 TiDB 不可用"; exit 1; }
log "两端 TiDB 均可用"

# 2. 删除旧正向 changefeed（已暂停），防止恢复后重复写入
if [ "$REMOVE_FORWARD" = "true" ]; then
  log "[2/4] 清理旧正向 changefeed..."
  ssh -o BatchMode=yes -o ConnectTimeout=5 "sder@${PRIMARY_IP}" \
    "docker exec tidb-primary-ticdc /cdc cli changefeed remove -c primary-to-secondary --server=http://127.0.0.1:8300 2>/dev/null || true" \
    && log "旧正向 changefeed 已清理" \
    || log "警告：清理旧正向 changefeed 失败，请人工确认其处于 paused 状态"
fi

# 3. 创建反向 changefeed
log "[3/4] 创建反向 changefeed..."
docker exec tidb-secondary-ticdc /cdc cli changefeed remove \
  -c secondary-to-primary --server=http://127.0.0.1:8300 >/dev/null 2>&1 || true
docker exec tidb-secondary-ticdc /cdc cli changefeed create \
  --server=http://127.0.0.1:8300 \
  --sink-uri="mysql://root:${ROOT_PASS}@${PRIMARY_IP}:4000" \
  --changefeed-id="secondary-to-primary" \
  --start-ts="$START_TS"

# 4. 显示状态
log "[4/4] 反向 changefeed 状态："
docker exec tidb-secondary-ticdc /cdc cli changefeed query \
  -c secondary-to-primary --server=http://127.0.0.1:8300 --simple 2>/dev/null || \
  docker exec tidb-secondary-ticdc /cdc cli changefeed query \
  -c secondary-to-primary --server=http://127.0.0.1:8300

cat <<EOF

=== 反向同步已建立 ===
当前主（写入）: $SECONDARY_IP:4000 / VIP 10.18.1.100
原主（备）    : $PRIMARY_IP:4000
起始位点      : $START_TS

后续：确认 checkpoint-ts 已追平当前 TSO 后，再执行 switchback.sh 切回。
EOF
