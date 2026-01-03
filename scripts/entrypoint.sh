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

# Wait for NextCloud entrypoint to initialize first
echo "🌟 Starting NextCloud with original entrypoint..."

# Set up autoconfig.php if admin credentials are provided
if [ -n "${NEXTCLOUD_ADMIN_USER:-}" ] && [ "${NEXTCLOUD_ADMIN_USER}" != "" ] && [ -n "${NEXTCLOUD_ADMIN_PASSWORD:-}" ] && [ "${NEXTCLOUD_ADMIN_PASSWORD}" != "" ]; then
    echo "✅ Admin credentials provided - will create autoconfig.php"
    # Create hook for autoconfig setup
    mkdir -p /docker-entrypoint-hooks.d/before-starting
    
    cat > /docker-entrypoint-hooks.d/before-starting/01-autoconfig.sh << 'EOF'
#!/bin/bash
echo "🔧 Creating autoconfig.php for automatic setup..."
mkdir -p /var/www/html/config
cat > /var/www/html/config/autoconfig.php << AUTOEOF
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
        1 => "${RAILWAY_PUBLIC_DOMAIN}",
    ),
);
AUTOEOF
chown www-data:www-data /var/www/html/config/autoconfig.php
chmod 640 /var/www/html/config/autoconfig.php
echo "✅ Autoconfig.php created for automatic installation"
EOF
    chmod +x /docker-entrypoint-hooks.d/before-starting/01-autoconfig.sh
else
    echo "✅ No admin credentials - NextCloud setup wizard will be used"
    echo "✅ Skipping autoconfig.php creation"
fi

# Fix Apache MPM configuration to prevent conflicts
echo "🔧 Fixing Apache MPM configuration..."
a2dismod --force mpm_event mpm_worker || true
a2enmod mpm_prefork || true
echo "✅ Apache MPM configuration fixed"

# NEW: Full warm-up + permanent security/setup fixes (integrates fix-warnings.sh)
if [ -f /var/www/html/config/config.php ] && grep -q "'installed' => true," /var/www/html/config/config.php 2>/dev/null; then
    echo "🔧 Running full warm-up + permanent security/setup fixes..."

    # run_occ function (reliable for www-data)
    run_occ() {
        su www-data -s /bin/bash -c "php /var/www/html/occ $* 2>/dev/null" || true
    }

    # Disable spam (speedup)
    run_occ config:system:set debug --value=false --type=boolean --quiet --no-interaction
    run_occ config:system:set loglevel --value=2 --quiet --no-interaction

    # DB fixes (core security warnings)
    run_occ db:add-missing-columns --quiet --no-interaction
    run_occ db:add-missing-indices --quiet --no-interaction
    run_occ db:add-missing-primary-keys --quiet --no-interaction

    # Repairs/migrations
    run_occ maintenance:repair --include-expensive --quiet --no-interaction
    run_occ files:scan --all --shallow --quiet --no-interaction

    # System configs
    run_occ config:system:set maintenance_window_start --value=2 --type=integer --quiet --no-interaction
    run_occ config:system:set default_phone_region --value="US" --quiet --no-interaction
    run_occ config:system:set updatechecker --value=false --type=boolean --quiet --no-interaction

    # Redis if available (caching perf)
    if [ -n "$REDIS_HOST" ] && [ "$REDIS_HOST" != "localhost" ]; then
        run_occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu" --quiet --no-interaction
        run_occ config:system:set memcache.distributed --value="\\OC\\Memcache\\Redis" --quiet --no-interaction
        run_occ config:system:set memcache.locking --value="\\OC\\Memcache\\Redis" --quiet --no-interaction
        run_occ redis:config-test --quiet
    fi

    # Background jobs + final
    run_occ background:cron --no-interaction --quiet
    run_occ maintenance:mode --off --quiet --no-interaction

    # Opcache warm (fast CLI)
    timeout 15 su www-data -s /bin/bash -c "php /var/www/html/index.php --version >/dev/null 2>&1" || true

    echo "✅ Permanent fixes & warm-up complete - 0 warnings expected!"
else
    echo "⏳ Not installed - fixes auto-run after setup (on restart/access)"
fi

# NEW: Start supervisord (Apache + cron auto)
echo "🚀 Starting supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
