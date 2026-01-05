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
    REDIS_HOST="${REDIS_HOST:-}"
    REDIS_PORT="${REDIS_PORT:-6379}"
    REDIS_PASSWORD="${REDIS_PASSWORD:-}"
fi

echo "DB: $POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB ($POSTGRES_USER)"
echo "Redis: $REDIS_HOST:$REDIS_PORT"

# Set trusted domains
export NEXTCLOUD_TRUSTED_DOMAINS="${NEXTCLOUD_TRUSTED_DOMAINS:-$RAILWAY_PUBLIC_DOMAIN localhost}"

# Apache port configuration
echo "Listen ${PORT:-80}" > /etc/apache2/ports.conf

# Auto-config for Nextcloud
if [ -n "$NEXTCLOUD_ADMIN_USER" ] && [ -n "$NEXTCLOUD_ADMIN_PASSWORD" ]; then
    echo "Creating auto-config for Nextcloud..."
    mkdir -p /docker-entrypoint-hooks.d/before-starting
    cat > /docker-entrypoint-hooks.d/before-starting/01-autoconfig.sh << EOF
#!/bin/bash
echo "Setting up Nextcloud auto-configuration..."
cat > /var/www/html/config/autoconfig.php << 'AUTOCONFIG_EOF'
<?php
\$AUTOCONFIG = array(
    "dbtype" => "pgsql",
    "dbname" => "$POSTGRES_DB",
    "dbuser" => "$POSTGRES_USER",
    "dbpass" => "$POSTGRES_PASSWORD",
    "dbhost" => "$POSTGRES_HOST:$POSTGRES_PORT",
    "dbtableprefix" => "${NEXTCLOUD_TABLE_PREFIX:-oc_}",
    "directory" => "${NEXTCLOUD_DATA_DIR:-/var/www/html/data}",
    "adminlogin" => "$NEXTCLOUD_ADMIN_USER",
    "adminpass" => "$NEXTCLOUD_ADMIN_PASSWORD",
    "trusted_domains" => array ( 0 => "$RAILWAY_PUBLIC_DOMAIN", 1 => "localhost" ),
);
?>
AUTOCONFIG_EOF
chown www-data:www-data /var/www/html/config/autoconfig.php
chmod 640 /var/www/html/config/autoconfig.php
echo "Auto-config created successfully"
EOF
    chmod +x /docker-entrypoint-hooks.d/before-starting/01-autoconfig.sh
fi

# Section 9: Post-install auto-green fixes
if grep -q "'installed'=>true" /var/www/html/config/config.php 2>/dev/null; then
    echo "🚀 === POST-INSTALL GREEN FIXES ==="
    chown -R www-data /var/www/html || true

    # Merge optimizations
    if ! grep -q "optimizations.php" /var/www/html/config/config.php; then
        sed -i '/\$CONFIG = array(/a $CONFIG_INCLUDES[] = include("/var/www/html/config/nextcloud-optimizations.php");' /var/www/html/config/config.php
    fi

    # Redis configuration
    runuser www-data -c "cd /var/www/html && php occ redis:config --host=$REDIS_HOST --port=$REDIS_PORT --password=$REDIS_PASSWORD --dbindex=0" 2>/dev/null || true

    # Run fix script
    /usr/local/bin/fix-warnings.sh || true

    # Files scan
    runuser www-data -c "cd /var/www/html && php occ files:scan --all --quiet" 2>/dev/null || true

    echo "✅ Auto-green fixes completed!"
fi

# Execute original Nextcloud entrypoint
exec /entrypoint.sh "$@"
