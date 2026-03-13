# mysql-cn

MySQL 兼容数据库基础组件，支持 MySQL、PolarDB-X、TiDB 三种数据库的 Docker 部署。

## 配置对比

| 项目 | MySQL | PolarDB-X | TiDB |
|------|-------|-----------|------|
| 端口映射 | 13306:3306 | 13306:8527 | 13306:4000 |
| 密码环境变量 | MYSQL_ROOT_PASSWORD | POLARDBX_ROOT_PASSWORD | TIDB_ROOT_PASSWORD |
| 数据目录 | ./data | ./data | ./data |
| 初始化 SQL | ./init → docker-entrypoint-initdb.d | ./init → 就绪后执行 | ./init → 就绪后执行 |
| 镜像 | mysql:8.0 | 自定义 (polardbx) | 自定义 (tidb) |
| 默认密码 | 123456 | 123456 | 123456 |

> 三种数据库均使用宿主机端口 **13306**，同一时间只能运行一个。

---

## MySQL

### 启动

```bash
cd mysql
docker-compose up -d
```

### 连接

```bash
mysql -h127.0.0.1 -P13306 -uroot -p123456
```

### 停止

```bash
docker-compose down
```

### 说明

- 首次启动自动初始化，`init/` 目录下的 `.sql` 脚本会在数据目录为空时执行
- 数据持久化到 `./data`

---

## PolarDB-X

### 首次部署（需初始化数据）

```bash
cd polardb-x
./init-data.sh
```

脚本会：启动容器 → 等待就绪 → 优雅停止 → 拷贝数据到 `./data` → 启用持久化

### 启动

```bash
docker-compose up -d
```

### 连接

```bash
mysql -h127.0.0.1 -P13306 -uroot -p123456
```

### 停止

```bash
docker-compose down
```

### 说明

- 首次使用需先执行 `init-data.sh` 完成数据初始化
- 数据持久化到 `./data`（挂载整个 run 目录）
- `init/` 目录下的 `.sql` 脚本在首次启动时执行（数据目录无 `.init_done` 时）

---

## TiDB

### 启动

```bash
cd tidb
docker-compose up -d
```

### 连接

```bash
mysql -h127.0.0.1 -P13306 -uroot -p123456
```

### 停止

```bash
docker-compose down
```

### 说明

- 需先构建基础镜像 `tidb:local`
- 数据持久化到 `./data`
- `init/` 目录下的 `.sql` 脚本在首次启动时执行（数据目录无 `.init_done` 时）

---

## 统一连接参数

| 参数 | 值 |
|------|-----|
| Host | 127.0.0.1 |
| Port | 13306 |
| User | root |
| Password | 123456 |

三种数据库均使用上述参数连接，便于应用切换数据源。
