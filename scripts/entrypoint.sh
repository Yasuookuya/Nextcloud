#!/bin/bash
set -e

echo "🚀 Starting NextCloud Railway deployment..."
echo "🐛 DEBUG: Current script: $0"
echo "🐛 DEBUG: Process ID: $$"
echo "🐛 DEBUG: All running scripts:"
ps aux | grep -E "(entrypoint|fix-warnings)" || echo "No matching processes found"

# Debug: Print all environment variables starting with POSTGRES or REDIS
echo "🔍 DIAGNOSTIC: Environment variables:"
env | grep -E "^(POSTGRES|REDIS.*|RAILWAY|PG|NEXTCLOUD|PHP|SSL)" | sort

# Also check for any database-related variables
echo "🔍 DIAGNOSTIC: Database-related variables:"
env | grep -iE "(database|db|host|ssl)" | sort

# Check for SSL certificates
echo "🔍 DIAGNOSTIC: Checking for SSL certificates..."
if [ -n "$SSL_CERT_FILE" ] && [ -f "$SSL_CERT_FILE" ]; then
    echo "✅ SSL certificate file found at: $SSL_CERT_FILE"
    ls -la "$SSL_CERT_FILE"
    chmod 644 "$SSL_CERT_FILE" 2>/dev/null || echo "⚠️ Could not set SSL cert permissions"
else
    echo "ℹ️ No SSL_CERT_FILE found or file missing"
fi

if [ -n "$SSL_KEY_FILE" ] && [ -f "$SSL_KEY_FILE" ]; then
    echo "✅ SSL key file found at: $SSL_KEY_FILE"
    ls -la "$SSL_KEY_FILE"
    chmod 600 "$SSL_KEY_FILE" 2>/dev/null || echo "⚠️ Could not set SSL key permissions"
else
    echo "ℹ️ No SSL_KEY_FILE found or file missing"
fi

# Check for environment variables - we need at least some PostgreSQL config
# Check for Railway's PG* variables OR POSTGRES_* variables OR DATABASE_URL
echo "🔍 DIAGNOSTIC: Checking PostgreSQL configuration..."
if [ -z "$POSTGRES_HOST" ] && [ -z "$DATABASE_URL" ] && [ -z "$POSTGRES_USER" ] && [ -z "$PGHOST" ] && [ -z "$PGUSER" ]; then
    echo "❌ No PostgreSQL configuration found!"
    echo "Set either individual POSTGRES_* variables, PG* variables, or DATABASE_URL"
    echo "Available environment variables:"
    env | grep -E "^(PG|POSTGRES|DATABASE)" | sort
    exit 1
else
    echo "✅ PostgreSQL configuration detected"
fi

# If DATABASE_URL is provided, parse it
if [ -n "$DATABASE_URL" ] && [ -z "$POSTGRES_HOST" ]; then
    echo "📊 DIAGNOSTIC: Parsing DATABASE_URL..."
    export POSTGRES_HOST=$(echo $DATABASE_URL | sed -n 's|postgresql://[^:]*:[^@]*@\([^:]*\):.*|\1|p')
    export POSTGRES_PORT=$(echo $DATABASE_URL | sed -n 's|postgresql://[^:]*:[^@]*@[^:]*:\([0-9]*\)/.*|\1|p')
    export POSTGRES_USER=$(echo $DATABASE_URL | sed -n 's|postgresql://\([^:]*\):.*|\1|p')
    export POSTGRES_PASSWORD=$(echo $DATABASE_URL | sed -n 's|postgresql://[^:]*:\([^@]*\)@.*|\1|p')
    export POSTGRES_DB=$(echo $DATABASE_URL | sed -n 's|.*/\([^?]*\).*|\1|p')
    echo "✅ Parsed DATABASE_URL: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
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
echo "🔍 DIAGNOSTIC: Configuring Apache for port: $PORT"
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
        echo "🔍 DIAGNOSTIC: Admin credentials provided - creating full config.php"
        rm -f /var/www/html/config/config.php
        mkdir -p /var/www/html/config
        # Generate secrets
        INSTANCEID=$(head -c32 /dev/urandom | base64)
        PASSWORDSALT=$(head -c32 /dev/urandom | base64)
        SECRET=$(head -c48 /dev/urandom | base64)

        # Build trusted_domains list dynamically (sed-based, no loop)
        ALL_DOMAINS="${NEXTCLOUD_TRUSTED_DOMAINS} localhost ${RAILWAY_PUBLIC_DOMAIN}"
        TRUSTED_DOMAINS_LIST=$(echo "$ALL_DOMAINS" | tr ' ' '\n' | sed "s/^/'/;s/$/', /" | sort -u | tr '\n' ' ' | sed 's/ , $//')

        cat > /var/www/html/config/config.php << 'EOF'
