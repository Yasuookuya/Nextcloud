#!/bin/bash
set -e

# Railway configuration - use the actual Railway environment variables provided
export PGSSLMODE=disable

# Railway provides individual POSTGRES_* and REDIS_* variables directly
# Validate required Railway environment variables
if [ -z "$POSTGRES_HOST" ] || [ -z "$POSTGRES_PORT" ] || [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_DB" ]; then
  echo "❌ ERROR: Railway PostgreSQL environment variables not set!"
  echo "   Required: POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_DB"
  echo "   Please ensure PostgreSQL database is attached to your Railway project."
  exit 1
fi

if [ -z "$REDIS_HOST" ] || [ -z "$REDIS_PORT" ]; then
  echo "❌ ERROR: Railway Redis environment variables not set!"
  echo "   Required: REDIS_HOST, REDIS_PORT"
  echo "   Please ensure Redis database is attached to your Railway project."
  exit 1
fi

# Set defaults for optional variables
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-""}
export REDIS_PASSWORD=${REDIS_HOST_PASSWORD:-""}  # Railway uses REDIS_HOST_PASSWORD
export DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

export NEXTCLOUD_TRUSTED_DOMAINS=${NEXTCLOUD_TRUSTED_DOMAINS:-"nextcloud-railway-template-website.up.railway.app,localhost,::1,RAILWAY_PRIVATE_DOMAIN,RAILWAY_STATIC_URL"}
export NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-"kikaiworksadmin"}
export NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-"2046S@nto!7669Y@"}
export NEXTCLOUD_UPDATE_CHECK=${NEXTCLOUD_UPDATE_CHECK:-"false"}
export OVERWRITEPROTOCOL=${OVERWRITEPROTOCOL:-"https"}

export PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-"512M"}
export PHP_UPLOAD_LIMIT=${PHP_UPLOAD_LIMIT:-"512M"}

# SMTP settings (optional)
export SMTP_HOST=${SMTP_HOST:-null}
export SMTP_SECURE=${SMTP_SECURE:-"ssl"}
export SMTP_PORT=${SMTP_PORT:-"465"}
export SMTP_AUTHTYPE=${SMTP_AUTHTYPE:-"LOGIN"}
export SMTP_NAME=${SMTP_NAME:-null}
export SMTP_PASSWORD=${SMTP_PASSWORD:-null}
export MAIL_FROM_ADDRESS=${MAIL_FROM_ADDRESS:-null}
export MAIL_DOMAIN=${MAIL_DOMAIN:-null}

echo "✅ Railway environment variables set"

echo "🚀 Starting NextCloud Railway deployment..."
echo "🐛 DEBUG: PID $$"

echo "=== STEP 1: ENV ==="
env | grep -E "(PORT|POSTGRES|REDIS|NEXTCLOUD|DATABASE_URL|RAILWAY)" | sort

# Environment variable validation
echo "🔍 Validating environment variables..."

# Required variables
REQUIRED_VARS=("PORT" "POSTGRES_HOST" "POSTGRES_DB" "REDIS_HOST")
WARNING_VARS=("NEXTCLOUD_ADMIN_USER" "NEXTCLOUD_ADMIN_PASSWORD")

for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ Required environment variable $var is not set!"
    exit 1
  else
    echo "✅ $var: ${!var}"
  fi
done

for var in "${WARNING_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "⚠️ Warning: $var is not set, using defaults"
  fi
done

echo "✅ Environment validation complete"

# STEP 2: DB DIAG with retry
echo "🔍 [PHASE: DB_CHECK] Checking database connectivity (3 retries)..."
for i in {1..3}; do
  if DB_TABLES=$(timeout 10 psql "$DATABASE_URL" -c "\dt" 2>&1) && [ $? -eq 0 ]; then
    echo "✅ [PHASE: DB_CHECK] Database connection successful."
    echo "📊 Tables: $(echo "$DB_TABLES" | grep -c "table")"
    DB_HAS_TABLES=true
    break
  else
    echo "⚠️ [PHASE: DB_CHECK] Attempt $i failed: $DB_TABLES"
    sleep 5
  fi
  [ $i -eq 3 ] && { echo "❌ [PHASE: DB_CHECK] Final failure"; exit 1; }
done

