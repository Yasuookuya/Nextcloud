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
        # Generate secrets
        INSTANCEID=$(head -c32 /dev/urandom | base64)
        PASSWORDSALT=$(head -c32 /dev/urandom | base64)
        SECRET=$(head -c48 /dev/urandom | base64)

        cat > /var/www/html/config/config.php << 'EOF'
<?php
$CONFIG = array (
  'instanceid' => 'INSTANCEID_PLACEHOLDER',
  'passwordsalt' => 'PASSWORDSALT_PLACEHOLDER',
  'secret' => 'SECRET_PLACEHOLDER',
  'trusted_domains' => 
  array (
    0 => 'localhost',
    1 => 'RAILWAY_PUBLIC_DOMAIN_PLACEHOLDER',
    2 => 'engineering.kikaiworks.com',
  ),
  'datadirectory' => 'NEXTCLOUD_DATA_DIR_PLACEHOLDER',
  'dbtype' => 'pgsql',
  'version' => '32.0.3.2',
  'dbname' => 'POSTGRES_DB_PLACEHOLDER',
  'dbhost' => 'POSTGRES_HOST_PLACEHOLDER:POSTGRES_PORT_PLACEHOLDER',
  'dbuser' => 'POSTGRES_USER_PLACEHOLDER',
  'dbpassword' => 'POSTGRES_PASSWORD_PLACEHOLDER',
  'installed' => true,
  'theme' => '',
  'loglevel' => 2,
  'maintenance' => false,
  'overwrite.cli.url' => 'https://RAILWAY_PUBLIC_DOMAIN_PLACEHOLDER',
  'overwriteprotocol' => 'https',
  'overwritehost' => 'RAILWAY_PUBLIC_DOMAIN_PLACEHOLDER',
  'trusted_proxies' => 
  array (
    0 => '100.0.0.0/8',
  ),
  'memcache.local' => '\\OC\\Memcache\\Redis',
  'redis' => 
  array (
    'host' => 'REDIS_HOST_PLACEHOLDER',
    'port' => REDIS_PORT_PLACEHOLDER,
    'password' => 'REDIS_PASSWORD_PLACEHOLDER',
    'user' => 'default',
  ),
);

$CONFIG['logfile'] = '/var/www/html/data/nextcloud.log';
EOF

        # Substitute placeholders
        sed -i "s|INSTANCEID_PLACEHOLDER|${INSTANCEID}|g" /var/www/html/config/config.php
        sed -i "s|PASSWORDSALT_PLACEHOLDER|${PASSWORDSALT}|g" /var/www/html/config/config.php
        sed -i "s|SECRET_PLACEHOLDER|${SECRET}|g" /var/www/html/config/config.php
        sed -i "s|RAILWAY_PUBLIC_DOMAIN_PLACEHOLDER|${RAILWAY_PUBLIC_DOMAIN}|g" /var/www/html/config/config.php
        sed -i "s|NEXTCLOUD_DATA_DIR_PLACEHOLDER|${NEXTCLOUD_DATA_DIR}|g" /var/www/html/config/config.php
        sed -i "s|POSTGRES_DB_PLACEHOLDER|${POSTGRES_DB}|g" /var/www/html/config/config.php
        sed -i "s|POSTGRES_HOST_PLACEHOLDER|${POSTGRES_HOST}|g" /var/www/html/config/config.php
        sed -i "s|POSTGRES_PORT_PLACEHOLDER|${POSTGRES_PORT}|g" /var/www/html/config/config.php
        sed -i "s|POSTGRES_USER_PLACEHOLDER|${POSTGRES_USER}|g" /var/www/html/config/config.php
        sed -i "s|POSTGRES_PASSWORD_PLACEHOLDER|${POSTGRES_PASSWORD}|g" /var/www/html/config/config.php
        chown www-data:www-data /var/www/html/config/config.php
        chmod 640 /var/www/html/config/config.php
        echo "✅ Config.php created with all settings"

        # Diagnostics and Installation
        echo "🔍 Starting diagnostics and installation..."

        # Fix permissions
        echo "🔍 Fixing permissions..."
        mkdir -p /var/www/html/data /var/www/html/config
        chown -R www-data:www-data /var/www/html/data /var/www/html/config
        chmod -R 755 /var/www/html/data /var/www/html/config
        ls -la /var/www/html/config /var/www/html/data 2>/dev/null || echo "Data dir initialized"

        # Test Postgres connection
        echo "🔍 Testing Postgres connection..."
        if PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "SELECT version();" >/dev/null 2>&1; then
            echo "✅ Postgres connected successfully"
            PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "\dt" 2>&1 | head -5 || echo "No tables or access issue"
        else
            echo "❌ Postgres connection failed!"
            exit 1
        fi

        # Test Redis connection
        echo "🔍 Testing Redis connection..."
        if timeout 5 redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" ping 2>&1 | grep -q "PONG"; then
            echo "✅ Redis responding with PONG"
        else
            echo "❌ Redis connection failed!"
            exit 1
        fi

        # Check Nextcloud status and install/upgrade
        cd /var/www/html
        echo "🔍 Checking Nextcloud installation status..."
        STATUS_OUTPUT=$(su www-data -s /bin/bash -c "php occ status --output=json 2>&1" || echo '{"installed":false}')
        echo "$STATUS_OUTPUT"
        if echo "$STATUS_OUTPUT" | grep -q '"installed":true'; then
            echo "🔧 Nextcloud already installed, running upgrade..."
            su www-data -s /bin/bash -c "php occ maintenance:upgrade --no-interaction 2>&1" || echo "Upgrade completed or no changes needed"
        else
            echo "🔧 Installing Nextcloud..."
            su www-data -s /bin/bash -c "php occ maintenance:install \
                --database=pgsql --database-host='${POSTGRES_HOST}:${POSTGRES_PORT}' \
                --database-name='${POSTGRES_DB}' --database-user='${POSTGRES_USER}' \
                --database-pass='${POSTGRES_PASSWORD}' \
                --admin-user='${NEXTCLOUD_ADMIN_USER}' --admin-pass='${NEXTCLOUD_ADMIN_PASSWORD}' \
                --data-dir='${NEXTCLOUD_DATA_DIR}' --no-interaction 2>&1" || { echo "❌ Installation failed!"; exit 1; }
            echo "✅ Installation completed"
        fi

        # Additional diagnostics
        echo "🔍 Running Nextcloud check..."
        su www-data -s /bin/bash -c "php occ check 2>&1" || echo "Check completed"

        # Update htaccess for pretty URLs
        echo "🔍 Updating .htaccess for pretty URLs..."
        su www-data -s /bin/bash -c "php occ maintenance:update:htaccess 2>&1" || echo "Htaccess updated or no changes"

        # Sanitized config preview
        echo "🔍 Generated config.php key sections:"
        sed 's/dbpassword => '\''[^'\'']*'\''/dbpassword => [REDACTED]/g' /var/www/html/config/config.php | grep -E "(dbtype|dbhost|dbname|dbuser|trusted_domains|datadirectory|installed|redis|overwrite)" || echo "Config sections not found"
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

echo "✅ Diagnostics and installation complete"
echo "🐛 DEBUG: About to start supervisord"
echo "🐛 DEBUG: Command: /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf"
echo "🐛 DEBUG: Current working directory: $(pwd)"

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
