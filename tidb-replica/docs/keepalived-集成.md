# Keepalived 集成说明

本文只讲 Keepalived 部分的原理、部署与排错。完整部署与演练见
[../README.md](../README.md)，总体设计见 [主备容灾总体方案.md](主备容灾总体方案.md)。

## 1. 架构

```
                 VIP 10.18.1.100:4000
                          │
          ┌───────────────┴───────────────┐
          │                               │
   10.18.1.27 (主)                  10.18.1.28 (备)
   keepalived MASTER                keepalived BACKUP
   TiDB 4000 (0.0.0.0)              TiDB 4000 (0.0.0.0)
```

- 正常：VIP 在 .27，应用连 `10.18.1.100:4000`。
- .27 TiDB 不可用：健康检查失败 → .27 进入 FAULT → 释放 VIP →
  .28 收不到通告成为 MASTER → VIP 漂到 .28。
- .27 恢复：健康检查通过后回到 BACKUP，**不抢回** VIP。

## 2. 三个关键配置

### 2.1 双 BACKUP + nopreempt

两端都写 `state BACKUP`，靠 `priority`（100 / 90）决定初始 MASTER。
`nopreempt` 保证主恢复后不抢回，避免 VIP 来回漂移。

> `nopreempt` 只在 BACKUP 状态生效，所以**两端都必须是 BACKUP**。

### 2.2 track_script 不配 weight

```conf
vrrp_script check_tidb {
    script "/etc/keepalived/check_tidb.sh"
    interval 3
    timeout 2
    fall 2
    rise 1
    # 不要写 weight
}
```

配了 `weight -20` 只会把优先级降到 80，但备站也是 `nopreempt`，
不会因为对方优先级降低而接管。不配 `weight` 时，脚本失败会让本节点进入
**FAULT** 并释放 VIP，备站才能在主站停止通告后接管。

### 2.3 unicast

现网组播不可靠，必须指定单播对端：

```conf
unicast_src_ip 10.18.1.27
unicast_peer {
    10.18.1.28
}
```

### 2.4 脚本安全（keepalived 2.2+）

```conf
global_defs {
    enable_script_security
    script_user root
}
```

不加会报 `SECURITY VIOLATION - scripts are being executed but script_security not enabled`。
`enable_script_security` 还会检查脚本路径不能被非 root 用户写入，所以脚本放在
`/etc/keepalived/`（root 755）即可。

## 3. 健康检查

`/etc/keepalived/check_tidb.sh` 三项全过才返回 0：

```bash
#!/bin/bash
set -u
curl -fsS --max-time 2 http://127.0.0.1:10080/status >/dev/null 2>&1 || exit 1
curl -fsS --max-time 2 http://127.0.0.1:2379/pd/api/v1/health >/dev/null 2>&1 || exit 1
stores=$(curl -fsS --max-time 2 http://127.0.0.1:2379/pd/api/v1/stores 2>/dev/null) || exit 1
echo "$stores" | grep -Eq '"state_name"[[:space:]]*:[[:space:]]*"Up"' || exit 1
```

- 覆盖 TiDB 进程、PD、TiKV，避免 TiDB 活着但存储不可用时 VIP 仍停留。
- 全部使用 TiDB/PD 自带 HTTP 接口，不依赖 MySQL 客户端。
- PD 返回的是格式化 JSON（冒号后有空格），grep 必须容忍空白。

## 4. 部署

```bash
# 先 .27，后 .28
sudo ./scripts/deploy-keepalived.sh master    # 在 10.18.1.27
sudo ./scripts/deploy-keepalived.sh backup    # 在 10.18.1.28
```

脚本会：

1. 备份已有 `/etc/keepalived/keepalived.conf`（解析软链接后备份真实文件）；
2. 安装配置、`check_tidb.sh`、`notify.sh`；
3. 校验网卡存在；
4. `keepalived -t` 语法检查；
5. `systemctl enable/restart keepalived`。

## 5. 验证

```bash
# VIP 只在 .27
ip -4 addr show ens3 | grep 10.18.1.100

# 状态文件：.27=MASTER，.28=BACKUP
sudo cat /run/tidb-dr-state

# 经 VIP 访问
curl -s -o /dev/null -w '%{http_code}\n' http://10.18.1.100:10080/status
```

## 6. 排错

| 现象 | 原因 | 处理 |
|---|---|---|
| `SECURITY VIOLATION` | 未启用 `enable_script_security` | 在 `global_defs` 中启用，`script_user root` |
| VIP 不漂移 | `track_script` 配了 `weight` | 去掉 `weight`，让脚本失败进入 FAULT |
| 主恢复后 VIP 被抢回 | 未配 `nopreempt` 或 state 写成 MASTER | 两端改 `state BACKUP` + `nopreempt` |
| 双 master / VIP 冲突 | 组播不通或未配 unicast | 配 `unicast_src_ip` / `unicast_peer` |
| 脚本一直成功但站点不可用 | 只检查了 TiDB 进程 | 使用三项健康检查（TiDB + PD + TiKV） |
| 初始 master 是 .28 | 先启动了 .28 | 先启 .27；或停 .28 的 keepalived 让 .27 接管后再启 .28 |

日志：

```bash
journalctl -u keepalived -f
tail -f /var/log/keepalived-tidb.log
```
