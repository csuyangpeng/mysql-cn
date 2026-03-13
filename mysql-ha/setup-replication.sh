#!/bin/bash
# 主从复制配置脚本：主库就绪后，从库执行 CHANGE MASTER TO
set -e

MASTER_HOST="${MASTER_HOST:-mysql-master}"
MASTER_PORT="${MASTER_PORT:-3306}"
REPL_USER="${REPL_USER:-replicator}"
REPL_PASS="${REPL_PASS:-123456}"
SLAVE_HOST="${SLAVE_HOST:-mysql-slave}"
SLAVE_PORT="${SLAVE_PORT:-3306}"
ROOT_PASS="${MYSQL_ROOT_PASSWORD:-123456}"
MAX_WAIT=60

echo "=== MySQL 主从复制配置 ==="
echo "等待主库就绪..."
for i in $(seq 1 $MAX_WAIT); do
  if mysql -h"$MASTER_HOST" -P"$MASTER_PORT" -uroot -p"$ROOT_PASS" -e 'SELECT 1' 2>/dev/null; then
    echo "主库已就绪"
    break
  fi
  [ $i -eq $MAX_WAIT ] && { echo "主库超时"; exit 1; }
  sleep 2
  echo -n "."
done
echo ""

# 获取主库 binlog 位置
echo "获取主库状态..."
MASTER_STATUS=$(mysql -h"$MASTER_HOST" -P"$MASTER_PORT" -uroot -p"$ROOT_PASS" -e "SHOW MASTER STATUS\G" 2>/dev/null)
MASTER_FILE=$(echo "$MASTER_STATUS" | grep "File:" | awk '{print $2}')
MASTER_POS=$(echo "$MASTER_STATUS" | grep "Position:" | awk '{print $2}')

if [ -z "$MASTER_FILE" ] || [ -z "$MASTER_POS" ]; then
  echo "无法获取主库 binlog 位置"
  exit 1
fi
echo "主库 binlog: $MASTER_FILE, position: $MASTER_POS"

# 等待从库就绪
echo "等待从库就绪..."
for i in $(seq 1 $MAX_WAIT); do
  if mysql -h"$SLAVE_HOST" -P"$SLAVE_PORT" -uroot -p"$ROOT_PASS" -e 'SELECT 1' 2>/dev/null; then
    echo "从库已就绪"
    break
  fi
  [ $i -eq $MAX_WAIT ] && { echo "从库超时"; exit 1; }
  sleep 2
  echo -n "."
done
echo ""

# 配置从库复制
echo "配置从库复制..."
mysql -h"$SLAVE_HOST" -P"$SLAVE_PORT" -uroot -p"$ROOT_PASS" << EOF
STOP REPLICA;
RESET REPLICA ALL;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='$MASTER_HOST',
  SOURCE_PORT=$MASTER_PORT,
  SOURCE_USER='$REPL_USER',
  SOURCE_PASSWORD='$REPL_PASS',
  SOURCE_LOG_FILE='$MASTER_FILE',
  SOURCE_LOG_POS=$MASTER_POS;
START REPLICA;
EOF

echo "验证复制状态..."
mysql -h"$SLAVE_HOST" -P"$SLAVE_PORT" -uroot -p"$ROOT_PASS" -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running|Replica_SQL_Running"
echo ""
echo "=== 主从复制配置完成 ==="