<?php
$CONFIG = array (
  'instanceid' => 'INSTANCEID_PLACEHOLDER',
  'passwordsalt' => 'PASSWORDSALT_PLACEHOLDER',
  'secret' => 'SECRET_PLACEHOLDER',
  'trusted_domains' => 
  array (
    TRUSTED_DOMAINS_PLACEHOLDER
  ),
  'datadirectory' => 'NEXTCLOUD_DATA_DIR_PLACEHOLDER',
  'dbtype' => 'pgsql',
  'version' => '32.0.3.2',
  'dbname' => 'POSTGRES_DB_PLACEHOLDER',
  'dbhost' => 'POSTGRES_HOST_PLACEHOLDER:POSTGRES_PORT_PLACEHOLDER',
  'dbuser' => 'POSTGRES_USER_PLACEHOLDER',
  'dbpassword' => 'POSTGRES_PASSWORD_PLACEHOLDER',
  'installed' => false,
  'theme' => '',
  'loglevel' => 2,
  'maintenance' => false,
  'overwrite.cli.url' => 'https://RAILWAY_PUBLIC_DOMAIN_PLACEHOLDER',
  'overwriteprotocol' => 'https',
  'overwritehost' => 'RAILWAY_PUBLIC_DOMAIN_PLACEHOLDER',
  'trusted_proxies' => 
  array (
    0 => '0.0.0.0/0',
  ),
  'memcache.local' => '\\OC\\Memcache\\Redis',
  'redis' => 
  array (
    'host' => 'REDIS_HOST_PLACEHOLDER',
    'port' => REDIS_PORT_PLACEHOLDER,
    'password' => 'REDIS_PASSWORD_PLACEHOLDER',
    'user' => 'default',
  ),
  'logfile' => '/var/www/html/data/nextcloud.log',
);
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
        sed -i "s|REDIS_HOST_PLACEHOLDER|${REDIS_HOST}|g" /var/www/html/config/config.php
        sed -i "s|REDIS_PORT_PLACEHOLDER|${REDIS_PORT}|g" /var/www/html/config/config.php
        sed -i "s|'password' => 'REDIS_PASSWORD_PLACEHOLDER',|'password' => '${REDIS_PASSWORD}',|g" /var/www/html/config/config.php
        sed -i "s|TRUSTED_DOMAINS_PLACEHOLDER|    0 => ${TRUSTED_DOMAINS_LIST}|g" /var/www/html/config/config.php

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

        # Substitute Redis placeholders
        sed -i "s|REDIS_HOST_PLACEHOLDER|${REDIS_HOST}|g" /var/www/html/config/config.php
        sed -i "s|REDIS_PORT_PLACEHOLDER|${REDIS_PORT}|g" /var/www/html/config/config.php
        sed -i "s|'password' => 'REDIS_PASSWORD_PLACEHOLDER',|'password' => '${REDIS_PASSWORD}',|g" /var/www/html/config/config.php

        chown www-data:www-data /var/www/html/config/config.php
        chmod 640 /var/www/html/config/config.php
        echo "✅ Config.php created with all settings"
