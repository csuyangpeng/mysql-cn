# TiUP 部署（nocontainer 模式）

在 `tiup-nocontainer` 目录下执行，按步骤 1→2→3→4 完成部署与同步。

## 脚本一览

| 脚本 | 用途 |
|------|------|
| `deploy-cluster.sh` | 首次部署集群（需 topology-a/b.yaml） |
| `start-cluster.sh` | 启动已部署的集群 |
| `setup-replication.sh` | 建立 27→28 的 TiCDC 同步 |
| `stop-cleanup.sh` | 停止并销毁集群，可选清理数据 |

---

## 1. 首次部署

集群未部署时执行，需 10.18.1.27、10.18.1.28 可 SSH 登录。

### 免密部署（推荐）

```bash
cd ~/mysql-cn/tiup-nocontainer

# 1.1 生成密钥（若无）
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

# 1.2 拷贝公钥到目标机（拓扑中 user 为 sder）
ssh-copy-id sder@10.18.1.27
ssh-copy-id sder@10.18.1.28

# 1.3 验证免密登录
ssh sder@10.18.1.27 "whoami"
ssh sder@10.18.1.28 "whoami"

# 1.4 部署（自动确认，无需输入密码）
chmod +x deploy-cluster.sh
./deploy-cluster.sh
```

### 密码部署

```bash
USE_PASSWORD=1 ./deploy-cluster.sh
# 会提示输入 SSH 密码
```

---

## 2. 启动集群

```bash
cd ~/mysql-cn/tiup-nocontainer

chmod +x start-cluster.sh
./start-cluster.sh
```

---

## 3. 建立 27 → 28 同步

```bash
cd ~/mysql-cn/tiup-nocontainer

# 设置 root 密码（若未设置）
mysql -h10.18.1.27 -P4000 -uroot -e "ALTER USER 'root'@'%' IDENTIFIED BY '123456';"
mysql -h10.18.1.28 -P4000 -uroot -e "ALTER USER 'root'@'%' IDENTIFIED BY '123456';"

# 执行同步脚本（若提示 ineligible tables 输入 y）
chmod +x setup-replication.sh
echo y | ROOT_PASS=123456 ./setup-replication.sh
```

### 手动创建 Changefeed（可选）

```bash
tiup cdc:v6.5.0 cli changefeed create \
  --server=http://10.18.1.27:8300 \
  --sink-uri="mysql://root:123456@10.18.1.28:4000/" \
  --changefeed-id="a-to-b" \
  --start-ts=0 \
  --config=./cdc-config.toml
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
| 查看 changefeed | `tiup cdc:v6.5.0 cli changefeed list --server=http://10.18.1.27:8300` |
| 查看详情 | `tiup cdc:v6.5.0 cli changefeed query -c a-to-b --server=http://10.18.1.27:8300` |
| 暂停 | `tiup cdc:v6.5.0 cli changefeed pause -c a-to-b --server=http://10.18.1.27:8300` |
| 恢复 | `tiup cdc:v6.5.0 cli changefeed resume -c a-to-b --server=http://10.18.1.27:8300` |

---

## 6. 验证 TiCDC（调试用）

```bash
tiup cdc:v6.5.0 cli capture list --server=http://10.18.1.27:8300
tiup cdc:v6.5.0 cli processor list --server=http://10.18.1.27:8300
```

---

## 7. 故障排查：新增表不同步

若使用旧配置创建的 changefeed，需重建并指定 `cdc-config.toml`：

```bash
tiup cdc:v6.5.0 cli changefeed remove -c a-to-b --server=http://10.18.1.27:8300
ROOT_PASS=123456 ./setup-replication.sh
```

---

## 8. 停止与清理集群

```bash
cd ~/mysql-cn/tiup-nocontainer

# 停止并销毁（保留数据目录）
chmod +x stop-cleanup.sh
./stop-cleanup.sh
# 销毁后需重新 deploy 才能再部署

# 彻底清理（含数据目录，需在 27、28 上手动执行）
CLEAN_DATA=true ./stop-cleanup.sh
# 然后执行：
# ssh 10.18.1.27 'sudo rm -rf /tidb-data /tidb-deploy'
# ssh 10.18.1.28 'sudo rm -rf /tidb-data /tidb-deploy'
```

### 分步执行

| 操作 | 命令 |
|------|------|
| 启动 cluster-a | `tiup cluster start tidb-cluster-a` |
| 启动 cluster-b | `tiup cluster start tidb-cluster-b` |
| 删除 changefeed | `tiup cdc:v6.5.0 cli changefeed remove -c a-to-b --server=http://10.18.1.27:8300` |
| 停止 cluster-a | `tiup cluster stop tidb-cluster-a` |
| 停止 cluster-b | `tiup cluster stop tidb-cluster-b` |
| 销毁 cluster-a | `tiup cluster destroy tidb-cluster-a -y` |
| 销毁 cluster-b | `tiup cluster destroy tidb-cluster-b -y` |
| 清理数据（27） | `ssh 10.18.1.27 'sudo rm -rf /tidb-data /tidb-deploy'` |
| 清理数据（28） | `ssh 10.18.1.28 'sudo rm -rf /tidb-data /tidb-deploy'` |