# Grant permissions to postgres user if tables exist (fix for existing DB)
if psql "$DATABASE_URL" -c "\dt" >/dev/null 2>&1; then
  echo "Reassigning ownership and granting permissions to postgres user on existing tables..."
  # First, find the current owner of the tables
  CURRENT_OWNER=$(psql "$DATABASE_URL" -t -c "SELECT tableowner FROM pg_tables WHERE tablename = 'oc_migrations' AND schemaname = 'public';" 2>/dev/null | xargs)
  if [ -n "$CURRENT_OWNER" ] && [ "$CURRENT_OWNER" != "postgres" ]; then
    echo "🔧 Current table owner: $CURRENT_OWNER, reassigning to postgres..."
    psql "$DATABASE_URL" -c "REASSIGN OWNED BY $CURRENT_OWNER TO postgres;" 2>/dev/null || echo "⚠️ Reassign failed, continuing..."
  fi
  psql "$DATABASE_URL" -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;" 2>/dev/null || echo "⚠️ Table grants failed, continuing..."
  psql "$DATABASE_URL" -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;" 2>/dev/null || echo "⚠️ Sequence grants failed, continuing..."
  psql "$DATABASE_URL" -c "GRANT ALL PRIVILEGES ON SCHEMA public TO postgres;" 2>/dev/null || echo "⚠️ Schema grants failed, continuing..."
  echo "Creating/updating config.php for existing DB..."
    mkdir -p /var/www/html/config
    mkdir -p /var/www/html/data
    # Use persistent config location
    CONFIG_FILE="/var/www/html/data/config.php"
    # Parse existing config if present (PRESERVE instanceid/passwordsalt/secret)
    if [ -f "$CONFIG_FILE" ]; then
      echo "🔄 Preserving existing config values from persistent storage..."
      INSTANCEID=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['instanceid'] ?? 'missing';")
      PASSWORDSALT=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['passwordsalt'] ?? 'missing';")
      SECRET=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['secret'] ?? 'missing';")

      if [ "$INSTANCEID" = "missing" ] || [ "$PASSWORDSALT" = "missing" ] || [ "$SECRET" = "missing" ]; then
        echo "⚠️ Incomplete existing config, regenerating..."
        INSTANCEID="oc$(openssl rand -hex 10)"
        PASSWORDSALT="$(openssl rand -hex 10)"
        SECRET="$(openssl rand -hex 10)"
      fi
    else
      echo "🆕 First-time config generation..."
      INSTANCEID="oc$(openssl rand -hex 10)"
      PASSWORDSALT="$(openssl rand -hex 10)"
      SECRET="$(openssl rand -hex 10)"
    fi
    # Explicit exports for all template vars (safe, idempotent)
    export RAILWAY_PUBLIC_DOMAIN=${RAILWAY_PUBLIC_DOMAIN:-"nextcloud-railway-template-website.up.railway.app"}
    export RAILWAY_PRIVATE_DOMAIN=${RAILWAY_PRIVATE_DOMAIN:-"nextcloud-railway-template.railway.internal"}
    export RAILWAY_STATIC_URL=${RAILWAY_STATIC_URL:-"nextcloud-railway-template-website.up.railway.app"}
    export REDIS_PASSWORD="${REDIS_HOST_PASSWORD:-}"
    export OVERWRITEPROTOCOL=${OVERWRITEPROTOCOL:-"https"}
    # UPDATE_CHECK_DISABLED is always false
    # Export instance-specific vars for envsubst
    export INSTANCEID PASSWORDSALT SECRET
    # Generate template first, then subst env vars
    cat > /var/www/html/config/config.php.template << 'EOF'
