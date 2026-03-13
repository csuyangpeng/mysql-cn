# TiDB 主从复制（双节点高可用，简化版）

在两台物理机部署 TiDB 主从复制，**无需 MinIO**，支持主故障时备升主，且原主恢复后**不抢占**。

## 架构

```
10.18.1.27 (主)                        10.18.1.28 (备)
┌─────────────────────────┐           ┌─────────────────────────┐
│  PD + TiKV + TiDB + TiCDC│ ────────► │  PD + TiKV + TiDB + TiCDC│
│  写流量                  │  TiCDC    │  读流量 / 故障时升主      │
└─────────────────────────┘  增量同步  └─────────────────────────┘
```

**故障切换**：主挂 → 备升主 → 应用切到备  
**恢复策略**：原主恢复后作为新备，不抢占，由当前主反向同步到原主。

## 部署步骤

### 1. 部署从集群（10.18.1.28）

```bash
cd tidb-replica/secondary
docker-compose up -d
```

### 2. 部署主集群（10.18.1.27）

```bash
cd tidb-replica/primary
docker-compose up -d
```

### 3. 配置主从复制

```bash
# 在 10.18.1.27 上执行（需 mysql 客户端）
cd tidb-replica/scripts
chmod +x setup-replication.sh
./setup-replication.sh
```

## 故障切换流程

### 主挂了 → 备升主

```bash
# 在任意可访问两集群的机器执行
./failover.sh
# 将应用连接改为 10.18.1.28:4000
```

### 原主恢复 → 建立反向同步（不抢占）

```bash
# 在 10.18.1.28 上执行
./recovery.sh
# 应用继续连 10.18.1.28，原主 10.18.1.27 作为新备
```

## 连接参数

| 场景       | 地址                          |
|------------|-------------------------------|
| 正常（主写）| `mysql -h10.18.1.27 -P4000 -uroot -p123456` |
| 故障后（备升主）| `mysql -h10.18.1.28 -P4000 -uroot -p123456` |

## 常用操作

| 操作       | 命令 |
|------------|------|
| 查看同步状态 | `docker exec tidb-primary-ticdc cdc cli changefeed list --server=http://127.0.0.1:8300` |
| 反向同步状态 | `docker exec tidb-secondary-ticdc cdc cli changefeed list --server=http://127.0.0.1:8300` |

## 目录结构

```
tidb-replica/
├── primary/
├── secondary/
├── scripts/
│   ├── setup-replication.sh
│   ├── failover.sh
│   ├── recovery.sh
│   ├── check_tidb.sh              # Keepalived 健康检查
│   ├── keepalived-master.conf     # Keepalived 主节点示例
│   └── keepalived-backup.conf     # Keepalived 备节点示例
├── docs/
│   └── keepalived-集成.md
└── init/
```

## Keepalived 集成

配合 Keepalived 做 VIP 漂移，应用固定连接 VIP，无需改连接地址。详见 [docs/keepalived-集成.md](docs/keepalived-集成.md)。

要点：
- VIP 在主/备间漂移，应用连 `VIP:4000`
- 健康检查脚本检测本机 TiDB 是否可用
- 不抢占：主节点 `priority` 可低于备，使 VIP 留在当前主

## 注意事项

- **初始数据**：两集群均需为空，或从集群已包含主集群数据，否则可能有数据不一致。
- **防火墙**：两台机器互通，放行 4000、2379、8300。
- **不抢占**：原主恢复后执行 `recovery.sh`，仅建立反向同步，不会重新成为主。
