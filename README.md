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

### 主从复制（mysql-ha）

```bash
cd mysql-ha
docker-compose up -d
```

- 主库端口 **13306**，从库端口 **13307**
- `repl-setup` 容器自动配置主从复制后退出
- 连接主库写、从库读实现读写分离

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

### 主从/HA 说明

单容器 PolarDB-X 为开发测试模式，无传统主从。生产级 HA 需使用 **PXD** 或 **K8s** 部署多节点集群，详见 [PolarDB-X 部署文档](https://doc.polardbx.com/deployment/topics/deploy-by-pxd.html)。

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

### 标准形式（tidb-std，真实 TiKV）

```bash
cd tidb-std
docker-compose up -d
```

- 1 PD + 1 TiKV + 1 TiDB，真实 TiKV，支持 CommonHandle
- 端口 **13306**，数据持久化到 `./data/pd`、`./data/tikv`

### 分布式集群/HA（tidb-ha）

```bash
cd tidb-ha
docker-compose up -d
```

- 1 PD + 3 TiKV + 1 TiDB，Raft 多副本，具备 HA 能力
- 端口 **13306**，`tidb-init` 容器自动设置 root 密码并执行 `init/` 脚本
- 资源需求约 8GB 内存

### 两物理节点 HA 部署

详见 [TiDB 两节点高可用部署](docs/TiDB-两节点高可用部署.md)：使用 TiUP 在两台物理机上混部 PD×3、TiKV×3、TiDB×2，实现有限高可用（可容忍“少数派”节点故障）。

### 主从复制（tidb-replica）

```bash
# 10.18.1.28 上：cd tidb-replica/secondary && docker-compose up -d
# 10.18.1.27 上：cd tidb-replica/primary && docker-compose up -d
# 10.18.1.27 上：cd tidb-replica/scripts && ./setup-replication.sh
```

双节点主从复制，**无需 MinIO**，TiCDC 增量同步。主故障时备升主，原主恢复后不抢占，详见 [tidb-replica/README.md](tidb-replica/README.md)。

---

## 统一连接参数

| 参数 | 值 |
|------|-----|
| Host | 127.0.0.1 |
| Port | 13306 |
| User | root |
| Password | 123456 |

三种数据库均使用上述参数连接，便于应用切换数据源。
