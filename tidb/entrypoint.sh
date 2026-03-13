#!/bin/sh
set +H

# Generate bootstrap.sql for fresh installs
PASS=$(echo "$TIDB_ROOT_PASSWORD" | sed "s/'/''/g")
cat > /tmp/bootstrap.sql << EOF
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$PASS';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# Start TiDB in background
/tidb-server --store=mocktikv --path=/tmp/tidb --initialize-sql-file=/tmp/bootstrap.sql &
TIDB_PID=$!

# Wait for TiDB to be ready
echo "Waiting for TiDB to be ready..."
until wget -q -O /dev/null http://127.0.0.1:10080/status 2>/dev/null; do
  sleep 2
done

# Set password for remote connections (root@'%') - for both fresh and existing data
if mysql -h 127.0.0.1 -P 4000 -u root -e 'SELECT 1' 2>/dev/null; then
  mysql -h 127.0.0.1 -P 4000 -u root -e "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$PASS';"
  mysql -h 127.0.0.1 -P 4000 -u root -e "ALTER USER 'root'@'%' IDENTIFIED BY '$PASS';"
  mysql -h 127.0.0.1 -P 4000 -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
  mysql -h 127.0.0.1 -P 4000 -u root -e "FLUSH PRIVILEGES;"
  echo "Root password set for remote access (root@'%')."
fi

# Keep container running
wait $TIDB_PID
