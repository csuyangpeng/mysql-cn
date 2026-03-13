# FROM pingcap/tidb:v8.5.0
# USER root
# RUN dnf install -y mysql && dnf clean all
FROM tidb:local
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
