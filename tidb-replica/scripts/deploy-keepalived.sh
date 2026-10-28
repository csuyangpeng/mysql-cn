#!/bin/bash
# 在单台主机上安装/更新 Keepalived 配置
# 用法（需 root）：
#   10.18.1.27: sudo ./deploy-keepalived.sh master
#   10.18.1.28: sudo ./deploy-keepalived.sh backup
#
# 会先备份已有的 /etc/keepalived/keepalived.conf（含软链接指向的真实文件）。
set -euo pipefail

ROLE="${1:-}"
case "$ROLE" in
  master|backup) ;;
  *) echo "用法: $0 master|backup"; exit 1 ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 执行（sudo $0 $ROLE）"
  exit 1
fi

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
DST_DIR=/etc/keepalived
STAMP=$(date +%Y%m%d%H%M%S)

command -v keepalived >/dev/null 2>&1 || { echo "未安装 keepalived，请先 apt-get install -y keepalived"; exit 1; }

mkdir -p "$DST_DIR"

# 备份已有配置：先解析软链接，避免 cp 写穿到原文件
if [ -e "$DST_DIR/keepalived.conf" ]; then
  cp -L "$DST_DIR/keepalived.conf" "$DST_DIR/keepalived.conf.bak.$STAMP"
  echo "已备份: $DST_DIR/keepalived.conf.bak.$STAMP"
fi

# 如果原配置是软链接，先删链接再写真实文件
[ -L "$DST_DIR/keepalived.conf" ] && rm -f "$DST_DIR/keepalived.conf"

install -m 644 "$SRC_DIR/keepalived-$ROLE.conf" "$DST_DIR/keepalived.conf"
install -m 755 "$SRC_DIR/check_tidb.sh" "$DST_DIR/check_tidb.sh"
install -m 755 "$SRC_DIR/notify.sh" "$DST_DIR/notify.sh"

# 网卡名与配置一致性检查
IFACE=$(awk '/^[[:space:]]*interface[[:space:]]/{print $2; exit}' "$DST_DIR/keepalived.conf")
if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "警告：配置中的网卡 $IFACE 不存在，请修改 interface 后重试"
  ip -brief link | awk '{print "  "$1}'
  exit 1
fi

# 语法检查
keepalived -t -f "$DST_DIR/keepalived.conf"

systemctl enable keepalived >/dev/null 2>&1 || true
systemctl restart keepalived
sleep 2

echo "keepalived 已启动（$ROLE）"
systemctl is-active keepalived
ip -brief addr show "$IFACE" | sed 's/^/  /'
