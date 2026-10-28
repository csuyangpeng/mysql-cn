#!/bin/bash
# 回切：当前主（10.18.1.28）-> 原主（10.18.1.27）
# 在 10.18.1.28 上执行。执行前必须停止业务写入（本脚本会校验追平）。
#
# 顺序（防止复制回环与数据丢失）：
#   1. 记录回切位点 TSO_CUT
#   2. 等反向同步 checkpoint 追平 TSO_CUT
#   3. 删除反向 changefeed
#   4. 在原主上创建新的正向 changefeed（起点 TSO_CUT）
#   5. 停止本机 keepalived，VIP 回到原主
#   6. 重新启动本机 keepalived（BACKUP，不抢占）
set -euo pipefail

PRIMARY_IP="${PRIMARY_IP:-10.18.1.27}"     # 原主，将切回为主
SECONDARY_IP="${SECONDARY_IP:-10.18.1.28}" # 当前主
ROOT_PASS="${ROOT_PASS:-123456}"
OUTAGE_FEED="secondary-to-primary"
FORWARD_FEED="primary-to-secondary"

log() { echo "[$(date '+%F %T')] $*"; }

log "=== 回切 $SECONDARY_IP -> $PRIMARY_IP ==="

# 0. 前置检查
curl -fsS --max-time 3 http://127.0.0.1:10080/status >/dev/null \
  || { echo "错误：当前主 TiDB 不可用"; exit 1; }
curl -fsS --max-time 3 "http://${PRIMARY_IP}:10080/status" >/dev/null \
  || { echo "错误：原主 TiDB 不可用"; exit 1; }

# 1. 回切位点
TSO_CUT=$(docker exec tidb-secondary-ticdc /cdc cli tso query \
  --pd=http://pd:2379 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
[ -n "${TSO_CUT:-}" ] || { echo "错误：无法获取 TSO"; exit 1; }
log "[1/6] TSO_CUT=$TSO_CUT"

# 2. 等待反向同步追平
log "[2/6] 等待反向同步追平（最多 300 秒）..."
ok=false
for _ in $(seq 1 150); do
  ck=$(docker exec tidb-secondary-ticdc /cdc cli changefeed query \
    -c "$OUTAGE_FEED" --server=http://127.0.0.1:8300 --simple 2>/dev/null \
    | grep -oE '"(checkpoint_tso|checkpoint-ts)"[[:space:]]*:[[:space:]]*[0-9]+' \
    | grep -oE '[0-9]+' | tail -1 || true)
  if [ -n "${ck:-}" ] && [ "$ck" -ge "$TSO_CUT" ]; then
    log "已追平：checkpoint-ts=$ck >= $TSO_CUT"
    ok=true
    break
  fi
  sleep 2
done
if [ "$ok" != "true" ]; then
  echo "错误：反向同步未追平，禁止回切。请检查 changefeed 状态与延迟。"
  exit 1
fi

# 3. 删除反向 changefeed
log "[3/6] 删除反向 changefeed..."
docker exec tidb-secondary-ticdc /cdc cli changefeed remove \
  -c "$OUTAGE_FEED" --server=http://127.0.0.1:8300

# 4. 在原主上创建新的正向 changefeed
log "[4/6] 在原主创建正向 changefeed，起点 $TSO_CUT ..."
ssh -o BatchMode=yes -o ConnectTimeout=5 "sder@${PRIMARY_IP}" bash -s <<EOF
set -e
docker exec tidb-primary-ticdc /cdc cli changefeed remove -c $FORWARD_FEED --server=http://127.0.0.1:8300 >/dev/null 2>&1 || true
docker exec tidb-primary-ticdc /cdc cli changefeed create \
  --server=http://127.0.0.1:8300 \
  --sink-uri="mysql://root:${ROOT_PASS}@${SECONDARY_IP}:4000" \
  --changefeed-id="$FORWARD_FEED" \
  --start-ts="$TSO_CUT"
EOF

# 5. 释放 VIP（本机停止 keepalived，原主接管）
log "[5/6] 停止本机 keepalived，VIP 回到原主..."
systemctl stop keepalived
for _ in $(seq 1 15); do
  if ssh -o BatchMode=yes -o ConnectTimeout=3 "sder@${PRIMARY_IP}" \
       "ip -brief addr show | grep -qw 10.18.1.100"; then
    log "VIP 已回到 $PRIMARY_IP"
    break
  fi
  sleep 1
done

# 6. 重新启动本机 keepalived（BACKUP）
log "[6/6] 启动本机 keepalived（BACKUP，不抢占）..."
systemctl start keepalived
sleep 2

cat <<EOF

=== 回切完成 ===
新主（写入）: $PRIMARY_IP:4000 / VIP 10.18.1.100
新备        : $SECONDARY_IP:4000
正向同步    : $FORWARD_FEED，起点 $TSO_CUT
EOF