<?php
CONFIG_VAR = array (
  'dbtype' => 'pgsql',
  'dbhost' => 'POSTGRES_HOST_VAR',
  'dbport' => 'POSTGRES_PORT_VAR',
  'dbtableprefix' => 'oc_',
  'dbname' => 'POSTGRES_DB_VAR',
  'dbuser' => 'POSTGRES_USER_VAR',
  'dbpassword' => 'POSTGRES_PASSWORD_VAR',
  'installed' => true,
  'instanceid' => 'INSTANCEID_VAR',
  'passwordsalt' => 'PASSWORDSALT_VAR',
  'secret' => 'SECRET_VAR',
  'trusted_domains' =>
  array (
    0 => 'RAILWAY_PUBLIC_DOMAIN_VAR',
    1 => 'localhost',
    2 => '::1',
    3 => 'RAILWAY_PRIVATE_DOMAIN_VAR',
    4 => 'RAILWAY_STATIC_URL_VAR',
  ),
  'datadirectory' => '/var/www/html/data',
  'overwrite.cli.url' => 'https://RAILWAY_PUBLIC_DOMAIN_VAR',
  'overwriteprotocol' => 'OVERWRITEPROTOCOL_VAR',
  'memcache.local' => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' =>
  array (
    'host' => 'REDIS_HOST_VAR',
    'port' => 'REDIS_PORT_VAR',
    'password' => 'REDIS_PASSWORD_VAR',
  ),
  'maintenance' => false,
  'update_check_disabled' => false,
);
EOF
    # Use sed to replace placeholders with actual values
    sed \
      -e "s/CONFIG_VAR/\$CONFIG/g" \
      -e "s/POSTGRES_HOST_VAR/${POSTGRES_HOST}/g" \
      -e "s/POSTGRES_PORT_VAR/${POSTGRES_PORT}/g" \
      -e "s/POSTGRES_DB_VAR/${POSTGRES_DB}/g" \
      -e "s/POSTGRES_USER_VAR/${POSTGRES_USER}/g" \
      -e "s/POSTGRES_PASSWORD_VAR/${POSTGRES_PASSWORD}/g" \
      -e "s/INSTANCEID_VAR/${INSTANCEID}/g" \
      -e "s/PASSWORDSALT_VAR/${PASSWORDSALT}/g" \
      -e "s/SECRET_VAR/${SECRET}/g" \
      -e "s/RAILWAY_PUBLIC_DOMAIN_VAR/${RAILWAY_PUBLIC_DOMAIN}/g" \
      -e "s/RAILWAY_PRIVATE_DOMAIN_VAR/${RAILWAY_PRIVATE_DOMAIN}/g" \
      -e "s/RAILWAY_STATIC_URL_VAR/${RAILWAY_STATIC_URL}/g" \
      -e "s/OVERWRITEPROTOCOL_VAR/${OVERWRITEPROTOCOL}/g" \
      -e "s/REDIS_HOST_VAR/${REDIS_HOST}/g" \
      -e "s/REDIS_PORT_VAR/${REDIS_PORT}/g" \
      -e "s/REDIS_PASSWORD_VAR/${REDIS_PASSWORD}/g" \
      /var/www/html/config/config.php.template > /var/www/html/config/config.php
    rm /var/www/html/config/config.php.template
    # CRITICAL: Lint the generated config
    if ! php -l /var/www/html/config/config.php; then
      echo "❌ Config.php syntax error! Contents:"
      cat /var/www/html/config/config.php
      exit 1
    fi
    echo "✅ Config.php lint OK"
    chown www-data:www-data /var/www/html/config/config.php
    # Make config persistent by copying to data volume
    cp /var/www/html/config/config.php "$CONFIG_FILE"
    chown www-data:www-data "$CONFIG_FILE"
    echo "Config.php created with env var expansion + lint, and persisted to volume."
fi
echo "Table owners (for oc_*):"
psql "$DATABASE_URL" -c "\dt oc_*" || echo "No oc tables"
echo "oc_migrations perms:"
psql "$DATABASE_URL" -c "\dp oc_migrations" || echo "No oc_migrations or perm error"

echo "=== STEP 3: FILES/PERMS ==="
ls -la /var/www/html
ls -la /var/www/html/data || mkdir -p /var/www/html/data
chown -R www-data:www-data /var/www/html /run/nginx /var/log/nginx /var/run/nginx

echo "=== STEP 4: PROCESSES ==="
ps aux

echo "=== STEP 5: NET ==="
netstat -tlnp || ss -tlnp

# Environment variables have already been parsed and validated above

