#!/bin/bash
# 一次性初始化：从运行中的容器拷贝数据到 ./data，之后可启用本地目录挂载

set -e
cd "$(dirname "$0")"

echo "=== PolarDB-X 数据持久化初始化 ==="

# 1. 临时移除挂载（备份并修改 compose）
echo "临时移除 volume 挂载..."
cp docker-compose.yml docker-compose.yml.bak
sed -i 's|^      - \./data:/home/polarx|      # - \./data:/home/polarx|' docker-compose.yml

# 2. 启动容器（无挂载）
echo "启动容器..."
docker-compose up -d

# 3. 等待 PolarDB-X 就绪
echo "等待 PolarDB-X 就绪（约 60-90 秒）..."
for i in $(seq 1 90); do
  if docker exec polardb-x mysql -h127.0.0.1 -P8527 -upolardbx_root -p123456 -e 'select 1' 2>/dev/null; then
    echo "PolarDB-X 已就绪"
    break
  fi
  sleep 2
  echo -n "."
done
echo ""

# 4. 优雅停止，确保数据落盘后再拷贝
echo "优雅停止容器..."
docker-compose stop -t 30

# 5. 拷贝整个 run 目录（含 GMS、DN、CDC 等）
echo "拷贝数据到 ./data ..."
rm -rf data
docker cp polardb-x:/home/polarx/polardbx/build/run ./data

# 6. 删除容器
docker-compose down

# 7. 恢复 volume 配置
mv docker-compose.yml.bak docker-compose.yml 2>/dev/null || sed -i 's|      # - \./data:/home/polarx|      - \./data:/home/polarx|' docker-compose.yml

echo ""
echo "=== 初始化完成 ==="
echo "数据已保存到 ./data，volume 已启用。执行: docker-compose up -d"
