#!/bin/bash
set -e

echo "🚀 Starting NextCloud Apache deployment on Railway..."

# Set PostgreSQL variables from DATABASE_URL or Railway PG* variables
if [ -n "$DATABASE_URL" ]; then
    export POSTGRES_HOST=$(echo $DATABASE_URL | sed -n 's|postgresql://[^:]*:[^@]*@\([^:]*\):.*|\1|p')
    export POSTGRES_PORT=$(echo $DATABASE_URL | sed -n 's|postgresql://[^:]*:[^@]*@[^:]*:\([0-9]*\)/.*|\1|p')
    export POSTGRES_USER=$(echo $DATABASE_URL | sed -n 's|postgresql://\([^:]*\):.*|\1|p')
    export POSTGRES_PASSWORD=$(echo $DATABASE_URL | sed -n 's|postgresql://[^:]*:\([^@]*\)@.*|\1|p')
    export POSTGRES_DB=$(echo $DATABASE_URL | sed -n 's|.*/\([^?]*\).*|\1|p')
fi

export POSTGRES_HOST=${POSTGRES_HOST:-$PGHOST}
export POSTGRES_PORT=${POSTGRES_PORT:-$PGPORT}
export POSTGRES_USER=${POSTGRES_USER:-$PGUSER}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$PGPASSWORD}
export POSTGRES_DB=${POSTGRES_DB:-$PGDATABASE}

# Redis defaults
export REDIS_HOST=${REDIS_HOST:-${REDISHOST:-localhost}}
export REDIS_PORT=${REDIS_PORT:-${REDISPORT:-6379}}
export REDIS_PASSWORD=${REDIS_PASSWORD:-${REDISPASSWORD:-}}

# NextCloud defaults
export NEXTCLOUD_DATA_DIR=${NEXTCLOUD_DATA_DIR:-/var/www/html/data}
export NEXTCLOUD_TABLE_PREFIX=${NEXTCLOUD_TABLE_PREFIX:-oc_}
export NEXTCLOUD_UPDATE_CHECKER=${NEXTCLOUD_UPDATE_CHECKER:-false}

# PHP limits
export PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-512M}
export PHP_UPLOAD_LIMIT=${PHP_UPLOAD_LIMIT:-2G}

# Apache port
export PORT=${PORT:-80}
echo "Listen $PORT" > /etc/apache2/ports.conf

# Create autoconfig.php if admin credentials are provided
if [ -n "$NEXTCLOUD_ADMIN_USER" ] && [ -n "$NEXTCLOUD_ADMIN_PASSWORD" ]; then
    echo "✅ Creating autoconfig.php for automatic installation..."
    mkdir -p /var/www/html/config
    cat > /var/www/html/config/autoconfig.php <<EOF
<?php
\$AUTOCONFIG = array(
  "dbtype" => "pgsql",
  "dbname" => "${POSTGRES_DB}",
  "dbuser" => "${POSTGRES_USER}",
  "dbpass" => "${POSTGRES_PASSWORD}",
  "dbhost" => "${POSTGRES_HOST}:${POSTGRES_PORT:-5432}",
  "dbtableprefix" => "${NEXTCLOUD_TABLE_PREFIX}",
  "directory" => "${NEXTCLOUD_DATA_DIR}",
  "adminlogin" => "${NEXTCLOUD_ADMIN_USER}",
  "adminpass" => "${NEXTCLOUD_ADMIN_PASSWORD}",
  "trusted_domains" => array(
      0 => "localhost",
      1 => "${RAILWAY_PUBLIC_DOMAIN}"
  ),
);
EOF
    chown www-data:www-data /var/www/html/config/autoconfig.php
    chmod 640 /var/www/html/config/autoconfig.php
fi

# Finally, start supervisord
echo "🌟 Starting supervisord..."
exec supervisord -c /etc/supervisor/conf.d/supervisord.conf
