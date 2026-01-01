#!/bin/bash
set -e

# Railway configuration - embedded
export POSTGRES_HOST=${POSTGRES_HOST:-"postgres-n76t.railway.internal"}
export POSTGRES_PORT=${POSTGRES_PORT:-"5432"}
export POSTGRES_USER=${POSTGRES_USER:-"postgres"}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-"uejIXoiQzAqOoFZFBOqZCnjovieZlgui"}
export POSTGRES_DB=${POSTGRES_DB:-"railway"}

export DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

export PGSSLMODE=disable

export REDIS_HOST=${REDIS_HOST:-"redis-svle.railway.internal"}
export REDIS_PORT=${REDIS_PORT:-"6379"}
export REDIS_HOST_PASSWORD=${REDIS_HOST_PASSWORD:-"OyHpmNkWOQsPxrzLBxrXiAlnRlYbWeFY"}

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

echo "=== [PHASE: DB_CHECK] STEP 2: DB DIAG ==="
echo "🔍 [PHASE: DB_CHECK] Checking database connectivity..."
DB_TABLES=$(psql "$DATABASE_URL" -c "\dt" 2>&1)
if [ $? -eq 0 ]; then
  echo "✅ [PHASE: DB_CHECK] Database connection successful."
  echo "📊 [PHASE: DB_CHECK] Tables found:"
  echo "$DB_TABLES"
  TABLE_COUNT=$(echo "$DB_TABLES" | grep -c "table")
  echo "📈 [PHASE: DB_CHECK] Total tables: $TABLE_COUNT"
else
  echo "❌ [PHASE: DB_CHECK] Database connection failed:"
  echo "$DB_TABLES"
  exit 1
fi

# Grant permissions to postgres user if tables exist (fix for existing DB)
if psql "$DATABASE_URL" -c "\dt" >/dev/null 2>&1; then
  echo "Reassigning ownership and granting permissions to postgres user on existing tables..."
  psql "$DATABASE_URL" -c "REASSIGN OWNED BY oc_admin TO postgres;" 2>/dev/null || echo "Reassign failed, continuing..."
  psql "$DATABASE_URL" -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres; GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres;" || echo "Grant failed, continuing..."
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
$CONFIG = array (
  'dbtype' => 'pgsql',
  'dbhost' => '${POSTGRES_HOST}',
  'dbport' => '${POSTGRES_PORT}',
  'dbtableprefix' => 'oc_',
  'dbname' => '${POSTGRES_DB}',
  'dbuser' => '${POSTGRES_USER}',
  'dbpassword' => '${POSTGRES_PASSWORD}',
  'installed' => true,
  'instanceid' => '${INSTANCEID}',
  'passwordsalt' => '${PASSWORDSALT}',
  'secret' => '${SECRET}',
  'trusted_domains' =>
  array (
    0 => '${RAILWAY_PUBLIC_DOMAIN}',
    1 => 'localhost',
    2 => '::1',
    3 => '${RAILWAY_PRIVATE_DOMAIN}',
    4 => '${RAILWAY_STATIC_URL}',
  ),
  'datadirectory' => '/var/www/html/data',
  'overwrite.cli.url' => 'https://${RAILWAY_PUBLIC_DOMAIN}',
  'overwriteprotocol' => '${OVERWRITEPROTOCOL}',
  'memcache.local' => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' =>
  array (
    'host' => '${REDIS_HOST}',
    'port' => '${REDIS_PORT}',
    'password' => '${REDIS_PASSWORD}',
  ),
  'maintenance' => false,
  'update_check_disabled' => false,
);
EOF
    envsubst '${POSTGRES_HOST} ${POSTGRES_PORT} ${POSTGRES_DB} ${POSTGRES_USER} ${POSTGRES_PASSWORD} ${INSTANCEID} ${PASSWORDSALT} ${SECRET} ${RAILWAY_PUBLIC_DOMAIN} ${RAILWAY_PRIVATE_DOMAIN} ${RAILWAY_STATIC_URL} ${OVERWRITEPROTOCOL} ${REDIS_HOST} ${REDIS_PORT} ${REDIS_PASSWORD}' < /var/www/html/config/config.php.template > /var/www/html/config/config.php
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
export NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-kikaiworksadmin}
export NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-2046S@nto!7669Y@}
export NEXTCLOUD_TRUSTED_DOMAINS=${NEXTCLOUD_TRUSTED_DOMAINS:-localhost,::1}
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

