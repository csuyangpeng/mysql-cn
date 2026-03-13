#!/bin/sh
set -e

# 从环境变量读取 root 密码，默认 123456
ROOT_PASS="${POLARDBX_ROOT_PASSWORD:-123456}"
PASS_ESC=$(echo "$ROOT_PASS" | sed "s/'/''/g")

# 以 polarx 用户启动 PolarDB-X（原 entrypoint 后台运行）
su polarx -c "/home/polarx/entrypoint.sh" &
PID=$!

# 等待数据库就绪
echo "Waiting for PolarDB-X to be ready..."
for i in $(seq 1 60); do
  if su polarx -c "mysql -h127.0.0.1 -P8527 -upolardbx_root -p123456 -e 'select 1'" 2>/dev/null; then
    echo "PolarDB-X ready, creating root user..."
    echo "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$PASS_ESC';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;" | su polarx -c "mysql -h127.0.0.1 -P8527 -upolardbx_root -p123456"
    echo "root user created successfully."
    break
  fi
  echo "Waiting... ($i/60)"
  sleep 2
done

# 保持容器运行
wait $PID
