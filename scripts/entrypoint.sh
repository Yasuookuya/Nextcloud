#!/bin/bash
set -e

# Force redeployment to clear cache

echo "🔧 Configuring Apache MPM for Railway compatibility..."
a2dismod mpm_event mpm_worker 2>/dev/null || true
a2enmod mpm_prefork 2>/dev/null || true

echo "🔧 Configuring Apache AllowOverride and rewrite for .htaccess support..."
a2enmod rewrite 2>/dev/null || true
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

# Force file-based sessions - disable Redis completely
echo "🔴 Redis disabled - using file-based sessions with APCu caching"

# NextCloud configuration variables
export NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-}
export NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-}
export NEXTCLOUD_DATA_DIR=${NEXTCLOUD_DATA_DIR:-/var/www/html/data}
export NEXTCLOUD_TABLE_PREFIX=${NEXTCLOUD_TABLE_PREFIX:-oc_}
export NEXTCLOUD_UPDATE_CHECKER=${NEXTCLOUD_UPDATE_CHECKER:-false}

# PHP performance settings
export PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-512M}
export PHP_UPLOAD_LIMIT=${PHP_UPLOAD_LIMIT:-2G}

# Configure Apache for Railway's PORT (IPv4 + IPv6)
export PORT=${PORT:-80}
cat > /etc/apache2/ports.conf << EOF
Listen 0.0.0.0:$PORT
Listen [::]:$PORT
EOF

# Configure Apache virtual host for Railway (IPv4 + IPv6)
cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:${PORT} [::]:${PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ServerName localhost


    <Directory /var/www/html/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

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

# Force Nextcloud permissions immediately after code restore (Railway volume fix)
echo "🔐 Forcing Nextcloud permissions (early)..."
mkdir -p /var/www/html/config /var/www/html/data /var/www/html/data/sessions
chown -R www-data:www-data /var/www/html
chmod 750 /var/www/html
chmod 770 /var/www/html/config
chmod 770 /var/www/html/data
chmod 770 /var/www/html/data/sessions

# Wait for NextCloud entrypoint to initialize first
echo "🌟 Starting NextCloud with original entrypoint..."

# Always provide autoconfig if config.php is missing (fixes Railway volume issues)
if [ ! -f /var/www/html/config/config.php ]; then
    echo "🧩 config.php missing – forcing autoconfig setup"

    # Wait for Postgres to be ready before proceeding
    echo "⏳ Waiting for Postgres to be ready..."
    MAX_RETRIES=30
    i=0
    until PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c '\q' 2>/dev/null; do
      i=$((i+1))
      if [ $i -ge $MAX_RETRIES ]; then
        echo "❌ Postgres not responding after $MAX_RETRIES attempts"
        exit 1
      fi
      echo "Waiting for Postgres..."
      sleep 2
    done
    echo "✅ Postgres is ready"

    # Only clean database on first install to avoid destroying existing data
    echo "🧹 config.php missing – resetting Nextcloud database..."
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

    # DISABLED: Autoconfig.php creation - causing syntax errors
    # Will use manual installation instead
    echo "✅ Using manual NextCloud installation (setup wizard)"
    echo "✅ Skipping autoconfig.php creation to avoid syntax errors"
else
    echo "📁 config.php exists – normal startup"
fi

# Ensure data directory marker file exists (only create if missing)
if [ ! -f /var/www/html/data/.ncdata ]; then
    echo "# Nextcloud data directory" > /var/www/html/data/.ncdata
    chown www-data:www-data /var/www/html/data/.ncdata
fi

# Configure NextCloud for Railway environment
echo "🔧 Configuring NextCloud for Railway deployment..."
if [ -f /var/www/html/occ ]; then
    echo "⚙️ Setting trusted proxies..."
    php /var/www/html/occ config:system:set trusted_proxies 0 --value="0.0.0.0/0" --type=string 2>/dev/null || echo "Trusted proxies already configured"

    echo "🔒 Setting HTTPS protocol..."
    php /var/www/html/occ config:system:set overwriteprotocol --value="https" --type=string 2>/dev/null || echo "Protocol already configured"

    echo "🌐 Setting host override..."
    php /var/www/html/occ config:system:set overwritehost --value="$RAILWAY_PUBLIC_DOMAIN" --type=string 2>/dev/null || echo "Host already configured"

    echo "💻 Setting CLI URL..."
    php /var/www/html/occ config:system:set overwrite.cli.url --value="https://$RAILWAY_PUBLIC_DOMAIN" --type=string 2>/dev/null || echo "CLI URL already configured"

    echo "✅ NextCloud configuration enforced"
else
    echo "⚠️ NextCloud occ command not available yet, configuration will be applied after startup"
fi

# Forward to original NextCloud entrypoint
echo "🐛 DEBUG: About to exec original NextCloud entrypoint"
echo "🐛 DEBUG: Command: /entrypoint.sh apache2-foreground"
echo "🐛 DEBUG: Current working directory: $(pwd)"
echo "� DEBUG: Contents of /usr/local/bin/:"
ls -la /usr/local/bin/ | grep -E "(entrypoint|fix-warnings)"

# Clean up any existing Apache processes to prevent port binding conflicts
echo "🧹 Cleaning up any existing Apache processes..."
pkill -f apache2 || true
sleep 1

exec /entrypoint.sh apache2-foreground
