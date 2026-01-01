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

# [PHASE: INSTALL/UPGRADE] Handle both fresh installs and upgrades
if [ -f "/var/www/html/config/config.php" ]; then
  echo "✅ [PHASE: INSTALL/UPGRADE] Config exists → Checking installation status."

  # Test config readability first
  echo "🔍 [PHASE: INSTALL/UPGRADE] Testing config readability..."
  OCC_STATUS_OUTPUT=$(su www-data -s /bin/bash -c "cd /var/www/html && php occ status --output=json" 2>&1)
  if echo "$OCC_STATUS_OUTPUT" | grep -q "require upgrade"; then
    echo "🔄 [PHASE: INSTALL/UPGRADE] Config readable but upgrade needed."
    CONFIG_READABLE=false
    UPGRADE_NEEDED=true
  elif [ $? -eq 0 ]; then
    echo "✅ [PHASE: INSTALL/UPGRADE] Config readable, Nextcloud appears installed."
    CONFIG_READABLE=true
  else
    echo "⚠️ [PHASE: INSTALL/UPGRADE] Config exists but occ status failed - may need installation or repair."
    OCC_STATUS=$(su www-data -s /bin/bash -c "cd /var/www/html && php occ status" 2>&1 || echo "OCC_FAILED")
    echo "🔍 [PHASE: INSTALL/UPGRADE] OCC status output: $OCC_STATUS"

    # Debug: Check config.php syntax and database connection
    echo "🔍 [PHASE: INSTALL/UPGRADE] Debugging config.php..."
    if [ -f "/var/www/html/config/config.php" ]; then
      php -l /var/www/html/config/config.php && echo "✅ Config.php syntax OK" || echo "❌ Config.php syntax error"
      echo "📄 Config.php contents (first 10 lines):"
      head -10 /var/www/html/config/config.php
    fi

    # Debug: Test database connection directly
    echo "🔍 [PHASE: INSTALL/UPGRADE] Testing database connection..."
    DB_TEST=$(psql "$DATABASE_URL" -c "SELECT version();" 2>&1 || echo "DB_CONNECT_FAILED")
    if [[ "$DB_TEST" == *"DB_CONNECT_FAILED"* ]]; then
      echo "❌ Database connection failed: $DB_TEST"
      echo "🔧 Attempting to fix database connection..."
      # Try alternative connection method
      export PGPASSWORD="$POSTGRES_PASSWORD"
      DB_TEST_ALT=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();" 2>&1 || echo "DB_CONNECT_ALT_FAILED")
      if [[ "$DB_TEST_ALT" == *"DB_CONNECT_ALT_FAILED"* ]]; then
        echo "❌ Alternative database connection also failed: $DB_TEST_ALT"
        exit 1
      else
        echo "✅ Alternative database connection successful"
      fi
    else
      echo "✅ Database connection successful"
    fi

    # Check if database tables exist
    TABLE_COUNT=$(psql "$DATABASE_URL" -c "\dt oc_*" 2>/dev/null | grep -c "table" || echo "0")
    echo "🔍 [PHASE: INSTALL/UPGRADE] Found $TABLE_COUNT Nextcloud tables"

    # Force fresh installation if OCC status fails consistently
    if [ "$TABLE_COUNT" -eq "0" ] || [[ "$OCC_STATUS" == *"Memcache"* ]] || [[ "$OCC_STATUS" == *"not available"* ]]; then
      echo "📦 [PHASE: INSTALL/UPGRADE] Performing fresh installation (no tables or cache issues detected)"

      # Clean up any existing broken config that might interfere
      if [ -f "/var/www/html/config/config.php" ]; then
        echo "🧹 [PHASE: INSTALL/UPGRADE] Removing potentially broken config.php"
        rm -f /var/www/html/config/config.php
      fi

      # Fresh installation with explicit data directory
      mkdir -p /var/www/html/data
      chown www-data:www-data /var/www/html/data

      INSTALL_CMD="cd /var/www/html && php occ maintenance:install --database pgsql --database-name $POSTGRES_DB --database-host $POSTGRES_HOST --database-port $POSTGRES_PORT --database-user $POSTGRES_USER --database-pass $POSTGRES_PASSWORD --admin-user $NEXTCLOUD_ADMIN_USER --admin-pass $NEXTCLOUD_ADMIN_PASSWORD --data-dir /var/www/html/data"
      echo "🏗️ [PHASE: INSTALL/UPGRADE] Running: $INSTALL_CMD"

      if su www-data -s /bin/bash -c "$INSTALL_CMD" 2>&1; then
        echo "✅ [PHASE: INSTALL/UPGRADE] Fresh installation completed successfully."

        # Verify installation worked
        if su www-data -s /bin/bash -c "cd /var/www/html && php occ status --output=json" 2>&1; then
          echo "✅ [PHASE: INSTALL/UPGRADE] Installation verified - OCC status OK"
          CONFIG_READABLE=true
        else
          echo "❌ [PHASE: INSTALL/UPGRADE] Installation verification failed"
          exit 1
        fi
      else
        echo "❌ [PHASE: INSTALL/UPGRADE] Fresh installation failed!"
        exit 1
      fi
    else
      echo "🔧 [PHASE: INSTALL/UPGRADE] Database tables exist - attempting upgrade."

      # Enable maintenance mode before upgrade
      echo "🔧 [PHASE: UPGRADE] Enabling maintenance mode for upgrade..."
      MAINT_ON=$(su www-data -s /bin/bash -c "cd /var/www/html && php occ maintenance:mode --on" 2>&1 || echo "FAILED")
      if [[ "$MAINT_ON" == *"FAILED"* ]]; then
        echo "⚠️ [PHASE: UPGRADE] Failed to enable maintenance mode: $MAINT_ON"
      else
        echo "✅ [PHASE: UPGRADE] Maintenance mode enabled."
      fi

      # Run upgrade with verbose output and no interaction
      echo "⬆️ [PHASE: UPGRADE] Running Nextcloud upgrade..."
      UPGRADE_CMD=$(su www-data -s /bin/bash -c "cd /var/www/html && php occ upgrade --no-interaction" 2>&1)
      UPGRADE_EXIT_CODE=$?

      echo "🔍 [PHASE: UPGRADE] Upgrade output:"
      echo "$UPGRADE_CMD"

      if [ $UPGRADE_EXIT_CODE -eq 0 ] && [[ "$UPGRADE_CMD" != *"FAILED"* ]] && [[ "$UPGRADE_CMD" != *"error"* ]] && [[ "$UPGRADE_CMD" != *"Error"* ]]; then
        echo "✅ [PHASE: UPGRADE] Upgrade completed successfully."

        # Verify upgrade was successful by checking version
        UPGRADE_CHECK=$(su www-data -s /bin/bash -c "cd /var/www/html && php occ status --output=json" 2>&1 || echo "CHECK_FAILED")
        if echo "$UPGRADE_CHECK" | grep -q "version"; then
          echo "✅ [PHASE: UPGRADE] Version check passed - upgrade verified."
        else
          echo "⚠️ [PHASE: UPGRADE] Version check failed, but continuing..."
        fi
      else
        echo "❌ [PHASE: UPGRADE] Upgrade failed with exit code $UPGRADE_EXIT_CODE: $UPGRADE_CMD"

        # Force maintenance mode off even if upgrade failed
        echo "🔧 [PHASE: UPGRADE] Attempting to force disable maintenance mode..."
        su www-data -s /bin/bash -c "cd /var/www/html && php occ maintenance:mode --off" 2>&1 || echo "⚠️ Could not disable maintenance mode"
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
  su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set memcache.local --value=\\OC\\Memcache\\Redis" 2>&1 || echo "⚠️ Redis local cache config failed"
  su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set memcache.locking --value=\\OC\\Memcache\\Redis" 2>&1 || echo "⚠️ Redis locking config failed"
  su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set redis host --value=${REDIS_HOST}" 2>&1 || echo "⚠️ Redis host config failed"
  su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set redis port --value=${REDIS_PORT}" 2>&1 || echo "⚠️ Redis port config failed"
  [ -n "$REDIS_PASSWORD" ] && su www-data -s /bin/bash -c "cd /var/www/html && php occ config:system:set redis password --value=${REDIS_PASSWORD}" 2>&1 || echo "⚠️ Redis password config failed"
  echo "✅ [PHASE: UPGRADE] Redis configuration applied."

  # Scans + cron (skip for fresh installs to speed up deployment)
  if [ "$TABLE_COUNT" -gt "10" ]; then
    echo "📁 [PHASE: UPGRADE] Running file scans (upgrade detected)..."
    su www-data -s /bin/bash -c "cd /var/www/html && php occ files:scan --all" 2>&1 || echo "⚠️ File scan failed"
    su www-data -s /bin/bash -c "cd /var/www/html && php occ groupfolders:scan --all" 2>&1 || echo "⚠️ Group folders scan failed"
  else
    echo "📁 [PHASE: UPGRADE] Skipping file scans for fresh install (will run later)..."
  fi
  su www-data -s /bin/bash -c "cd /var/www/html && php occ background-job:cron" 2>&1 || echo "⚠️ Background jobs failed"
  # Skip integrity check for speed
  echo "⚠️ Skipping integrity check for deployment speed"

  echo "✅ [PHASE: UPGRADE] Upgrade & post-setup complete. Admin: ${NEXTCLOUD_ADMIN_USER}/${NEXTCLOUD_ADMIN_PASSWORD}"
    fi
  fi
else
  echo "⚠️ [PHASE: UPGRADE] No config found - basic installation may still work."
fi

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
echo "🔗 [PHASE: FINAL] Access URL: https://${RAILWAY_PUBLIC_DOMAIN:-'your-app.up.railway.app'}"

# Final health check
if [ -f "/var/www/html/config/config.php" ]; then
  echo "✅ [PHASE: FINAL] Config file exists"
  if su www-data -s /bin/bash -c "cd /var/www/html && php occ status --output=json" >/dev/null 2>&1; then
    echo "✅ [PHASE: FINAL] OCC status OK - Nextcloud is operational"
  else
    echo "❌ [PHASE: FINAL] OCC status FAILED - Check logs for issues"
  fi
else
  echo "❌ [PHASE: FINAL] Config file missing - deployment incomplete"
fi

echo "🚀 [PHASE: FINAL] Supervisor starting..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
