# TiDB 两节点主备容灾（VIP 接入）

在两台主机上各部署一套独立的 TiDB 集群，通过 TiCDC 做单向增量同步，
用宿主机 Keepalived 提供 VIP `10.18.1.100`。主站故障时 VIP 自动漂到备站，
备站升主；原主恢复后建立反向同步，追平后人工回切。

```
10.18.1.27 (主)                          10.18.1.28 (备)
┌───────────────────────────┐            ┌───────────────────────────┐
│ PD + TiKV + TiDB + TiCDC  │  TiCDC     │ PD + TiKV + TiDB + TiCDC  │
│ 172.19.0.x / 127.0.0.1    │ ─────────► │ 172.20.0.x / 127.0.0.1    │
└─────────────┬─────────────┘  正向同步  └─────────────┬─────────────┘
              │                                        │
        ens3: 10.18.1.27                        ens3: 10.18.1.28
              └──────── VIP 10.18.1.100 ───────────────┘
                    Keepalived (双 BACKUP + nopreempt + unicast)
```

- 应用只连 `10.18.1.100:4000`，不直连单台主机。
- 两套集群互相独立，不做跨站 Raft；站点内单副本，定位为容灾而非高可用。
- 全程使用 TiDB / TiCDC / PD 自带接口，**不依赖 MySQL 数据库或 MySQL 客户端**。

## 端口

| 端口 | 监听 | 用途 |
|---|---|---|
| 4000 | 0.0.0.0 | TiDB SQL，VIP DNAT 入口 |
| 10080 | 0.0.0.0 | TiDB 状态 / 运维 |
| 2379 | 127.0.0.1 | PD，仅本机健康检查与运维 |
| 20160 | 127.0.0.1 | TiKV |
| 8300 | 127.0.0.1 | TiCDC |

## 脚本

| 脚本 | 用途 |
|---|---|
| `scripts/start-cluster.sh` / `stop-cluster.sh` | 启动/停止两站集群（先备后主 / 先主后备） |
| `scripts/setup-replication.sh` | 建立初始正向同步 `primary-to-secondary` |
| `scripts/deploy-keepalived.sh master\|backup` | 在单台主机安装并启动 Keepalived |
| `scripts/failover.sh` | 在备站执行：校验、记录切换 TSO、暂停旧正向 feed |
| `scripts/recovery.sh` | 原主恢复后，在现主执行：建立反向同步 |
| `scripts/switchback.sh` | 在现主执行：追平校验、回切 VIP、重建正向同步 |
| `scripts/check_tidb.sh` | Keepalived 健康检查（TiDB + PD + TiKV） |
| `scripts/notify.sh` | Keepalived 状态记录 |
| `scripts/tidb-entrypoint.sh` | 覆盖镜像入口，首次初始化时设置 GC 保留 24h |

---

## 1. 前置条件

- 两台主机：Ubuntu 22.04，Docker + `docker compose` v2，已安装 `keepalived`。
- 网卡名 `ens3`（不同环境请改 `scripts/keepalived-*.conf` 的 `interface`）。
- 两站路径一致：`/home/sder/mysql-cn/tidb-replica`。
- 镜像已存在（不要重建 `tidb-replica:local`）：
  - `pingcap/pd:v7.5.0`、`pingcap/tikv:v7.5.0`、`pingcap/ticdc:v7.5.0`
  - `registry.cn-hangzhou.aliyuncs.com/10_18_1_2_5000/tidb-replica:local`
- VIP `10.18.1.100` 未被占用；两站 TCP 4000/10080 互通。
- 两站时间同步（TSO 与时间相关，建议 chrony/NTP）。

## 2. 部署

### 2.1 清理旧数据（保留备份）

```bash
# 两站各自执行；不要直接 rm，先改名保留
cd /home/sder/mysql-cn/tidb-replica
sudo mv primary/data   primary/data.bak.$(date +%Y%m%d%H%M%S)     # .27
sudo mv secondary/data secondary/data.bak.$(date +%Y%m%d%H%M%S)   # .28
```

### 2.2 同步代码

以 10.18.1.27 为源，把仓库同步到 10.18.1.28（排除数据目录）：

```bash
cd /home/sder/mysql-cn
tar -czf - --exclude='tidb-replica/*/data' --exclude='tidb-replica/*/data.bak.*' tidb-replica \
  | ssh sder@10.18.1.28 'tar -xzf - -C /home/sder/mysql-cn'
```

