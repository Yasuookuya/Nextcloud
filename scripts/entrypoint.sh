#!/bin/bash

# Template-style entrypoint for Nextcloud Railway deployment
# Based on working mod_php setup with auto-green section 9

set -e

# Debug environment
echo "=== DEBUG: Environment ==="
env | grep -E "(POSTGRES|REDIS|NEXTCLOUD|PORT|RAILWAY)" | sort || true

# Parse database connection
if [ -n "$DATABASE_URL" ]; then
    # Railway DATABASE_URL format
    POSTGRES_HOST=$(echo $DATABASE_URL | sed -n 's|.*@\([^:]*\):\([^/]*\)/.*|\1|p')
    POSTGRES_PORT=$(echo $DATABASE_URL | sed -n 's|.*@\([^:]*\):\([^/]*\)/.*|\2|p')
    POSTGRES_USER=$(echo $DATABASE_URL | sed -n 's|.*://\([^:]*\):.*|\1|p')
    POSTGRES_PASSWORD=$(echo $DATABASE_URL | sed -n 's|.*:\([^@]*\)@.*|\1|p')
    POSTGRES_DB=$(echo $DATABASE_URL | basename "$DATABASE_URL")
else
    # PG* variables
    POSTGRES_HOST="${PGHOST:-}"
    POSTGRES_PORT="${PGPORT:-5432}"
    POSTGRES_USER="${PGUSER:-postgres}"
    POSTGRES_PASSWORD="${PGPASSWORD:-}"
    POSTGRES_DB="${PGDATABASE:-railway}"
fi

# Redis connection
if [ -n "$REDIS_URL" ]; then
    REDIS_HOST=$(echo $REDIS_URL | sed -n 's|.*@\([^:]*\):\([^/]*\)/.*|\1|p')
    REDIS_PORT=$(echo $REDIS_URL | sed -n 's|.*@\([^:]*\):\([^/]*\)/.*|\2|p')
    REDIS_PASSWORD=$(echo $REDIS_URL | sed -n 's|.*:\([^@]*\)@.*|\1|p')
else
    REDIS_HOST="${REDIS_HOST:-${REDISHOST:-}}"
    REDIS_PORT="${REDIS_PORT:-${REDISPORT:-6379}}"
    REDIS_PASSWORD="${REDIS_PASSWORD:-${REDISPASSWORD:-}}"
fi

echo "ID1-DB: $POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB ($POSTGRES_USER)"

# Wait for DB and Redis (up to 60s)
echo "ID1-WAIT: Waiting for PostgreSQL and Redis..."
timeout=60
while [ $timeout -gt 0 ]; do
  if pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" 2>/dev/null && \
     redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
    echo "ID1-WAIT OK: Services ready"
    break
  fi
  echo "ID1-WAIT: Waiting... ($timeout s left)"
  sleep 5
  timeout=$((timeout - 5))
done
if [ $timeout -le 0 ]; then
  echo "ID1-WAIT FAIL: Services not ready, continuing anyway"
fi

if [ ! -f "/var/www/html/config/config.php" ] || ! grep -q "'installed' => true," "/var/www/html/config/config.php" 2>/dev/null; then
  echo "ID2-CONFIG-GEN: Generating config.php..."
  # Dynamic trusted_domains
  TRUSTED_ARRAY="'$RAILWAY_PUBLIC_DOMAIN', 'localhost'"
  if [ -n "$NEXTCLOUD_TRUSTED_DOMAINS" ]; then
    IFS=' ' read -ra DOMAINS <<< "$NEXTCLOUD_TRUSTED_DOMAINS"
    for d in "${DOMAINS[@]}"; do TRUSTED_ARRAY+=" '$d',"; done
    TRUSTED_ARRAY=${TRUSTED_ARRAY%,}
  fi
  cat > /var/www/html/config/config.php << EOF
  <?php
\$CONFIG = array (
  'instanceid' => '$(openssl rand -hex 10)',
  'passwordsalt' => '$(openssl rand -base64 30)',
  'secret' => '$(openssl rand -base64 48)',
  'trusted_domains' => array ($TRUSTED_ARRAY),
  'datadirectory' => '$NEXTCLOUD_DATA_DIR',
  'dbtype' => 'pgsql',
  'version' => '32.0.3.0',
  'overwrite.cli.url' => 'https://$RAILWAY_PUBLIC_DOMAIN',
  'overwriteprotocol' => 'https',
  'dbname' => '$POSTGRES_DB',
  'dbhost' => '$POSTGRES_HOST',
  'dbport' => '$POSTGRES_PORT',
  'dbuser' => '$POSTGRES_USER',
  'dbpassword' => '$POSTGRES_PASSWORD',
  'dbtableprefix' => '$NEXTCLOUD_TABLE_PREFIX',
  'memcache.local' => '\\\\OCP\\\\Memcache\\\\APCu',
  'memcache.distributed' => '\\\\OC\\\\Memcache\\\\Redis',
  'memcache.locking' => '\\\\OC\\\\Memcache\\\\Redis',
  'redis' => array (
    'host' => '$REDIS_HOST',
    'port' => '$REDIS_PORT',
    'password' => '$REDIS_PASSWORD',
    'dbindex' => 0,
  ),
  'loglevel' => 2,
  'maintenance' => false,
  'installed' => false,
);
\$CONFIG_INCLUDES[] = include('/var/www/html/config/nextcloud-optimizations.php');
EOF
chown www-data /var/www/html/config/config.php
echo "ID2-CONFIG-GEN OK"
fi

