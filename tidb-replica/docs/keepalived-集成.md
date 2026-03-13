# TiDB 主从 + Keepalived 集成

Keepalived 负责 VIP 漂移，应用始终连接 VIP，无需改连接地址。

## 架构

```
                    VIP (如 10.18.1.100)
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    10.18.1.27       10.18.1.28     应用连接
    (主) keepalived  (备) keepalived   VIP:4000
    TiDB:4000        TiDB:4000
```

- **正常**：VIP 在主机 10.18.1.27，应用连 VIP:4000 → 主 TiDB
- **主故障**：VIP 漂到 10.18.1.28，应用连 VIP:4000 → 备 TiDB
- **原主恢复**：执行 `recovery.sh` 建立反向同步，VIP 仍可留在当前主（不抢占）

## 1. 安装 Keepalived

```bash
# Ubuntu/Debian
apt install keepalived

# CentOS/RHEL
yum install keepalived
```

## 2. 健康检查脚本

Keepalived 通过脚本判断 TiDB 是否可用，决定是否释放 VIP。

```bash
# /etc/keepalived/check_tidb.sh
#!/bin/bash
# 检查本机 TiDB 是否可连接
mysql -h127.0.0.1 -P4000 -uroot -p123456 -e 'SELECT 1' 2>/dev/null
exit $?
```

```bash
chmod +x /etc/keepalived/check_tidb.sh
```

## 3. 主节点配置 (10.18.1.27)

`/etc/keepalived/keepalived.conf`：

```
vrrp_script check_tidb {
    script "/etc/keepalived/check_tidb.sh"
    interval 3
    weight -20
    fall 2
    rise 1
}

vrrp_instance VI_TIDB {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass tidb123
    }
    virtual_ipaddress {
        10.18.1.100
    }
    track_script {
        check_tidb
    }
}
```

> `interface` 改为实际网卡名（如 `ens33`），`10.18.1.100` 改为规划好的 VIP。

## 4. 备节点配置 (10.18.1.28)

```
vrrp_script check_tidb {
    script "/etc/keepalived/check_tidb.sh"
    interval 3
    weight -20
    fall 2
    rise 1
}

vrrp_instance VI_TIDB {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 90
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass tidb123
    }
    virtual_ipaddress {
        10.18.1.100
    }
    track_script {
        check_tidb
    }
}
```

## 5. 启动

```bash
systemctl enable keepalived
systemctl start keepalived
```

## 6. 应用连接

应用统一连接 **VIP:4000**，例如：

```
mysql -h10.18.1.100 -P4000 -uroot -p123456
```

主备切换时，VIP 自动漂移，应用无需改配置。

## 7. 与 TiCDC 的配合

| 阶段 | Keepalived | TiCDC |
|------|------------|-------|
| 主故障 | VIP 漂到备 | 原主→备 的 changefeed 自动停止 |
| 应用 | 连 VIP，自动到备 | - |
| 原主恢复 | 主优先级高，但可保持 VIP 在备 | 执行 `recovery.sh` 建立反向同步 |

**不抢占**：原主恢复后，若希望 VIP 不漂回原主，需在 failover 后调整优先级：
- 将原主 (10.18.1.27) 的 `priority` 改为 80
- 备 (10.18.1.28) 保持 90 或更高
- 重启原主上的 keepalived，VIP 会留在当前主

## 8. 可选：状态变化时执行脚本

在 `vrrp_instance` 中增加 `notify_master` / `notify_backup`，在角色变化时执行脚本（如发告警、触发 `recovery.sh`）：

```
vrrp_instance VI_TIDB {
    ...
    notify_master "/path/to/on_master.sh"
    notify_backup "/path/to/on_backup.sh"
}
```