### 2.3 启动集群

```bash
cd /home/sder/mysql-cn/tidb-replica
./scripts/start-cluster.sh
```

脚本会先启动 .28、再启动 .27，并等待两端 `/status` 返回 200。
首次启动会初始化 root 密码和 `tidb_gc_life_time=24h`（由 entrypoint 执行）。

检查：

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://10.18.1.27:10080/status
curl -s -o /dev/null -w '%{http_code}\n' http://10.18.1.28:10080/status
```

### 2.4 建立正向同步

在 .27 上执行：

```bash
cd /home/sder/mysql-cn/tidb-replica/scripts
./setup-replication.sh
```

确认状态为 `normal`：

```bash
docker exec tidb-primary-ticdc /cdc cli changefeed query \
  -c primary-to-secondary --server=http://127.0.0.1:8300 --simple
```

> 备库必须为空。若主库已有历史数据，先用 Dumpling/BR 做一次全量，再建 changefeed，
> 否则历史数据不会自动补齐。

### 2.5 部署 Keepalived

**先 .27，后 .28**（顺序反了初始 master 会变成 .28）：

```bash
# 在 10.18.1.27
cd /home/sder/mysql-cn/tidb-replica/scripts
sudo ./deploy-keepalived.sh master

# 在 10.18.1.28
cd /home/sder/mysql-cn/tidb-replica/scripts
sudo ./deploy-keepalived.sh backup
```

脚本会备份已有 `/etc/keepalived/keepalived.conf`（含软链接目标），下发配置与脚本，
执行 `keepalived -t` 语法检查后重启服务。

验证：

```bash
ip -brief addr show | grep 10.18.1.100          # 只在 .27 上有
sudo cat /run/tidb-dr-state                     # .27=MASTER, .28=BACKUP
curl -s -o /dev/null -w '%{http_code}\n' http://10.18.1.100:10080/status
```

### 2.6 业务连通性

```bash
# 经 VIP 连接（<国产 SQL 客户端> 或业务应用）
<client> -h10.18.1.100 -P4000 -uroot -p<password> -e 'SELECT 1'
```

## 3. 验证

### 3.1 同步验证

在主库写入，备库应能查到（DDL 与 DML 都同步）：

```sql
CREATE DATABASE IF NOT EXISTS dr_test;
CREATE TABLE dr_test.t1(id INT PRIMARY KEY, name VARCHAR(50));
INSERT INTO dr_test.t1 VALUES (1,'alpha'),(2,'beta'),(3,'gamma');
```

在备库执行 `SELECT * FROM dr_test.t1`，结果应一致。

### 3.2 同步延迟

```bash
# checkpoint_tso 应持续前进，并与当前 TSO 接近
docker exec tidb-primary-ticdc /cdc cli changefeed query \
  -c primary-to-secondary --server=http://127.0.0.1:8300 --simple
docker exec tidb-primary-ticdc /cdc cli tso query --pd=http://pd:2379
```

## 4. 故障切换演练

### 4.1 注入故障

```bash
# 在 .27 上停掉 TiDB，模拟主库故障
docker stop tidb-primary-sql
```

约 3 秒后检查 VIP：

```bash
# .28 上应出现 10.18.1.100；.27 上消失
ip -brief addr show | grep 10.18.1.100
sudo cat /run/tidb-dr-state
```

### 4.2 备站升主

在 **10.18.1.28** 上：

```bash
cd /home/sder/mysql-cn/tidb-replica/scripts
sudo ./failover.sh
```

脚本会：

1. 校验本机 TiDB / PD 健康；
2. 记录 `TSO_FAILOVER` 到 `/var/lib/tidb-dr/failover-tso`；
3. 若旧主可达，暂停其正向 feed；
4. 校验 VIP 归属；
5. 打印后续动作。

随后确认旧主已停止写入（防止直连双写）：

```bash
ssh sder@10.18.1.27 'docker stop tidb-primary-sql'
```

### 4.3 故障期间写入

应用继续连 VIP 写入，数据落在 .28。演练时可写入带标记的数据，
用于验证后续反向同步。

## 5. 恢复与回切演练

### 5.1 恢复旧主并建立反向同步

```bash
# 1. .27 恢复 TiDB
ssh sder@10.18.1.27 'docker start tidb-primary-sql'

