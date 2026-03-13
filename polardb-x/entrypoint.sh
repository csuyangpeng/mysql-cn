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
    # 执行初始化 SQL（仅首次，数据目录无 .init_done 时）
    INIT_DONE="/home/polarx/polardbx/build/run/.init_done"
    if [ ! -f "$INIT_DONE" ] && [ -d /init ] && [ -n "$(ls -A /init 2>/dev/null)" ]; then
      echo "Running init SQL..."
      for f in /init/*.sql; do
        [ -f "$f" ] && su polarx -c "mysql -h127.0.0.1 -P8527 -uroot -p'$ROOT_PASS' < '$f'" && echo "  Executed: $f"
      done
      touch "$INIT_DONE"
      echo "Init SQL completed."
    fi
    break
  fi
  echo "Waiting... ($i/60)"
  sleep 2
done

# 保持容器运行
wait $PID
