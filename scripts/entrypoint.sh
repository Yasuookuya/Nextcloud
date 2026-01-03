#!/bin/bash
set -e

# Force redeployment to clear cache

echo "🔧 Configuring Apache MPM for Railway compatibility..."
a2dismod mpm_event mpm_worker 2>/dev/null || true
a2enmod mpm_prefork 2>/dev/null || true

echo "🔧 Configuring Apache AllowOverride for .htaccess support..."
sed -i 's|AllowOverride None|AllowOverride All|g' /etc/apache2/apache2.conf

echo "� Starting NextCloud Railway deployment..."
echo "🐛 DEBUG: Current script: $0"
echo "🐛 DEBUG: Process ID: $$"
echo "�🐛 DEBUG: All running scripts:"
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

# Initialize Nextcloud code into volume if empty (official Docker behavior)
if [ ! -f /var/www/html/occ ]; then
  echo "📦 Nextcloud code not found in volume – restoring from image"
  rsync -a --delete /usr/src/nextcloud/ /var/www/html/
fi

# Wait for NextCloud entrypoint to initialize first
echo "🌟 Starting NextCloud with original entrypoint..."

# Check if Nextcloud is already installed
if [ -f /var/www/html/config/config.php ]; then
    echo "📁 Existing installation detected - skipping database reset and autoconfig"
else
    echo "🆕 First install detected - proceeding with setup"

    # Only clean database on first install to avoid destroying existing data
    echo "🧹 First install - resetting Nextcloud database..."
    PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "
    DO \$\$
    DECLARE
        r RECORD;
    BEGIN
        -- Drop all tables in all schemas
        FOR r IN (SELECT schemaname, tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema')) LOOP
            EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.schemaname) || '.' || quote_ident(r.tablename) || ' CASCADE';
        END LOOP;

        -- Drop all sequences in all schemas
        FOR r IN (SELECT schemaname, sequencename FROM pg_sequences WHERE schemaname NOT IN ('pg_catalog', 'information_schema')) LOOP
            EXECUTE 'DROP SEQUENCE IF EXISTS ' || quote_ident(r.schemaname) || '.' || quote_ident(r.sequencename) || ' CASCADE';
        END LOOP;

        -- Reset sequences
        PERFORM setval(oid, 1, false) FROM pg_class WHERE relkind = 'S';
    END \$\$;
    " 2>/dev/null || echo "Database cleanup completed or database not ready yet"

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
fi

# Fix Nextcloud directory permissions after volume mount
echo "🔧 Setting Nextcloud directory permissions..."
chown -R www-data:www-data /var/www/html
chmod -R 750 /var/www/html
mkdir -p /var/www/html/data
echo "# Nextcloud data directory" > /var/www/html/data/.ncdata
chown www-data:www-data /var/www/html/data/.ncdata

# Forward to original NextCloud entrypoint
echo "🐛 DEBUG: About to exec original NextCloud entrypoint"
echo "🐛 DEBUG: Command: /entrypoint.sh apache2-foreground"
echo "🐛 DEBUG: Current working directory: $(pwd)"
echo "🐛 DEBUG: Contents of /usr/local/bin/:"
ls -la /usr/local/bin/ | grep -E "(entrypoint|fix-warnings)"

exec /entrypoint.sh apache2-foreground
