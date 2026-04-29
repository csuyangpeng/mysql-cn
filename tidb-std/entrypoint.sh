#!/bin/sh
# 与 ../tidb/entrypoint.sh 同一套路：initialize-sql + 无密补 root@'%' + /init
# 区别：--store=tikv（来自 compose 的 command），/init 完成标记在持久卷 /var/lib/tidb-entrypoint
set +H

MARKER_DIR="/var/lib/tidb-entrypoint"
MARKER="${MARKER_DIR}/.initdb_done"
TIDB_PORT="${TIDB_PORT:-4000}"

if [ -z "${TIDB_ROOT_PASSWORD:-}" ]; then
  echo "entrypoint: 未设置 TIDB_ROOT_PASSWORD，仅启动 tidb-server" >&2
  exec /tidb-server "$@"
fi

PASS=$(echo "$TIDB_ROOT_PASSWORD" | sed "s/'/''/g")
cat > /tmp/bootstrap.sql << EOF
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$PASS';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

/tidb-server "$@" --initialize-sql-file=/tmp/bootstrap.sql &
TIDB_PID=$!

echo "entrypoint: 等待 http://127.0.0.1:10080/status ..."
i=0
while [ "$i" -lt 180 ]; do
  if wget -q -O /dev/null http://127.0.0.1:10080/status 2>/dev/null; then
    break
  fi
  i=$((i + 1))
  sleep 1
done
if ! wget -q -O /dev/null http://127.0.0.1:10080/status 2>/dev/null; then
  echo "entrypoint: 等待 TiDB 超时" >&2
  kill -TERM "$TIDB_PID" 2>/dev/null || true
  wait "$TIDB_PID" 2>/dev/null || true
  exit 1
fi

# 与 tidb/ 一致：新集群 + 旧元数据时都能补 root@'%'，便于外网/宿主机用同一密码
if mysql -h 127.0.0.1 -P "$TIDB_PORT" -u root -e "SELECT 1" 2>/dev/null; then
  mysql -h 127.0.0.1 -P "$TIDB_PORT" -u root -e "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$PASS';"
  mysql -h 127.0.0.1 -P "$TIDB_PORT" -u root -e "ALTER USER 'root'@'%' IDENTIFIED BY '$PASS';"
  mysql -h 127.0.0.1 -P "$TIDB_PORT" -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
  mysql -h 127.0.0.1 -P "$TIDB_PORT" -u root -e "FLUSH PRIVILEGES;"
  echo "entrypoint: Root password 与 root@'%' 已处理（可远程/宿主机用 TIDB_ROOT_PASSWORD 连接）"
fi

if [ -f "$MARKER" ]; then
  echo "entrypoint: 已存在 ${MARKER}，跳过 /init"
  wait "$TIDB_PID"
  exit $?
fi

# 有 .sql 才跑；无则只写标记，避免空目录时反复重试
if [ -d /init ]; then
  has=0
  for f in /init/*.sql; do
    if [ -f "$f" ]; then
      has=1
      break
    fi
  done
  if [ "$has" -eq 1 ]; then
    echo "entrypoint: 执行 /init 下 .sql（按 sort）..."
    for f in $(ls /init/*.sql 2>/dev/null | sort); do
      [ -f "$f" ] || continue
      echo "  -> $f"
      if ! MYSQL_PWD="$TIDB_ROOT_PASSWORD" mysql -h 127.0.0.1 -P "$TIDB_PORT" -u root < "$f"; then
        echo "entrypoint: 执行失败: $f" >&2
        kill -TERM "$TIDB_PID" 2>/dev/null || true
        wait "$TIDB_PID" 2>/dev/null || true
        exit 1
      fi
    done
  else
    echo "entrypoint: /init 中无 .sql，仅写标记"
  fi
else
  echo "entrypoint: 无 /init 目录，仅写标记"
fi

mkdir -p "$MARKER_DIR"
: > "$MARKER"
echo "entrypoint: 初始化段完成"

wait "$TIDB_PID"
exit $?
