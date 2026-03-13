# TiDB 两物理节点高可用部署指南

## 一、架构约束说明

TiDB 基于 Raft 协议，对节点数有硬性要求：

| 组件 | 最小 HA 要求 | 原因 |
|------|-------------|------|
| **PD** | 3 个实例 | Raft 需多数派（2/3）形成 quorum |
| **TiKV** | 3 个实例 | 默认 max-replicas=3，需 2 副本在线才能写入 |
| **TiDB** | 2 个实例 | 无状态，可任意扩展 |

**两节点下的策略**：在 2 台物理机上**混部多实例**，使 PD、TiKV 各有 3 个实例，并尽量分散到两台机器。

---

## 二、推荐拓扑（2 台物理机）

```
节点 A (10.0.1.1)              节点 B (10.0.1.2)
├── PD-1                        ├── PD-2
├── PD-2                        ├── PD-3
├── TiDB-1                      ├── TiDB-2
├── TiKV-1                      ├── TiKV-2
└── TiKV-2                      └── TiKV-3
```

- **PD**：3 实例（2+1）→ 节点 B 故障时仍可形成 quorum
- **TiKV**：3 实例（2+1）→ 节点 B 故障时仍可形成 quorum
- **TiDB**：2 实例（1+1）→ 任一台故障均可继续服务

**容灾能力**：仅能容忍**节点 B 故障**；节点 A 故障时，PD 和 TiKV 会失去多数派，集群不可用。

**对称 HA**：若需两台机器任意一台故障都能继续服务，需至少 **3 台物理机**。

---

## 三、TiUP 拓扑文件

创建 `topology-2node.yaml`（将 `10.0.1.1`、`10.0.1.2` 替换为实际 IP）：

```yaml
global:
  user: "tidb"
  ssh_port: 22
  deploy_dir: "/tidb-deploy"
  data_dir: "/tidb-data"

server_configs:
  pd:
    replication.location-labels: ["az", "host"]

pd_servers:
  - host: 10.0.1.1
    name: "pd-1"
    client_port: 2379
    peer_port: 2380
  - host: 10.0.1.1
    name: "pd-2"
    client_port: 2381
    peer_port: 2382
  - host: 10.0.1.2
    name: "pd-3"
    client_port: 2379
    peer_port: 2380

tidb_servers:
  - host: 10.0.1.1
  - host: 10.0.1.2

tikv_servers:
  - host: 10.0.1.1
    port: 20160
    config:
      server.labels: { az: "a", host: "1" }
  - host: 10.0.1.1
    port: 20161
    config:
      server.labels: { az: "a", host: "2" }
  - host: 10.0.1.2
    port: 20160
    config:
      server.labels: { az: "b", host: "3" }

monitoring_servers:
  - host: 10.0.1.1

grafana_servers:
  - host: 10.0.1.1

alertmanager_servers:
  - host: 10.0.1.1
```

> 同主机多实例必须配置不同端口：PD 的 `client_port`/`peer_port`，TiKV 的 `port`。

---

## 四、部署步骤

### 1. 安装 TiUP

```bash
curl --proto '=https' --tlsv1.2 -sSf https://tiup-mirrors.pingcap.com/install.sh | sh
source ~/.bashrc
```

### 2. 部署集群

```bash
tiup cluster deploy tidb-2node v7.5.0 topology-2node.yaml
tiup cluster start tidb-2node
```

### 3. 验证

```bash
tiup cluster display tidb-2node
mysql -h 10.0.1.1 -P 4000 -u root
```

---

## 五、Label 与副本分布

为让副本尽量分散到两台机器，建议配置 PD：

```bash
pd-ctl config set replication.location-labels "az,host"
```

TiKV 的 `server.labels` 需与上述一致，例如 `az` 区分机房，`host` 区分主机。

---

## 六、方案对比

| 方案 | 节点数 | 容灾能力 | 适用场景 |
|------|--------|----------|----------|
| 2 节点混部 | 2 | 仅能容忍“少数派”节点故障 | 资源有限、可接受非对称 HA |
| 3 节点标准 | 3 | 可容忍任意 1 节点故障 | 生产推荐 |
| 同城双 AZ | 6+ | 机房级容灾，RPO=0 | 金融、核心业务 |

---

## 七、参考文档

- [最小拓扑架构](https://docs.pingcap.com/zh/tidb/stable/minimal-deployment-topology/)
- [单区域双 AZ 部署](https://docs.pingcap.com/zh/tidb/stable/two-data-centers-in-one-city-deployment)
- [TiUP 拓扑配置](https://docs.pingcap.com/zh/tidb/stable/tiup-cluster-topology-reference)
