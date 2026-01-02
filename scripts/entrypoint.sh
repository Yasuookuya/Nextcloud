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

# Set Nextcloud version from Dockerfile
export NEXTCLOUD_VERSION="29.0.16"

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

fix_permissions() {
  echo "🔧 Fixing permissions (Nextcloud docs)..."
  mkdir -p /var/www/html/{config,data}
  chown -R www-data:www-data /var/www/html{,/config,/data}
  find /var/www/html/ -type d -exec chmod 750 {} + 2>/dev/null || true
  find /var/www/html/ -type f -exec chmod 640 {} + 2>/dev/null || true
  chmod 770 /var/www/html/data 2>/dev/null || true
  echo "✅ Permissions fixed (dirs:750 files:640 data:770)"
}

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
  'config_is_read_only' => false,  // Temp; locked post-upgrade
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
  'htaccess.RewriteBase' => '/',
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

fix_permissions  # Early enforcement

# Check database version compatibility (after config is ready)
if psql "$DATABASE_URL" -c "\dt oc_*" >/dev/null 2>&1; then
  echo "🔍 Checking database version compatibility..."
  # Try a quick upgrade test to see if it's compatible
  UPGRADE_TEST=$(timeout 30 su www-data -s /bin/bash -c "cd /var/www/html && php occ upgrade --no-interaction" 2>&1 | head -10)
  if echo "$UPGRADE_TEST" | grep -q "Updates between multiple major versions and downgrades are unsupported"; then
    echo "⚠️ Database schema is incompatible with Nextcloud 29.0.16"
    echo "💡 Detected old Nextcloud version - resetting for clean installation"
    echo "🔄 Resetting database for clean 29.0.16 installation..."
    # Reset database for clean install
    psql "$DATABASE_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO postgres; GRANT ALL ON SCHEMA public TO public;" 2>/dev/null || echo "⚠️ DB reset failed"
    DB_HAS_TABLES=false
    echo "✅ Database reset complete - will perform fresh installation"
  else
    echo "✅ Database appears compatible with Nextcloud 29.0.16"
  fi
fi

echo "🚀 [UPGRADE PHASE] Consolidated upgrade/repair (https://docs.nextcloud.com/server/29/admin_manual/maintenance/upgrade.html)..."

su www-data -s /bin/bash -c "
  cd /var/www/html &&
  php occ maintenance:mode --on || true
"

# Upgrade with retry
for attempt in {1..3}; do
  if timeout 600 su www-data -s /bin/bash -c "cd /var/www/html && php occ upgrade --no-interaction"; then
    echo "✅ Core upgrade OK"
    break
  else
    echo "⚠️ Upgrade attempt $attempt/3 failed, retry..."
    sleep 10
  fi
done || echo "⚠️ Upgrade partial, continuing..."

timeout 300 su www-data -s /bin/bash -c "cd /var/www/html && php occ app:update --all --no-interaction" || true

su www-data -s /bin/bash -c "
  cd /var/www/html &&
  php occ maintenance:repair --include-expensive || true &&
  php occ config:system:set htaccess.RewriteBase --value=/ &&
  php occ maintenance:update:htaccess &&
  php occ maintenance:mode --off
"

# Redis (idempotent)
su www-data -s /bin/bash -c "
  cd /var/www/html &&
  php occ config:system:set memcache.local --value='\\\\OC\\\\Memcache\\\\Redis' &&
  php occ config:system:set memcache.locking --value='\\\\OC\\\\Memcache\\\\Redis' &&
  php occ config:system:set redis.host --value='$REDIS_HOST' &&
  php occ config:system:set redis.port --value=$REDIS_PORT
"
[ -n "$REDIS_PASSWORD" ] && su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set redis.password --value='$REDIS_PASSWORD'"

# Lock read-only
su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set config_is_read_only --value=true" || true
sed -i "s/'config_is_read_only' => false/'config_is_read_only' => true/g" /var/www/html/config/config.php /var/www/html/data/config.php 2>/dev/null || true

fix_permissions  # Final lock: 750/640/444

echo "✅ Upgrade/Pretty/Redis/Read-only complete."

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
echo "🔗 [PHASE: FINAL] Access URL: https://${RAILWAY_PUBLIC_DOMAIN:-'your-app.up.railway.app'}"

# Final health check and service preparation
if [ -f "/var/www/html/config/config.php" ]; then
  echo "✅ [PHASE: FINAL] Config file exists"

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

# Auto-upgrade (www-data, Nextcloud docs)
echo "⬆️ [PHASE: FINAL] Checking for Nextcloud updates..."
FINAL_AUTO_VERSION=$(su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:get version 2>/dev/null || echo 'unknown'")
if [ "$FINAL_AUTO_VERSION" = "$NEXTCLOUD_VERSION" ] || [ "$FINAL_AUTO_VERSION" = "unknown" ]; then
  echo "✅ Proceeding with final auto-upgrade..."
  su www-data -s /bin/bash -c '
    cd /var/www/html &&
    php occ maintenance:mode --on &&
    php occ upgrade --no-interaction --verbose &&
    php occ maintenance:mode --off &&
    php occ background-job:cron
  ' || echo "⚠️ [PHASE: FINAL] Auto-upgrade failed (non-fatal)"
else
  echo "⚠️ [PHASE: FINAL] Skipping auto-upgrade: DB version $FINAL_AUTO_VERSION != Code version $NEXTCLOUD_VERSION"
fi

echo "🔍 Final status:"
su www-data -s /bin/bash -c "cd /var/www/html && php occ status --output=json" || echo "⚠️ Final OCC failed"

echo "🚀 [PHASE: FINAL] All pre-flight checks passed. Starting Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