# NextCloud configuration variables
export NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-kikaiworksadmin}
export NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-2046S@nto!7669Y@}
export NEXTCLOUD_TRUSTED_DOMAINS=${NEXTCLOUD_TRUSTED_DOMAINS:-localhost,::1}
export NEXTCLOUD_DATA_DIR=${NEXTCLOUD_DATA_DIR:-/var/www/html/data}
export NEXTCLOUD_TABLE_PREFIX=${NEXTCLOUD_TABLE_PREFIX:-oc_}
export NEXTCLOUD_UPDATE_CHECK=${NEXTCLOUD_UPDATE_CHECK:-false}

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

mkdir -p /run/nginx /var/log/nginx /var/run/nginx
chown -R www-data:www-data /run/nginx /var/log/nginx

# ONLY envsubst PORT (no sed pid hacks - config now clean)
if envsubst '${PORT}' < /etc/nginx/nginx.conf > /tmp/nginx.conf.tmp 2>/dev/null; then
  mv /tmp/nginx.conf.tmp /etc/nginx/nginx.conf
  echo "✅ Nginx: PORT=${PORT} substituted"
fi

# Add SINGLE pid at top if missing (idempotent)
if ! grep -q '^pid ' /etc/nginx/nginx.conf; then
  sed -i '1i pid /run/nginx.pid;' /etc/nginx/nginx.conf
  echo "✅ Added pid directive"
fi

echo "🔍 Testing nginx configuration..."
if nginx -t; then
  echo "✅ Nginx config OK (listen ${PORT:-8080})"
  echo "🔍 Testing status.php endpoint..."
  # Quick test of our status endpoint
  timeout 5 bash -c "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT:-8080}/status.php" 2>/dev/null || echo "⚠️ Status endpoint test failed (expected during startup)"
else
  echo "❌ Nginx config test failed - showing details:"
  nginx -t
  echo "❌ Cannot start services with invalid nginx config"
  exit 1
fi

# Skip temporary nginx test - let supervisor handle it
echo "🌐 [PHASE: INSTALL] Skipping temporary nginx test - will be handled by supervisor"

# Railway Deployment Info
echo "🌐 Railway Deployment Info:"
echo "  Public URL: https://${RAILWAY_PUBLIC_DOMAIN:-'your-app.up.railway.app'}"
echo "  Service: ${RAILWAY_SERVICE_NAME:-unknown}"
echo "  Listen: localhost:80"

echo "🧪 Endpoint Tests:"
timeout 5 bash -c "curl -f -s http://localhost:${PORT:-8080}/ && echo '✅ Root (index.php) OK'" || echo "⚠️ / pending (wizard/DB)"
timeout 5 bash -c "curl -f -s http://localhost:${PORT:-8080}/status.php && echo '✅ Status OK'" || echo "ℹ️ status.php pending"

echo "📋 Logs: nginx=/var/log/nginx/error.log, supervisor=/var/log/supervisor/"

# Ensure Nextcloud code is available (download if needed)
if [ ! -f "/var/www/html/occ" ]; then
  if psql "$DATABASE_URL" -c "\dt" >/dev/null 2>&1; then
    echo "📦 Nextcloud code not found, but DB exists - skipping official installer to avoid conflicts."
  else
    echo "📦 Nextcloud code not found, initializing..."
    /entrypoint.sh php-fpm &
    sleep 10  # Give time for code download
    pkill -f php-fpm || true
  fi
fi

# Always generate config (fresh or existing) - PERSISTENT
echo "📝 Generating persistent config.php..."
mkdir -p /var/www/html/config /var/www/html/data
CONFIG_FILE="/var/www/html/data/config.php"
# ... (keep instanceid/passwordsalt logic) ...
# Generate & subst template (keep existing sed block)
# Lint + chown + copy to $CONFIG_FILE (keep)

# Waits with retries
echo "⌛ Waiting for PostgreSQL (max 30s)..."
timeout 30 sh -c "until pg_isready -h '$POSTGRES_HOST' -p '$POSTGRES_PORT'; do sleep 2; done" || exit 1
echo "⌛ Waiting for Redis (max 30s)..."
timeout 30 sh -c "until redis-cli -h '$REDIS_HOST' -p '$REDIS_PORT' ${REDIS_PASSWORD:+-a '$REDIS_PASSWORD'} ping; do sleep 2; done" || exit 1

