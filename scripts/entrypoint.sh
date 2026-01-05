#!/bin/bash
set -e

echo "🚀 Starting NextCloud Railway deployment..."
echo "🐛 DEBUG: Current script: $0"
echo "🐛 DEBUG: Process ID: $$"
echo "🐛 DEBUG: All running scripts:"
ps aux | grep -E "(entrypoint|fix-warnings)" || echo "No matching processes found"

# Debug: Print all environment variables starting with POSTGRES or REDIS
echo "🔍 Debug: Environment variables:"
env | grep -E "^(POSTGRES|REDIS.*|RAILWAY|PG|NEXTCLOUD|PHP)" | sort

# Also check for any database-related variables
echo "🔍 Database-related variables:"
env | grep -iE "(database|db|host)" | sort

# Check for environment variables - we need at least some PostgreSQL config
# Check for Railway's PG* variables OR POSTGRES_* variables OR DATABASE_URL
if [ -z "$POSTGRES_HOST" ] && [ -z "$DATABASE_URL" ] && [ -z "$POSTGRES_USER" ] && [ -z "$PGHOST" ] && [ -z "$PGUSER" ]; then
    echo "❌ No PostgreSQL configuration found!"
    echo "Set either individual POSTGRES_* variables, PG* variables, or DATABASE_URL"
    echo "Available environment variables:"
    env | grep -E "^(PG|POSTGRES|DATABASE)" | sort
    exit 1
fi

# If DATABASE_URL is provided, parse it
if [ -n "$DATABASE_URL" ] && [ -z "$POSTGRES_HOST" ]; then
    echo "📊 Parsing DATABASE_URL..."
    export POSTGRES_HOST=$(echo $DATABASE_URL | sed -n 's|postgresql://[^:]*:[^@]*@\([^:]*\):.*|\1|p')
    export POSTGRES_PORT=$(echo $DATABASE_URL | sed -n 's|postgresql://[^:]*:[^@]*@[^:]*:\([0-9]*\)/.*|\1|p')
    export POSTGRES_USER=$(echo $DATABASE_URL | sed -n 's|postgresql://\([^:]*\):.*|\1|p')
    export POSTGRES_PASSWORD=$(echo $DATABASE_URL | sed -n 's|postgresql://[^:]*:\([^@]*\)@.*|\1|p')
    export POSTGRES_DB=$(echo $DATABASE_URL | sed -n 's|.*/\([^?]*\).*|\1|p')
fi

# Use Railway's standard PG* variables if POSTGRES_* aren't set
export POSTGRES_HOST=${POSTGRES_HOST:-$PGHOST}
export POSTGRES_PORT=${POSTGRES_PORT:-$PGPORT}
export POSTGRES_USER=${POSTGRES_USER:-$PGUSER}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$PGPASSWORD}
export POSTGRES_DB=${POSTGRES_DB:-$PGDATABASE}

# Set final defaults if still missing
export POSTGRES_HOST=${POSTGRES_HOST:-localhost}
export POSTGRES_PORT=${POSTGRES_PORT:-5432}
export POSTGRES_USER=${POSTGRES_USER:-postgres}
export POSTGRES_DB=${POSTGRES_DB:-nextcloud}

# Redis configuration - Railway uses REDISHOST, REDISPORT, REDISPASSWORD
export REDIS_HOST=${REDIS_HOST:-${REDISHOST:-localhost}}
export REDIS_PORT=${REDIS_PORT:-${REDISPORT:-6379}}
export REDIS_PASSWORD=${REDIS_PASSWORD:-${REDISPASSWORD:-}}

# NextCloud configuration variables
export NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-}
export NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-}
export NEXTCLOUD_DATA_DIR=${NEXTCLOUD_DATA_DIR:-/var/www/html/data}
export NEXTCLOUD_TABLE_PREFIX=${NEXTCLOUD_TABLE_PREFIX:-oc_}
export NEXTCLOUD_UPDATE_CHECKER=${NEXTCLOUD_UPDATE_CHECKER:-false}

# PHP performance settings
export PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-512M}
export PHP_UPLOAD_LIMIT=${PHP_UPLOAD_LIMIT:-2G}

# Configure Apache for Railway's PORT
export PORT=${PORT:-80}
echo "Listen $PORT" > /etc/apache2/ports.conf
echo "✅ Apache configured for port: $PORT"

