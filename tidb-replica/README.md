# TiDB 主从复制（容器版）

在两台物理机（10.18.1.27、10.18.1.28）用 Docker 部署 TiDB 主从复制，支持 DDL+DML 同步、故障切换、反向同步。

## 架构

```
10.18.1.27 (主)                        10.18.1.28 (备)
┌─────────────────────────┐           ┌─────────────────────────┐
│ PD + TiKV + TiDB + TiCDC│ ────────► │ PD + TiKV + TiDB + TiCDC│
│  写流量                  │  TiCDC    │  读流量 / 故障时升主      │
└─────────────────────────┘  增量同步  └─────────────────────────┘
```

## 脚本一览

| 脚本 | 用途 |
|------|------|
| `scripts/start-cluster.sh` | 启动主从容器集群（需 SSH） |
| `scripts/stop-cluster.sh` | 停止主从容器集群 |
| `scripts/setup-replication.sh` | 建立 27→28 的 TiCDC 同步 |
| `scripts/failover.sh` | 主故障时切换说明 |
| `scripts/recovery.sh` | 原主恢复后建立反向同步 |

---

## 1. 部署前准备

将 `tidb-replica` 目录复制到两台机器（或通过 git 拉取），确保路径一致，如 `~/mysql-cn/tidb-replica`。

```bash
# 两台机器均需安装 Docker、Docker Compose
# 互通放行 4000、2379、8300
```

---

## 2. 启动集群

### 方式 A：SSH 远程启动（推荐）

在可 SSH 到 27、28 的机器上执行：

```bash
cd ~/mysql-cn/tidb-replica
chmod +x scripts/*.sh

# 先启动从集群，再启动主集群
./scripts/start-cluster.sh
```

### 方式 B：分别在两台机器上执行

```bash
# 在 10.18.1.28 上
cd ~/mysql-cn/tidb-replica/secondary
docker compose up -d

# 在 10.18.1.27 上
cd ~/mysql-cn/tidb-replica/primary
docker compose up -d
```

---

## 3. 建立同步

在 **10.18.1.27** 上执行（需 mysql 客户端，且能访问 10.18.1.28:4000）。root 密码由 TiDB 环境变量 TIDB_ROOT_PASSWORD=123456 设置：

```bash
cd ~/mysql-cn/tidb-replica/scripts
ROOT_PASS=123456 ./setup-replication.sh
```

或从本机 SSH 执行：

```bash
ssh 10.18.1.27 'cd ~/mysql-cn/tidb-replica/scripts && ROOT_PASS=123456 ./setup-replication.sh'
```

---

## 4. 验证同步

```bash
# 27 上建库表并插入（DDL+DML 会同步到 28）
mysql -h10.18.1.27 -P4000 -uroot -p123456 -e "
  CREATE DATABASE IF NOT EXISTS test;
  CREATE TABLE test.t1(id int PRIMARY KEY, name varchar(50));
  INSERT INTO test.t1 VALUES(1,'a'), (2,'b');
"

# 28 读取
mysql -h10.18.1.28 -P4000 -uroot -p123456 -e "SELECT * FROM test.t1;"
```

---

## 5. 常用命令

| 操作 | 命令 |
|------|------|
| 查看同步状态 | `docker exec tidb-primary-ticdc cdc cli changefeed list --server=http://127.0.0.1:8300` |
| 反向同步状态 | `docker exec tidb-secondary-ticdc cdc cli changefeed list --server=http://127.0.0.1:8300` |

---

## 6. 故障切换

### 主挂了 → 备升主

```bash
# 将应用连接改为 10.18.1.28:4000
./scripts/failover.sh
```

### 原主恢复 → 建立反向同步（不抢占）

```bash
# 在 10.18.1.28 上执行
./scripts/recovery.sh
```

---

## 7. 停止集群

```bash
cd ~/mysql-cn/tidb-replica
./scripts/stop-cluster.sh

# 彻底清理数据
CLEAN_DATA=true ./scripts/stop-cluster.sh
# 然后手动删除 primary/data、secondary/data
```

---

## 连接参数

| 场景 | 地址 |
|------|------|
| 正常（主写） | `mysql -h10.18.1.27 -P4000 -uroot -p123456` |
| 故障后（备升主） | `mysql -h10.18.1.28 -P4000 -uroot -p123456` |

---

## 目录结构

```
tidb-replica/
├── primary/           # 主集群 docker-compose
├── secondary/         # 从集群 docker-compose
├── config/
│   └── cdc-config.toml   # TiCDC 配置（DDL 同步）
├── tidb/                 # 自定义 TiDB 镜像（读取 TIDB_ROOT_PASSWORD 设置 root 密码）
│   ├── Dockerfile
│   └── entrypoint.sh
├── scripts/
│   ├── start-cluster.sh
│   ├── stop-cluster.sh
│   ├── setup-replication.sh
│   ├── failover.sh
│   ├── recovery.sh
│   └── check_tidb.sh
└── docs/
```

## Keepalived 集成

配合 Keepalived 做 VIP 漂移，详见 [docs/keepalived-集成.md](docs/keepalived-集成.md)。
