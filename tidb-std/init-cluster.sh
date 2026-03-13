#!/bin/bash
# TiDB 集群初始化：设置 root 密码 + 执行 init SQL
set -e

TIDB_HOST="${TIDB_HOST:-tidb}"
TIDB_PORT="${TIDB_PORT:-4000}"
ROOT_PASS="${TIDB_ROOT_PASSWORD:-123456}"
MAX_WAIT=90

echo "=== TiDB 集群初始化 ==="
echo "等待 TiDB 就绪..."
for i in $(seq 1 $MAX_WAIT); do
  if mysql -h"$TIDB_HOST" -P"$TIDB_PORT" -uroot -e 'SELECT 1' 2>/dev/null; then
    echo "TiDB 已就绪"
    break
  fi
  [ $i -eq $MAX_WAIT ] && { echo "TiDB 超时"; exit 1; }
  sleep 2
  echo -n "."
done
echo ""

# 设置 root 密码
PASS_ESC=$(echo "$ROOT_PASS" | sed "s/'/''/g")
echo "设置 root 密码..."
mysql -h"$TIDB_HOST" -P"$TIDB_PORT" -uroot << EOF
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$PASS_ESC';
ALTER USER 'root'@'%' IDENTIFIED BY '$PASS_ESC';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
echo "root 密码已设置"

# 执行 init SQL
if [ -d /init ] && [ -n "$(ls -A /init/*.sql 2>/dev/null)" ]; then
  echo "执行 init SQL..."
  for f in /init/*.sql; do
    [ -f "$f" ] && MYSQL_PWD="$ROOT_PASS" mysql -h"$TIDB_HOST" -P"$TIDB_PORT" -uroot < "$f" && echo "  Executed: $f"
  done
  echo "Init SQL 完成"
fi

echo "=== 初始化完成 ==="