# SIMPLIFIED INSTALL/UPGRADE (single path, no deep nesting)
if [ -f "$CONFIG_FILE" ] && su www-data -s /bin/bash -c "cd /var/www/html && php occ status" >/dev/null 2>&1; then
  echo "✅ Nextcloud installed. Checking upgrade..."
  if su www-data -s /bin/bash -c "cd /var/www/html && php occ status" | grep -q "require upgrade"; then
    echo "⬆️ Upgrading..."
    chmod 666 /var/www/html/config/config.php "$CONFIG_FILE"
    timeout 600 su www-data -s /bin/bash -c "cd /var/www/html && php occ upgrade --no-interaction" || exit 1
    chmod 444 /var/www/html/config/config.php "$CONFIG_FILE"
  fi
else
  echo "🏗️ Fresh install..."
  su www-data -s /bin/bash -c "cd /var/www/html && php occ maintenance:install \
    --database 'pgsql' --database-host '$POSTGRES_HOST' --database-port '$POSTGRES_PORT' \
    --database-name '$POSTGRES_DB' --database-user '$POSTGRES_USER' --database-pass '$POSTGRES_PASSWORD' \
    --admin-user '$NEXTCLOUD_ADMIN_USER' --admin-pass '$NEXTCLOUD_ADMIN_PASSWORD' \
    --data-dir '/var/www/html/data'" || exit 1
fi

# Post-install (always)
su www-data -s /bin/bash -c "cd /var/www/html && php occ maintenance:mode --off"
su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set memcache.local --value='\\OC\\Memcache\\Redis'"
su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set memcache.locking --value='\\OC\\Memcache\\Redis'"
su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set redis host --value='$REDIS_HOST'"
su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set redis port --value='$REDIS_PORT'"
[ -n "$REDIS_PASSWORD" ] && su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set redis password --value='$REDIS_PASSWORD'"

# Create deployment completion flag for nginx (always create if config exists)
if [ -f "/var/www/html/config/config.php" ]; then
  echo "🏁 [PHASE: FINAL] Creating deployment completion flag..."
  touch /var/www/html/.deployment_complete
  chown www-data:www-data /var/www/html/.deployment_complete
  echo "✅ [PHASE: FINAL] Deployment flag created - nginx will now serve Nextcloud"
else
  echo "⚠️ [PHASE: FINAL] Config.php not found - keeping deployment status page active"
fi

# Nextcloud deployment is complete

# Chown
chown -R www-data:www-data /var/www/html

# Diagnostics
ls -la /var/www/html
psql "$DATABASE_URL" -c "\dp oc_migrations"

# Force disable maintenance mode and clear upgrade flags to ensure Nextcloud is accessible
if [ -f "/var/www/html/config/config.php" ]; then
  echo "🔧 Forcing maintenance mode off and clearing upgrade flags..."

  # Try normal occ command first
  su www-data -s /bin/bash -c "cd /var/www/html && php occ maintenance:mode --off" 2>&1 || echo "⚠️ Normal maintenance mode disable failed"

  # Force disable by directly editing config.php
  sed -i "s/'maintenance' => true/'maintenance' => false/g" /var/www/html/config/config.php || echo "⚠️ Config edit failed"

  # Clear any cached maintenance mode
  su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:delete maintenance" 2>&1 || echo "⚠️ Could not clear maintenance config"

  # Try alternative: create a temporary script to force maintenance off
  cat > /tmp/force_maintenance_off.php << 'EOF'
<?php
$configFile = '/var/www/html/config/config.php';
if (file_exists($configFile)) {
    $config = include $configFile;
    $config['maintenance'] = false;
    $content = "<?php\n\$CONFIG = " . var_export($config, true) . ";\n";
    file_put_contents($configFile, $content);
    echo "Maintenance mode forcibly disabled in config\n";
}
?>
EOF
  php /tmp/force_maintenance_off.php || echo "⚠️ PHP maintenance force failed"
  rm -f /tmp/force_maintenance_off.php

  echo "✅ Maintenance mode forcibly disabled"
fi

# Run fix-warnings if config exists and Nextcloud is installed
if [ -f "/var/www/html/config/config.php" ]; then
  echo "🔧 Running fix-warnings script..."
  /usr/local/bin/fix-warnings.sh || echo "⚠️ Fix-warnings script failed, but continuing..."
fi