else
    echo "✅ No admin credentials - NextCloud setup wizard will be used"
fi

# Placeholder for diagnostics - will be run after installation
echo "=== DIAGNOSTIC LOGGING DEFERRED ==="

echo "=== PRE-RESTORE FILE CHECK ==="

# Pre-restore: Check volume-mounted state
echo "🔍 PRE-RESTORE: Recursive file search (top 50 files):"
find /var/www/html -type f 2>/dev/null | head -50 || echo "find failed"
echo "🔍 PRE-RESTORE: Key Nextcloud files/dirs in /var/www/html:"
ls -la /var/www/html/ 2>/dev/null | grep -E "(occ|index\.php|core|apps|lib|config)" || echo "No key files found"
echo "🔍 PRE-RESTORE: Search for occ anywhere:"
find /var/www/html -name "occ" 2>/dev/null || echo "occ not found anywhere"
echo "🔍 PRE-RESTORE: index.php content preview (if exists):"
if [ -f /var/www/html/index.php ]; then head -20 /var/www/html/index.php; else echo "index.php missing"; fi
echo "=== PRE-RESTORE END ==="

# Restore Nextcloud files if missing due to volume mount
if [ ! -f /var/www/html/occ ]; then
    echo "🔄 Restoring Nextcloud files from /tmp backup..."
    if [ -d /tmp/nextcloud-backup ] && [ "$(ls -A /tmp/nextcloud-backup)" ]; then
        cp -r /tmp/nextcloud-backup/* /var/www/html/ || echo "Copy from backup failed"
        chown -R www-data:www-data /var/www/html
        find /var/www/html -type f -exec chmod 644 {} \; 2>/dev/null || true
        find /var/www/html -type d -exec chmod 755 {} \; 2>/dev/null || true
        echo "✅ Files restored from backup"
    else
        echo "📥 No backup found - downloading Nextcloud 32.0.3..."
        cd /var/www/html
        echo "🔍 Starting curl download..."
        curl -L -o nextcloud.tar.bz2 https://download.nextcloud.com/server/releases/nextcloud-32.0.3.tar.bz2 || echo "Download failed"
        if [ -f nextcloud.tar.bz2 ]; then
            echo "✅ Download succeeded - file size:"
            ls -lh nextcloud.tar.bz2 || echo "ls tar failed"
            echo "🔍 Starting tar extract..."
            tar -xjf nextcloud.tar.bz2 --strip-components=1 || echo "Extract failed - check error above"
            rm nextcloud.tar.bz2
            echo "🔍 Post-extract ls top-level:"
            ls -la /var/www/html/ || echo "ls post-extract failed"
            echo "🔍 Post-extract find occ:"
            find /var/www/html -name "occ" 2>/dev/null || echo "occ not found post-extract"
            chown -R www-data:www-data /var/www/html
            find /var/www/html -type f -exec chmod 644 {} \; 2>/dev/null || true
            find /var/www/html -type d -exec chmod 755 {} \; 2>/dev/null || true
            echo "✅ Files downloaded and extracted"
        else
            echo "❌ Download failed - files cannot be restored"
        fi
    fi
else
    echo "✅ Nextcloud files already present (occ found)"
fi

echo "=== POST-RESTORE FILE CHECK ==="

# Post-restore: Verify files and paths
echo "🔍 POST-RESTORE: Full top-level ls /var/www/html:"
ls -la /var/www/html/ 2>/dev/null || echo "ls post-restore failed"
echo "🔍 POST-RESTORE: Search for occ post-restore:"
find /var/www/html -name "occ" 2>/dev/null || echo "occ still not found"
echo "🔍 POST-RESTORE: occ content preview (if exists):"
if [ -f /var/www/html/occ ]; then head -10 /var/www/html/occ; else echo "occ missing post-restore"; fi
echo "🔍 POST-RESTORE: index.php content preview:"
if [ -f /var/www/html/index.php ]; then head -10 /var/www/html/index.php; else echo "index.php missing"; fi
echo "🔍 POST-RESTORE: Dir structure (top dirs):"
find /var/www/html -type d 2>/dev/null | head -15 || echo "find dirs failed"
echo "🔍 POST-RESTORE: Sizes of key dirs/files:"
du -sh /var/www/html/* 2>/dev/null | head -10 || echo "du failed"
echo "=== POST-RESTORE END ==="

echo "=== EXPECTED FILES CHECK ==="

# Expected Nextcloud files/dirs (from docs)
EXPECTED_FILES=(
    "index.php"
    "occ"
    ".htaccess"
    "version.php"
    "core/"
    "apps/"
    "lib/"
    "config/"
    "themes/"
    "upgrader/"
    "3rdparty/"
    "ocs/"
    "remote.php"
    "status.php"
    "public.php"
    "cron.php"
    "core/img/"
    "apps/files/"
    "lib/private/"
    "config/config.php"
)

for file in "${EXPECTED_FILES[@]}"; do
    if [ -e "/var/www/html/$file" ]; then
        echo "PRESENT: $file"
        ls -la "/var/www/html/$file" 2>/dev/null || echo "ls $file failed"
        if [ -f "/var/www/html/$file" ]; then
            head -5 "/var/www/html/$file" 2>/dev/null || echo "head $file failed"
        fi
        if [ -d "/var/www/html/$file" ]; then
            echo "  Contents (top 5):"
            ls -la "/var/www/html/$file/" 2>/dev/null | head -6 || echo "ls dir failed"
        fi
    else
        echo "MISSING: $file"
    fi
done

echo "=== EXPECTED FILES CHECK END ==="

cd /var/www/html || echo "Failed to cd to /var/www/html"

# Pre-install: Test database connection and check for existing tables
echo "🔍 DIAGNOSTIC: Testing database connection..."
export PGPASSWORD="${POSTGRES_PASSWORD}"
if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -w -c "\conninfo" >/dev/null 2>&1; then
    echo "✅ Database connection successful"
else
    echo "❌ Database connection failed - check credentials and network"
    unset PGPASSWORD
    exit 1
fi

echo "🔍 DIAGNOSTIC: Checking for existing Nextcloud tables..."
TABLE_COUNT=$(psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'oc_%';" 2>/dev/null || echo "0")
if [ "$TABLE_COUNT" -gt 0 ]; then
    echo "✅ Existing tables found ($TABLE_COUNT). Using postgres user directly (no ownership change needed)."
else
    echo "ℹ️ No existing Nextcloud tables found"
fi
unset PGPASSWORD

# Install Nextcloud if not already installed
if [ -f occ ]; then
    echo "⚙️ DIAGNOSTIC: Checking installation status..."
    if ! php occ status 2>/dev/null | grep -q "installed: true"; then
        echo "🚀 DIAGNOSTIC: Nextcloud not installed, proceeding with installation using postgres user..."

        # Install directly with postgres user (no oc_admin creation)
        INSTALL_EXIT=0
        echo "🔍 DIAGNOSTIC: Running maintenance:install with postgres user..."
        php occ maintenance:install --no-interaction \
            --database pgsql \
            --database-host "${POSTGRES_HOST}:${POSTGRES_PORT}" \
            --database-name "${POSTGRES_DB}" \
            --database-user "${POSTGRES_USER}" \
            --database-pass "${POSTGRES_PASSWORD}" \
            --admin-user "${NEXTCLOUD_ADMIN_USER}" \
            --admin-pass "${NEXTCLOUD_ADMIN_PASSWORD}" || INSTALL_EXIT=$?

        if [ $INSTALL_EXIT -ne 0 ]; then
            echo "❌ Installation failed with exit code $INSTALL_EXIT"
            echo "🔍 DIAGNOSTIC: Installation command output above, checking database permissions..."
            export PGPASSWORD="${POSTGRES_PASSWORD}"
            psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -w -c "\l" | grep "${POSTGRES_DB}" || echo "Database list failed"
            psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -w -c "\du ${POSTGRES_USER}" || echo "User privileges check failed"
            unset PGPASSWORD
            exit 1
        fi

        echo "✅ Installation command completed successfully"
        php occ config:system:set installed --value true || echo "⚠️ Could not set installed flag"

        # Verify installation immediately
        echo "🔍 DIAGNOSTIC: Verifying installation..."
        php occ status || echo "⚠️ Post-install status check failed"

        echo "✅ Nextcloud installation completed"
    else
        echo "✅ Nextcloud already installed"
    fi

    # Run security and setup fixes only if installed
    if php occ status 2>/dev/null | grep -q "installed: true"; then
        echo "🔧 DIAGNOSTIC: Nextcloud installed, running fix-warnings script..."
        /usr/local/bin/fix-warnings.sh || echo "⚠️ fix-warnings.sh completed with warnings or errors"
    else
        echo "⚠️ Skipping fix-warnings: Nextcloud not fully installed"
    fi
fi

# Now run deferred diagnostics after installation
echo "🔍 DIAGNOSTIC: Starting comprehensive post-installation diagnostics..."

# Environment and Config Dump (masked)
echo "🔍 FINAL ENV VARS (masked):"
echo "  POSTGRES: host=${POSTGRES_HOST}, port=${POSTGRES_PORT}, user=${POSTGRES_USER}, db=${POSTGRES_DB}"
echo "  REDIS: host=${REDIS_HOST}, port=${REDIS_PORT}"
echo "  TRUSTED_DOMAINS: ${NEXTCLOUD_TRUSTED_DOMAINS:-not set}"
echo "  OVERWRITE: host=${OVERWRITEHOST:-not set}, protocol=${OVERWRITEPROTOCOL:-not set}"
echo "📄 CONFIG.PHP CONTENT (secrets masked):"
cat /var/www/html/config/config.php | sed "s/'dbpassword' => '[^']*'/'dbpassword' => '***'/g" | sed "s/'password' => '[^']*'/'password' => '***'/g" || echo "Config.php cat failed"

# File and Directory Listings
echo "📁 FINAL FILES IN /var/www/html:"
ls -la /var/www/html/ || echo "ls /var/www/html failed"
echo "📁 CONFIG DIR:"
ls -la /var/www/html/config/ || echo "ls config dir failed"
echo "📁 DATA DIR:"
ls -la /var/www/html/data/ 2>/dev/null || echo "Data dir not present or empty"

# Postgres Connection Tests
echo "🗄️ TESTING POSTGRES CONNECTION:"
export PGPASSWORD="${POSTGRES_PASSWORD}"
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -w -c "\conninfo" || echo "Postgres conninfo failed: $?"
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -w -c "SELECT version();" || echo "Postgres version query failed: $?"
echo "📋 POSTGRES TABLES REVIEW:"
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -w -c "\dt" || echo "Postgres list tables failed: $?"
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -w -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" || echo "Postgres table count failed: $?"
unset PGPASSWORD

# Redis Connection Tests
echo "🔴 TESTING REDIS CONNECTION:"
redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" ping || echo "Redis ping failed: $?"
redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" info server | head -10 || echo "Redis info failed: $?"

# Nextcloud OCC Diagnostics
    echo "⚙️ NEXTCLOUD OCC DIAGNOSTICS:"
    cd /var/www/html || echo "cd /var/www/html failed"
    if [ -f /var/www/html/occ ]; then
        echo "✅ OCC file found - running diagnostics:"
        php /var/www/html/occ status || echo "occ status failed: $?"
        php /var/www/html/occ db:add-missing-columns || echo "occ db:add-missing-columns failed: $?"
        php /var/www/html/occ db:add-missing-indices || echo "occ db:add-missing-indices failed: $?"
        php /var/www/html/occ integrity:check-core || echo "occ integrity:check-core failed: $?"
        echo "📋 SYSTEM CONFIG (first 20 lines):"
        php /var/www/html/occ config:list system | head -20 || echo "occ config:list failed: $?"
        echo "🔍 INSTALLED APPS (first 10):"
        php /var/www/html/occ app:list | head -10 || echo "occ app:list failed: $?"
        echo "🔍 BACKGROUND JOBS MODE:"
        php /var/www/html/occ background:cron || echo "occ background:cron failed: $?"
    else
        echo "❌ OCC file not found - Nextcloud files need to be downloaded"
    fi

# Processes, Disk, and Logs
echo "🐛 CURRENT PROCESSES (relevant):"
ps aux | grep -E "(apache|php|supervisord|cron|postgres|redis)" || echo "ps grep failed"
echo "📊 DISK USAGE (root):"
df -h / || echo "df failed"
echo "📊 APACHE LOGS (last 10 lines if exist):"
if [ -f /var/log/apache2/error.log ] && [ -r /var/log/apache2/error.log ]; then
  tail -n 10 /var/log/apache2/error.log 2>/dev/null || echo "Tail failed"
else
  echo "No Apache error log or empty"
fi
echo "📊 APACHE ACCESS LOGS (last 10 if exist):"
if [ -f /var/log/apache2/access.log ] && [ -r /var/log/apache2/access.log ]; then
  tail -n 10 /var/log/apache2/access.log 2>/dev/null || echo "Tail failed"
else
  echo "No Apache access log or empty"
fi
echo "🔍 NEXTCLOUD LOG (last 10 lines if exists):"
if [ -f /var/www/html/data/nextcloud.log ] && [ -r /var/www/html/data/nextcloud.log ]; then
  tail -n 10 /var/www/html/data/nextcloud.log 2>/dev/null || echo "Tail failed"
else
  echo "No nextcloud.log or empty"
fi
echo "🔍 SUPERVISOR LOG (if exists):"
if [ -f /var/log/supervisor/supervisord.log ] && [ -r /var/log/supervisor/supervisord.log ]; then
  tail -n 10 /var/log/supervisor/supervisord.log 2>/dev/null || echo "Tail failed"
else
  echo "No supervisor log or empty"
fi

echo "🔍 DIAGNOSTIC: Comprehensive diagnostics completed"

# Forward to original NextCloud entrypoint
echo "🔧 DIAGNOSTIC: Preparing Apache configuration..."
# Comment out conflicting MPM LoadModule lines in all conf
find /etc/apache2 -name "*.conf" -o -name "*.load" | xargs sed -i '/LoadModule.*mpm_\(event\|worker\)_module/ s/^/#/'
# Remove conflicting MPM files (real or symlink)
rm -f /etc/apache2/mods-enabled/mpm_event.load /etc/apache2/mods-enabled/mpm_event.conf /etc/apache2/mods-enabled/mpm_worker.load /etc/apache2/mods-enabled/mpm_worker.conf
# Link prefork
ln -sf /etc/apache2/mods-available/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.load
ln -sf /etc/apache2/mods-available/mpm_prefork.conf /etc/apache2/mods-enabled/mpm_prefork.conf
apache2ctl configtest || echo "Apache configtest warning - continuing"

echo "🔍 DIAGNOSTIC: Final configuration complete, starting supervisord..."
echo "📊 Command: /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf"
echo "📊 Working directory: $(pwd)"
echo "📊 Environment summary:"
echo "  - PostgreSQL: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
echo "  - Redis: ${REDIS_HOST}:${REDIS_PORT}"
echo "  - Domain: ${RAILWAY_PUBLIC_DOMAIN:-not set}"
echo "  - Port: ${PORT}"

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