# 2. 确认 .27 健康，但仍是 BACKUP、没有 VIP
ip -brief addr show | grep 10.18.1.100   # 只在 .28

# 3. 在 .28 建立反向同步（自动读取 failover-tso）
cd /home/sder/mysql-cn/tidb-replica/scripts
sudo ./recovery.sh

# 4. 确认故障期间数据已补到 .27
```

`recovery.sh` 会先删除旧的正向 feed，再以 `--start-ts=$TSO_FAILOVER`
创建 `secondary-to-primary`。

### 5.2 回切

先停业务写入（应用摘流量），然后在 **10.18.1.28** 上：

```bash
cd /home/sder/mysql-cn/tidb-replica/scripts
sudo ./switchback.sh
```

固定顺序：

1. 记录 `TSO_CUT`；
2. 等反向 feed 的 checkpoint ≥ `TSO_CUT`，未追平拒绝回切；
3. 删除反向 feed；
4. 在 .27 重建正向 feed，`--start-ts=TSO_CUT`；
5. 停 .28 的 keepalived，VIP 回到 .27；
6. 启动 .28 的 keepalived（BACKUP，不抢占）。

验证：

```bash
# VIP 回到 .27
ip -brief addr show | grep 10.18.1.100
# .28 为 BACKUP
ssh sder@10.18.1.28 'sudo cat /run/tidb-dr-state'
# 正向 feed normal
docker exec tidb-primary-ticdc /cdc cli changefeed list --server=http://127.0.0.1:8300
```

恢复业务写入，经 VIP 写一条数据，确认备站可见。

## 6. 日常运维

```bash
# 集群状态
docker compose -f primary/docker-compose.yml ps
docker compose -f secondary/docker-compose.yml ps

# 健康检查（与 keepalived 使用同一脚本）
sudo /etc/keepalived/check_tidb.sh; echo $?

# changefeed
docker exec tidb-primary-ticdc /cdc cli changefeed list --server=http://127.0.0.1:8300
docker exec tidb-secondary-ticdc /cdc cli changefeed list --server=http://127.0.0.1:8300

# VIP 与状态
ip -4 addr show ens3 | grep 10.18.1.100
sudo cat /run/tidb-dr-state
tail -20 /var/log/keepalived-tidb.log
```

## 7. 注意事项

1. **备份库禁止写入**。备库是独立集群，直连写入会造成分叉。
2. **不要重建 `tidb-replica:local` 镜像**。仓库里的 `tidb/Dockerfile` 与线上镜像不一致，
   重建会让 TiDB 退化为 mocktikv。该镜像只拉取、不重建。
3. **GC 保留 24h** 由 `scripts/tidb-entrypoint.sh` 在首次初始化时设置。
   已运行集群不会重复执行；如需调整，用国产 SQL 客户端执行
   `SET GLOBAL tidb_gc_life_time='24h';`。
4. **切换 TSO 不能丢**。`/var/lib/tidb-dr/failover-tso` 是反向同步的起点，
   丢失会导致故障窗口数据无法补齐。
5. **回切前必须停业务写入**，并等反向同步追平；脚本会拒绝未追平的回切。
6. **旧主恢复后不会自动抢回 VIP**（双 BACKUP + nopreempt），这是刻意设计。
7. 站点内单副本，任一 PD/TiKV 故障整站不可用；本方案只解决站点级容灾。
8. 异步复制存在秒级 RPO，故障瞬间未同步的尾部数据会丢失。

## 附录：关键设计点

- **Keepalived**：双 `state BACKUP` + `nopreempt` + `unicast_src_ip/peer`；
  `track_script` 不配 `weight`（配了在 nopreempt 下备站不会接管）；
  脚本失败进入 FAULT 并释放 VIP。
- **健康检查**：TiDB `/status` + PD `/pd/api/v1/health` + TiKV store `Up`，
  三项全过才算可用。
- **防回环**：回切时先删反向 feed，再建正向 feed，两个方向不同时存在。
- **防双写**：切换后停旧主 TiDB；旧正向 feed 被暂停/删除。
- **数据补齐**：反向 feed 用 `--start-ts=TSO_FAILOVER`，覆盖整个故障窗口。
