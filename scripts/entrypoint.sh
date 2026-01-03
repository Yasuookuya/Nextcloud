#!/bin/bash
set -e

echo "🔧 Starting custom Nextcloud entrypoint..."

# --- PostgreSQL configuration ---
export POSTGRES_HOST=${PGHOST:-${POSTGRES_HOST:-localhost}}
export POSTGRES_PORT=${PGPORT:-${POSTGRES_PORT:-5432}}
export POSTGRES_USER=${PGUSER:-${POSTGRES_USER:-postgres}}
export POSTGRES_PASSWORD=${PGPASSWORD:-${POSTGRES_PASSWORD:-}}
export POSTGRES_DB=${PGDATABASE:-${POSTGRES_DB:-nextcloud}}

# --- Redis configuration with fallback ---
export REDIS_HOST=${REDISHOST:-redis.railway.internal}
export REDIS_PORT=${REDISPORT:-6379}
export REDIS_PASSWORD=${REDISPASSWORD:-$REDIS_PASSWORD}

echo "🔍 Checking Redis connectivity..."
if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
    echo "⚠️ Private Redis unreachable at $REDIS_HOST:$REDIS_PORT, trying public proxy..."
    REDIS_HOST="yamanote.proxy.rlwy.net"
    REDIS_PORT=6379
    REDIS_PASSWORD=$REDISPASSWORD
    if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
        echo "❌ Redis unreachable! Nextcloud caching will be disabled."
        unset REDIS_HOST REDIS_PORT REDIS_PASSWORD
    else
        echo "✅ Connected to public Redis proxy at $REDIS_HOST:$REDIS_PORT"
    fi
else
    echo "✅ Connected to private Redis at $REDIS_HOST:$REDIS_PORT"
fi

# --- Apache configuration for Railway ---
PORT=${PORT:-80}
echo "📌 Configuring Apache to listen on port $PORT..."
cat > /etc/apache2/ports.conf << EOF
Listen 0.0.0.0:$PORT
Listen [::]:$PORT
EOF

# --- Ensure Nextcloud directories ---
mkdir -p /var/www/html/data /var/www/html/config
chown -R www-data:www-data /var/www/html
chmod 750 /var/www/html
chmod 770 /var/www/html/config /var/www/html/data

# --- Autoconfig Nextcloud if config.php missing ---
if [ ! -f /var/www/html/config/config.php ]; then
    echo "🧩 config.php missing — creating autoconfig.php..."
    cat > /var/www/html/config/autoconfig.php <<EOF
<?php
\$AUTOCONFIG = array(
    "dbtype" => "pgsql",
    "dbname" => "${POSTGRES_DB}",
    "dbuser" => "${POSTGRES_USER}",
    "dbpass" => "${POSTGRES_PASSWORD}",
    "dbhost" => "${POSTGRES_HOST}:${POSTGRES_PORT}",
    "dbtableprefix" => "oc_",
    "directory" => "/var/www/html/data",
    "trusted_domains" => array(
        0 => "localhost",
        1 => "${RAILWAY_PUBLIC_DOMAIN:-localhost}",
    ),
    "adminlogin" => "${NEXTCLOUD_ADMIN_USER:-admin}",
    "adminpass" => "${NEXTCLOUD_ADMIN_PASSWORD:-changeme}",
    "memcache.locking" => "\\OC\\Memcache\\Redis",
    "memcache.distributed" => "\\OC\\Memcache\\Redis",
EOF

# Only add Redis config if Redis is reachable
if [ -n "$REDIS_HOST" ]; then
    cat >> /var/www/html/config/autoconfig.php <<EOF
    "redis" => array(
        "host" => "${REDIS_HOST}",
        "port" => ${REDIS_PORT},
        "auth" => "${REDIS_PASSWORD}",
    ),
EOF
fi

echo ");" >> /var/www/html/config/autoconfig.php
chown www-data:www-data /var/www/html/config/autoconfig.php
chmod 640 /var/www/html/config/autoconfig.php
echo "✅ Autoconfig.php created"
fi

# --- Forward to original Nextcloud entrypoint ---
echo "🌟 Starting Apache and Nextcloud..."
exec /entrypoint.sh apache2-foreground