# Apache port configuration
echo "Listen ${PORT:-80}" > /etc/apache2/ports.conf
echo "ID3-APACHE-PORT OK"

# OCC install if admin vars provided and not already installed
if [ -n "$NEXTCLOUD_ADMIN_USER" ] && ! runuser www-data -c "cd /var/www/html && php occ status 2>/dev/null | grep -q 'installed: true'"; then
    echo "ID4-OCC-INSTALL: Running Nextcloud installation..."
    runuser www-data -c "cd /var/www/html && php occ maintenance:install --database \"pgsql\" --database-name \"$POSTGRES_DB\" --database-host \"$POSTGRES_HOST:$POSTGRES_PORT\" --database-user \"$POSTGRES_USER\" --database-pass \"$POSTGRES_PASSWORD\" --database-table-prefix \"\${NEXTCLOUD_TABLE_PREFIX:-oc_}\" --admin-user \"$NEXTCLOUD_ADMIN_USER\" --admin-pass \"$NEXTCLOUD_ADMIN_PASSWORD\" --data-dir \"$NEXTCLOUD_DATA_DIR\""
    echo "ID4-OCC-INSTALL OK"
else
    echo "ID4-SKIPPED: Nextcloud already installed or no admin vars"
fi

# Post-install upgrade and configuration
if runuser www-data -c "cd /var/www/html && php occ status 2>/dev/null | grep -q 'installed: true'"; then
  echo "ID4-UPGRADE: Running upgrade if needed..."
  runuser www-data -c "cd /var/www/html && php occ upgrade --no-appcode" 2>/dev/null || true

  echo "ID4-POST-CONFIG: Setting trusted domains and configs..."
  # Clear trusted_domains
  runuser www-data -c "cd /var/www/html && php occ config:system:delete trusted_domains" 2>/dev/null || true
  # Set trusted_domains from env
  domains="${NEXTCLOUD_TRUSTED_DOMAINS:-$RAILWAY_PUBLIC_DOMAIN localhost 127.0.0.1 [::1]}"
  IFS=' ' read -ra DOMAINS <<< "$domains"
  for i in "${!DOMAINS[@]}"; do
    runuser www-data -c "cd /var/www/html && php occ config:system:set trusted_domains $i --value=\"${DOMAINS[$i]}\" " 2>/dev/null || true
  done
  runuser www-data -c "cd /var/www/html && php occ config:system:set overwrite.cli.url --value=\"https://$RAILWAY_PUBLIC_DOMAIN\" " 2>/dev/null || true
  runuser www-data -c "cd /var/www/html && php occ config:system:set overwriteprotocol --value https" 2>/dev/null || true
  runuser www-data -c "cd /var/www/html && php occ config:system:set loglevel --value 2" 2>/dev/null || true
  runuser www-data -c "cd /var/www/html && php occ config:system:set memcache.local --value \"\\\\OCP\\\\Memcache\\\\APCu\"" 2>/dev/null || true
  runuser www-data -c "cd /var/www/html && php occ config:system:set memcache.distributed --value \"\\\\OC\\\\Memcache\\\\Redis\"" 2>/dev/null || true
  runuser www-data -c "cd /var/www/html && php occ config:system:set memcache.locking --value \"\\\\OC\\\\Memcache\\\\Redis\"" 2>/dev/null || true
  # Add optimizations include if missing
  if ! grep -q "nextcloud-optimizations.php" /var/www/html/config/config.php 2>/dev/null; then
    echo "\$CONFIG_INCLUDES[] = include('/var/www/html/config/nextcloud-optimizations.php');" >> /var/www/html/config/config.php
  fi
  echo "ID4-POST-CONFIG OK"
fi

# Section 9: Post-install auto-green fixes
echo "ID5-POST-INSTALL-GREEN"
chown -R www-data /var/www/html || true


# Redis configuration
runuser www-data -c "cd /var/www/html && php occ redis:config --host=$REDIS_HOST --port=$REDIS_PORT --password=$REDIS_PASSWORD --dbindex=0" 2>/dev/null || true

# Run fix script
/usr/local/bin/fix-warnings.sh || true

# Files scan
runuser www-data -c "cd /var/www/html && php occ files:scan --all --quiet" 2>/dev/null || true

echo "ID5-GREEN-OK"

echo "ID6-START-SUPERVISOR"
exec supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
