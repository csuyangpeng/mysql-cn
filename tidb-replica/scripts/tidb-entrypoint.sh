#!/bin/sh
# TiDB 容器入口脚本（覆盖镜像内 /entrypoint.sh）
# 与镜像自带逻辑一致，额外在首次初始化时设置 GC 保护时间，
# 避免主备切换窗口内 TiKV 回收尚未同步的历史数据。
# 注意：--initialize-sql-file 只在空集群首次启动时执行。
set +H

PASS="${TIDB_ROOT_PASSWORD:-123456}"
PASS_ESC=$(echo "$PASS" | sed "s/'/''/g")

# 生成首次启动用的 SQL
cat > /tmp/bootstrap.sql << EOF
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$PASS_ESC';
ALTER USER 'root'@'%' IDENTIFIED BY '$PASS_ESC';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SET GLOBAL tidb_gc_life_time = '24h';
EOF

# 启动 TiDB（透传 docker compose 的 command）
/tidb-server "$@" --initialize-sql-file=/tmp/bootstrap.sql &
TIDB_PID=$!

# 等待 TiDB 就绪
echo "Waiting for TiDB..."
until wget -q -O /dev/null http://127.0.0.1:10080/status 2>/dev/null; do
  sleep 2
done

# 已有集群：确保 root@'%' 密码存在（GC 生命周期在已有集群上不会被重置）
if mysql -h 127.0.0.1 -P 4000 -u root -e 'SELECT 1' 2>/dev/null; then
  mysql -h 127.0.0.1 -P 4000 -u root -e "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$PASS_ESC';"
  mysql -h 127.0.0.1 -P 4000 -u root -e "ALTER USER 'root'@'%' IDENTIFIED BY '$PASS_ESC';"
  mysql -h 127.0.0.1 -P 4000 -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
  mysql -h 127.0.0.1 -P 4000 -u root -e "FLUSH PRIVILEGES;"
  echo "Root password set (root@'%')."
fi

wait $TIDB_PID