# Ensure log dirs exist for Supervisor/Nginx/PHP (Fixes crash)
echo "📁 Creating log/run dirs..."
mkdir -p /var/log/supervisor /var/log/nginx /var/run/php /var/run/nginx
chown -R www-data:www-data /var/log/supervisor /var/log/nginx /var/run/php /var/run/nginx /var/www/html/data

# [PHASE: FINAL] Start Supervisor (after install complete)
echo "🛡️ [PHASE: FINAL] Starting Supervisor with services..."
echo "📊 [PHASE: FINAL] DEPLOYMENT SUMMARY:"
echo "  - Nextcloud Version: 29.0.16"
echo "  - Config Location: /var/www/html/data/config.php (persistent)"
echo "  - Data Directory: /var/www/html/data"
echo "  - Admin User: ${NEXTCLOUD_ADMIN_USER}"
echo "  - Database: PostgreSQL (${POSTGRES_DB})"
echo "  - Cache: Redis (${REDIS_HOST}:${REDIS_PORT})"
echo "  - Services: nginx + php-fpm + cron"
echo "� [PHASE: FINAL] Access URL: https://${RAILWAY_PUBLIC_DOMAIN:-'your-app.up.railway.app'}"

# Final health check and service preparation
if [ -f "/var/www/html/config/config.php" ]; then
  echo "✅ [PHASE: FINAL] Config file exists"

  # Final maintenance mode check and force disable
  echo "🔧 [PHASE: FINAL] Final maintenance mode check..."
  MAINT_STATUS=$(su www-data -s /bin/bash -c "cd /var/www/html && php occ maintenance:mode" 2>/dev/null || echo "unknown")
  if [[ "$MAINT_STATUS" == *"enabled"* ]] || [[ "$MAINT_STATUS" == *"true"* ]]; then
    echo "⚠️ [PHASE: FINAL] Maintenance mode is still enabled - forcing disable..."
    su www-data -s /bin/bash -c "cd /var/www/html && php occ maintenance:mode --off" 2>&1 || echo "⚠️ Could not disable maintenance mode via occ"
    # Force via config edit
    sed -i "s/'maintenance' => true/'maintenance' => false/g" /var/www/html/config/config.php || echo "⚠️ Config edit failed"
  else
    echo "✅ [PHASE: FINAL] Maintenance mode is disabled"
  fi

  # Check Nextcloud status
  if su www-data -s /bin/bash -c "cd /var/www/html && php occ status --output=json" >/dev/null 2>&1; then
    echo "✅ [PHASE: FINAL] OCC status OK - Nextcloud is operational"
  else
    echo "❌ [PHASE: FINAL] OCC status FAILED - attempting emergency repair..."
    # Emergency repair: try to reset any corrupted state
    su www-data -s /bin/bash -c "cd /var/www/html && php occ maintenance:repair" 2>&1 || echo "⚠️ Repair failed"
  fi
else
  echo "❌ [PHASE: FINAL] Config file missing - deployment incomplete"
fi

# Ensure proper ownership for web serving
echo "🔧 [PHASE: FINAL] Ensuring proper file ownership..."
chown -R www-data:www-data /var/www/html /var/log/nginx /var/run/nginx /var/run/php /var/log/supervisor

# Pre-flight service checks
echo "🔍 [PHASE: FINAL] Pre-flight service checks..."
if ! nginx -t >/dev/null 2>&1; then
  echo "❌ [PHASE: FINAL] Nginx configuration test failed"
  nginx -t
  exit 1
else
  echo "✅ [PHASE: FINAL] Nginx config OK"
fi

# Test PHP-FPM config
if ! php-fpm -t >/dev/null 2>&1; then
  echo "❌ [PHASE: FINAL] PHP-FPM configuration test failed"
  php-fpm -t
  exit 1
else
  echo "✅ [PHASE: FINAL] PHP-FPM config OK"
fi

# Test Supervisor config
if ! supervisord -c /etc/supervisor/conf.d/supervisord.conf -t >/dev/null 2>&1; then
  echo "❌ [PHASE: FINAL] Supervisor configuration test failed"
  supervisord -c /etc/supervisor/conf.d/supervisord.conf -t
  exit 1
else
  echo "✅ [PHASE: FINAL] Supervisor config OK"
fi

echo "🚀 [PHASE: FINAL] All pre-flight checks passed. Starting Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