mkdir -p /var/run/nginx /var/log/nginx /var/lib/nginx/logs
chown -R www-data:www-data /var/run/nginx /var/log/nginx

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

nginx -t && echo "✅ Nginx config OK (listen ${PORT:-8080})" || { echo "❌ Nginx failed"; nginx -t; exit 1; }

# Railway Deployment Info
echo "🌐 Railway Deployment Info:"
echo "  Public URL: https://${RAILWAY_PUBLIC_DOMAIN:-'your-app.up.railway.app'}"
echo "  Service: ${RAILWAY_SERVICE_NAME:-unknown}"
echo "  Listen: localhost:80"

echo "🧪 Endpoint Tests:"
timeout 5 bash -c "curl -f -s http://localhost/ && echo '✅ Root (index.php) OK'" || echo "⚠️ / pending (wizard/DB)"
timeout 5 bash -c "curl -f -s http://localhost/status.php && echo '✅ Status OK'" || echo "ℹ️ status.php pending"

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

# [PHASE: UPGRADE] PRESERVE config if exists (don't delete!)
if [ -f "/var/www/html/config/config.php" ]; then
  echo "✅ [PHASE: UPGRADE] Config exists + DB populated → Running safe upgrade/post-setup."

  # Test config readability first
  echo "🔍 [PHASE: UPGRADE] Testing config readability..."
  if su www-data -s /bin/bash -c "php occ status --output=json" 2>&1; then
    echo "✅ [PHASE: UPGRADE] Config readable, proceeding with upgrade."
  else
    echo "❌ [PHASE: UPGRADE] Config unreadable - checking details..."
    OCC_STATUS=$(su www-data -s /bin/bash -c "php occ status" 2>&1 || echo "OCC_FAILED")
    echo "🔍 [PHASE: UPGRADE] OCC status output: $OCC_STATUS"
    if [[ "$OCC_STATUS" == *"Configuration was not read or initialized correctly"* ]]; then
      echo "❌ [PHASE: UPGRADE] Config read error - instance ID mismatch detected."
      echo "💡 [PHASE: UPGRADE] This usually means config values changed between deploys."
      echo "🔧 [PHASE: UPGRADE] Check if config.php in data/ matches DB stored values."
    fi
    echo "🛑 [PHASE: UPGRADE] Exiting due to config issues."
    exit 1
  fi

  # Maintenance mode
  echo "🔧 [PHASE: UPGRADE] Enabling maintenance mode..."
  MAINT_ON=$(su www-data -s /bin/bash -c "php occ maintenance:mode --on" 2>&1 || echo "FAILED")
  if [[ "$MAINT_ON" == *"FAILED"* ]]; then
    echo "⚠️ [PHASE: UPGRADE] Maintenance mode enable failed: $MAINT_ON"
  else
    echo "✅ [PHASE: UPGRADE] Maintenance mode enabled."
  fi

  # Upgrade
  echo "⬆️ [PHASE: UPGRADE] Running database upgrade..."
  UPGRADE=$(su www-data -s /bin/bash -c "php occ upgrade --no-interaction --force" 2>&1 || echo "FAILED")
  if [[ "$UPGRADE" == *"FAILED"* ]]; then
    echo "⚠️ [PHASE: UPGRADE] Upgrade failed: $UPGRADE"
  else
    echo "✅ [PHASE: UPGRADE] Upgrade completed."
  fi

  # Maintenance mode off
  echo "🔧 [PHASE: UPGRADE] Disabling maintenance mode..."
  MAINT_OFF=$(su www-data -s /bin/bash -c "php occ maintenance:mode --off" 2>&1 || echo "FAILED")
  if [[ "$MAINT_OFF" == *"FAILED"* ]]; then
    echo "⚠️ [PHASE: UPGRADE] Maintenance mode disable failed: $MAINT_OFF"
  else
    echo "✅ [PHASE: UPGRADE] Maintenance mode disabled."
  fi

  # Redis/memcache (idempotent)
  echo "⚙️ [PHASE: UPGRADE] Configuring Redis caching..."
  su www-data -s /bin/bash -c "php occ config:system:set memcache.local --value=\\OC\\Memcache\\Redis" 2>&1 || echo "⚠️ Redis local cache config failed"
  su www-data -s /bin/bash -c "php occ config:system:set memcache.locking --value=\\OC\\Memcache\\Redis" 2>&1 || echo "⚠️ Redis locking config failed"
  su www-data -s /bin/bash -c "php occ config:system:set redis host --value=${REDIS_HOST}" 2>&1 || echo "⚠️ Redis host config failed"
  su www-data -s /bin/bash -c "php occ config:system:set redis port --value=${REDIS_PORT}" 2>&1 || echo "⚠️ Redis port config failed"
  [ -n "$REDIS_PASSWORD" ] && su www-data -s /bin/bash -c "php occ config:system:set redis password --value=${REDIS_PASSWORD}" 2>&1 || echo "⚠️ Redis password config failed"
  echo "✅ [PHASE: UPGRADE] Redis configuration applied."

  # Scans + cron
  echo "📁 [PHASE: UPGRADE] Running file scans..."
  su www-data -s /bin/bash -c "php occ files:scan --all" 2>&1 || echo "⚠️ File scan failed"
  su www-data -s /bin/bash -c "php occ groupfolders:scan --all" 2>&1 || echo "⚠️ Group folders scan failed"
  su www-data -s /bin/bash -c "php occ background-job:cron" 2>&1 || echo "⚠️ Background jobs failed"
  su www-data -s /bin/bash -c "php occ integrity:check-core --skip-migrations" 2>&1 || echo "⚠️ Integrity check failed"

  echo "✅ [PHASE: UPGRADE] Upgrade & post-setup complete. Admin: ${NEXTCLOUD_ADMIN_USER}/${NEXTCLOUD_ADMIN_PASSWORD}"

  # Create deployment completion flag for nginx
  echo "🏁 [PHASE: FINAL] Creating deployment completion flag..."
  touch /var/www/html/.deployment_complete
  echo "✅ [PHASE: FINAL] Deployment flag created - nginx will now serve Nextcloud"
else
  echo "⚠️ [PHASE: UPGRADE] No config found - web installer needed."
fi

# Chown
chown -R www-data:www-data /var/www/html

# Diagnostics
ls -la /var/www/html
psql "$DATABASE_URL" -c "\dp oc_migrations"

# Run fix-warnings if config exists
if [ -f "/var/www/html/config/config.php" ]; then
  /usr/local/bin/fix-warnings.sh  # Run any warning fixes
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
echo "🔗 [PHASE: FINAL] Access URL: https://${RAILWAY_PUBLIC_DOMAIN:-'your-app.up.railway.app'}"

# Final health check
if [ -f "/var/www/html/config/config.php" ]; then
  echo "✅ [PHASE: FINAL] Config file exists"
  if su www-data -s /bin/bash -c "php occ status --output=json" >/dev/null 2>&1; then
    echo "✅ [PHASE: FINAL] OCC status OK - Nextcloud is operational"
  else
    echo "❌ [PHASE: FINAL] OCC status FAILED - Check logs for issues"
  fi
else
  echo "❌ [PHASE: FINAL] Config file missing - deployment incomplete"
fi

echo "🚀 [PHASE: FINAL] Supervisor starting..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
