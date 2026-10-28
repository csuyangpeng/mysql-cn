#!/bin/bash
# Keepalived 健康检查（国产化工具链，不使用 MySQL 客户端）
# 判定本机是否具备对外提供 TiDB 服务的能力：
#   1. TiDB HTTP 状态端口可访问
#   2. 本机 PD 健康
#   3. 至少有一个 TiKV store 处于 Up 状态
# 任一项失败即返回非 0，keepalived 将本节点置为 FAULT 并释放 VIP。
# 部署路径：/etc/keepalived/check_tidb.sh

set -u

# 1) TiDB 状态端口（容器内 10080 映射到宿主机 127.0.0.1:10080）
curl -fsS --max-time 2 http://127.0.0.1:10080/status >/dev/null 2>&1 || exit 1

# 2) PD 健康
curl -fsS --max-time 2 http://127.0.0.1:2379/pd/api/v1/health >/dev/null 2>&1 || exit 1

# 3) 至少一个 TiKV store 为 Up
stores=$(curl -fsS --max-time 2 http://127.0.0.1:2379/pd/api/v1/stores 2>/dev/null) || exit 1
echo "$stores" | grep -Eq '"state_name"[[:space:]]*:[[:space:]]*"Up"' || exit 1

exit 0