# Display configuration info  
echo "📊 Final Configuration:"
echo "📊 Database Config:"
echo "  POSTGRES_HOST: ${POSTGRES_HOST}"
echo "  POSTGRES_PORT: ${POSTGRES_PORT}"  
echo "  POSTGRES_USER: ${POSTGRES_USER}"
echo "  POSTGRES_DB: ${POSTGRES_DB}"
echo "  Full connection: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
echo "🔴 Redis Config:"
echo "  REDISHOST: ${REDISHOST}"
echo "  REDISPORT: ${REDISPORT}"
echo "  REDISPASSWORD: ${REDISPASSWORD}"
echo "🌐 NextCloud Config:"
echo "  Trusted domains: ${NEXTCLOUD_TRUSTED_DOMAINS}"
echo "  Admin user: ${NEXTCLOUD_ADMIN_USER:-'(setup wizard)'}"
echo "  Data directory: ${NEXTCLOUD_DATA_DIR}"
echo "  Table prefix: ${NEXTCLOUD_TABLE_PREFIX}"
echo "⚡ Performance Config:"
echo "  PHP Memory Limit: ${PHP_MEMORY_LIMIT}"
echo "  PHP Upload Limit: ${PHP_UPLOAD_LIMIT}"

# Create full config.php if admin credentials are provided
if [ -n "${NEXTCLOUD_ADMIN_USER}" ] && [ -n "${NEXTCLOUD_ADMIN_PASSWORD}" ]; then
    echo "✅ Admin credentials provided - creating full config.php"
    mkdir -p /var/www/html/config
    cat > /var/www/html/config/config.php << 'EOF'
<?php
$CONFIG = array (
  'instanceid' => '$(head -c32 /dev/urandom | base64)',
  'passwordsalt' => '$(head -c32 /dev/urandom | base64)',
  'secret' => '$(head -c48 /dev/urandom | base64)',
  'trusted_domains' => 
  array (
    0 => 'localhost',
    1 => '$RAILWAY_PUBLIC_DOMAIN',
    2 => 'engineering.kikaiworks.com',
  ),
  'datadirectory' => '$NEXTCLOUD_DATA_DIR',
  'dbtype' => 'pgsql',
  'version' => '32.0.3.2',
  'dbname' => '$POSTGRES_DB',
  'dbhost' => '$POSTGRES_HOST:$POSTGRES_PORT',
  'dbuser' => '$POSTGRES_USER',
  'dbpassword' => '$POSTGRES_PASSWORD',
  'installed' => true,
  'theme' => '',
  'loglevel' => 2,
  'maintenance' => false,
  'overwrite.cli.url' => 'https://$RAILWAY_PUBLIC_DOMAIN',
  'overwriteprotocol' => 'https',
  'overwritehost' => '$RAILWAY_PUBLIC_DOMAIN',
  'trusted_proxies' => 
  array (
    0 => '100.0.0.0/8',
  ),
  'memcache.local' => '\\OC\\Memcache\\Redis',
  'redis' => 
  array (
    'host' => '$REDIS_HOST',
    'port' => '$REDIS_PORT',
    'password' => '$REDIS_PASSWORD',
    'user' => 'default',
  ),
);

$CONFIG['logfile'] = '/var/www/html/data/nextcloud.log';
EOF
    chown www-data:www-data /var/www/html/config/config.php
    chmod 640 /var/www/html/config/config.php
    echo "✅ Config.php created with all settings"
else
    echo "✅ No admin credentials - NextCloud setup wizard will be used"
fi

# Forward to original NextCloud entrypoint
echo "🔧 Fixing Apache MPM runtime..."
# Comment out conflicting MPM LoadModule lines in all conf
find /etc/apache2 -name "*.conf" -o -name "*.load" | xargs sed -i '/LoadModule.*mpm_\(event\|worker\)_module/ s/^/#/'
# Remove conflicting MPM files (real or symlink)
rm -f /etc/apache2/mods-enabled/mpm_event.load /etc/apache2/mods-enabled/mpm_event.conf /etc/apache2/mods-enabled/mpm_worker.load /etc/apache2/mods-enabled/mpm_worker.conf
# Link prefork
ln -sf /etc/apache2/mods-available/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.load
ln -sf /etc/apache2/mods-available/mpm_prefork.conf /etc/apache2/mods-enabled/mpm_prefork.conf
apache2ctl configtest || echo "Apache configtest warning - continuing"

echo "🐛 DEBUG: About to exec original NextCloud entrypoint"
echo "🐛 DEBUG: Command: /entrypoint.sh apache2-foreground"
echo "🐛 DEBUG: Current working directory: $(pwd)"
echo "🐛 DEBUG: Contents of /usr/local/bin/:"
ls -la /usr/local/bin/ | grep -E "(entrypoint|fix-warnings)"

exec /entrypoint.sh apache2-foreground
