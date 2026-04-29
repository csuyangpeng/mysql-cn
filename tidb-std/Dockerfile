# 在官方 tidb-server 上增加协议兼容客户端，供 entrypoint 执行 /init 下 SQL
FROM swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/pingcap/tidb:v8.5.0
USER root
RUN set -eux; \
    if command -v dnf >/dev/null 2>&1; then \
      dnf install -y mysql && dnf clean all; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y mysql && microdnf clean all; \
    elif command -v yum >/dev/null 2>&1; then \
      yum install -y mysql && yum clean all; \
    else \
      echo "未找到 dnf/microdnf/yum，请根据基础镜像改 Dockerfile 安装客户端" >&2; \
      exit 1; \
    fi
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["--store=tikv", "--path=pd:2379"]
