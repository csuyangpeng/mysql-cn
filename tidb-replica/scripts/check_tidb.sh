#!/bin/bash
# Keepalived 健康检查：本机 TiDB 是否可连接
# 复制到 /etc/keepalived/check_tidb.sh 并 chmod +x
mysql -h127.0.0.1 -P4000 -uroot -p123456 -e 'SELECT 1' 2>/dev/null
exit $?
