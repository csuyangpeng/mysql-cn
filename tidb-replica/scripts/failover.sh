#!/bin/bash
# 主站点故障：在备站点（10.18.1.28）上执行，完成备升主
# 用法：sudo ./failover.sh
#
# 说明：
#   - VIP 由 keepalived 自动漂移；本脚本负责校验、记录切换位点、暂停旧正向同步。
#   - 记录的 TSO 是后续建立反向同步的起点，不能丢。
#   - 全程使用 TiDB/TiCDC/PD 自带接口，不使用 MySQL 客户端。
set -euo pipefail

PRIMARY_IP="${PRIMARY_IP:-10.18.1.27}"
SECONDARY_IP="${SECONDARY_IP:-10.18.1.28}"
VIP="${VIP:-10.18.1.100}"
TSO_FILE="${TSO_FILE:-/var/lib/tidb-dr/failover-tso}"

log() { echo "[$(date '+%F %T')] $*"; }

log "=== 主备切换：$PRIMARY_IP -> $SECONDARY_IP ==="

# 1. 本机（备）TiDB 必须健康
log "[1/5] 检查备集群健康..."
curl -fsS --max-time 3 "http://127.0.0.1:10080/status" >/dev/null \
  || { echo "错误：本机 TiDB 不可用，不能升主"; exit 1; }
curl -fsS --max-time 3 "http://127.0.0.1:2379/pd/api/v1/health" >/dev/null \
  || { echo "错误：本机 PD 不健康"; exit 1; }
log "备集群健康检查通过"

# 2. 记录切换位点（反向同步起点）
log "[2/5] 获取当前 TSO..."
TSO_FAILOVER=$(docker exec tidb-secondary-ticdc /cdc cli tso query \
  --pd=http://pd:2379 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
if [ -z "${TSO_FAILOVER:-}" ]; then
  echo "错误：无法获取 TSO（检查 tidb-secondary-ticdc 是否运行）"
  exit 1
fi
mkdir -p "$(dirname "$TSO_FILE")"
echo "$TSO_FAILOVER" > "$TSO_FILE"
log "TSO_FAILOVER=$TSO_FAILOVER 已写入 $TSO_FILE"

# 3. 若旧主仍可达，暂停其正向 changefeed，避免恢复后重复写入
log "[3/5] 尝试暂停旧主上的正向同步..."
if curl -fsS --max-time 2 "http://${PRIMARY_IP}:10080/status" >/dev/null 2>&1; then
  ssh -o BatchMode=yes -o ConnectTimeout=3 "sder@${PRIMARY_IP}" \
    "docker exec tidb-primary-ticdc /cdc cli changefeed pause -c primary-to-secondary --server=http://127.0.0.1:8300" \
    && log "已暂停旧主正向 changefeed" \
    || log "警告：暂停旧主 changefeed 失败，请人工确认"
else
  log "旧主不可达，跳过（其 changefeed 随主机故障停止）"
fi

# 4. 检查 VIP 是否已漂到本机
log "[4/5] 检查 VIP..."
if ip -brief addr show | grep -qw "$VIP"; then
  log "VIP $VIP 已在本机"
else
  log "警告：VIP 尚未漂到本机，请检查 keepalived（systemctl status keepalived）"
fi

# 5. 输出后续动作
log "[5/5] 切换完成"
cat <<EOF

=== 切换完成 ===
新主（写入）: $SECONDARY_IP:4000 / VIP $VIP:4000
切换位点    : $TSO_FAILOVER（文件 $TSO_FILE，建立反向同步时必须使用）

后续动作：
  1. 确认旧主已下线或隔离，禁止其继续写入（必要时在旧主上 docker stop tidb-primary-sql）。
  2. 旧主恢复后，在本机执行 ./recovery.sh（自动读取 $TSO_FILE）。
  3. 确认反向同步追平后，再按演练手册切回。
EOF
