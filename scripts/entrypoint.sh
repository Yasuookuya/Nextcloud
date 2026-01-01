#!/bin/bash
set -e

echo "🚀 Starting NextCloud Railway deployment..."
echo "🐛 DEBUG: PID $$"

# Diagnostics: Print env
echo "🔍 ENV DIAGNOSTIC:"
env | grep -E "(POSTGRES|REDIS|NEXTCLOUD|DATABASE_URL|RAILWAY)" | sort

# Diagnostics: Check DB connection and tables/owners
echo "🔍 DB DIAGNOSTIC:"
echo "Tables:"
psql "$DATABASE_URL" -c "\dt" || echo "No tables or connection issue"
echo "Table owners (for oc_*):"
psql "$DATABASE_URL" -c "\dt oc_*" || echo "No oc tables"
echo "oc_migrations perms:"
psql "$DATABASE_URL" -c "\dp oc_migrations" || echo "No oc_migrations or perm error"

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

# Display configuration info (unchanged)
echo "📊 Final Configuration:"
echo "📊 Database Config:"
echo "  POSTGRES_HOST: ${POSTGRES_HOST}"
echo "  POSTGRES_PORT: ${POSTGRES_PORT}"
echo "  POSTGRES_USER: ${POSTGRES_USER}"
echo "  POSTGRES_DB: ${POSTGRES_DB}"
echo "  Full connection: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
echo "🔴 Redis Config:"
echo "  REDIS_HOST: ${REDIS_HOST}"
echo "  REDIS_PORT: ${REDIS_PORT}"
echo "  REDIS_PASSWORD: ${REDIS_PASSWORD}"
echo "🌐 NextCloud Config:"
echo "  Trusted domains: ${NEXTCLOUD_TRUSTED_DOMAINS}"
echo "  Admin user: ${NEXTCLOUD_ADMIN_USER:-'(setup wizard)'}"
echo "  Data directory: ${NEXTCLOUD_DATA_DIR}"
echo "  Table prefix: ${NEXTCLOUD_TABLE_PREFIX}"
echo "⚡ Performance Config:"
echo "  PHP Memory Limit: ${PHP_MEMORY_LIMIT}"
echo "  PHP Upload Limit: ${PHP_UPLOAD_LIMIT}"

# Wait for DB and Redis to be available (add this for reliability in Railway)
echo "⌛ Waiting for PostgreSQL..."
until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER"; do
  sleep 2
done
echo "✅ PostgreSQL is ready"

echo "⌛ Waiting for Redis..."
until redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} ping; do
  sleep 2
done
echo "✅ Redis is ready"

# Diagnostics: Check config and occ status
echo "🔍 POST-WAITS DIAGNOSTIC:"
ls -la /var/www/html/config/ || echo "No config dir"
su www-data -s /bin/bash -c "php occ status --output=json 2>/dev/null" || echo "occ status failed (no config yet)"

# Substitute env vars in nginx.conf (fix $PORT issue)
if command -v envsubst >/dev/null 2>&1; then
  envsubst '${PORT}' < /etc/nginx/sites-available/default > /etc/nginx/sites-enabled/default
  echo "✅ Nginx config substituted with runtime env vars"
else
  echo "⚠️ envsubst not found - Falling back to default port 80"
  sed -i "s/listen \$PORT/listen 80/g" /etc/nginx/sites-available/default
  ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi

# Set up autoconfig or force occ install if creds provided (enhanced for reliability)
if [ -n "${NEXTCLOUD_ADMIN_USER}" ] && [ -n "${NEXTCLOUD_ADMIN_PASSWORD}" ]; then
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
    "memcache.local" => "\\OC\\Memcache\\Redis",
    "memcache.locking" => "\\OC\\Memcache\\Redis",
    "redis" => array(
        "host" => "${REDIS_HOST}",
        "port" => "${REDIS_PORT}",
        "password" => "${REDIS_PASSWORD}",
    ),
);
AUTOEOF
chown www-data:www-data /var/www/html/config/autoconfig.php
chmod 640 /var/www/html/config/autoconfig.php
echo "✅ Autoconfig.php created for automatic installation"
EOF
  chmod +x /docker-entrypoint-hooks.d/before-starting/01-autoconfig.sh
else
  echo "⚠️ No admin creds - Forcing occ install with defaults (update later via UI)"
  # Set defaults or prompt - for auto, recommend setting vars
  export NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-admin}
  export NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-$(openssl rand -base64 16)}  # Random for security; log it
  echo "Generated temp password: $NEXTCLOUD_ADMIN_PASSWORD (change immediately!)"
fi

# Skip original entrypoint entirely (avoids parameter error, custom handles)
echo "🌟 Skipping original entrypoint (using custom setup for wizard)"

# Force fresh wizard
rm -f /var/www/html/config/config.php
echo "🔧 config.php deleted - fresh wizard ready"

# Diagnostics
echo "🔍 POST-SETUP DIAGNOSTIC:"
ls -la /var/www/html/config/ || echo "No config dir"
su www-data -s /bin/bash -c "php occ status --output=json 2>/dev/null || echo 'occ status: Not installed (wizard needed)'"

# Post-install (now runs after install complete)
if [ -f "/var/www/html/config/config.php" ]; then
  # ... existing occ commands for Redis, cron, and call fix-warnings.sh ...
  echo "🔧 Running post-install fixes..."
  su www-data -s /bin/bash -c "php occ config:system:set memcache.local --value=\\OC\\Memcache\\Redis"
  su www-data -s /bin/bash -c "php occ config:system:set memcache.locking --value=\\OC\\Memcache\\Redis"
  su www-data -s /bin/bash -c "php occ config:system:set redis host --value=${REDIS_HOST}"
  su www-data -s /bin/bash -c "php occ config:system:set redis port --value=${REDIS_PORT}"
  if [ -n "$REDIS_PASSWORD" ]; then
    su www-data -s /bin/bash -c "php occ config:system:set redis password --value=${REDIS_PASSWORD}"
  fi
  su www-data -s /bin/bash -c "php occ background-job:cron"  # Set up cron mode

  # Community fix: Scan files and group folders to sync existing data
  echo "🧹 Scanning files and group folders (to recover existing data)..."
  su www-data -s /bin/bash -c "php occ files:scan --all"
  su www-data -s /bin/bash -c "php occ groupfolders:scan --all"

  /usr/local/bin/fix-warnings.sh  # Run any warning fixes
fi

# Start Supervisor (after install complete)
echo "🛡️ Starting Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
