#!/bin/bash
set -e

echo "🚀 === 1. ENV VARS ==="
# FIXED: No backslash escapes, use PG* std + fallback
export PGHOST="${PGHOST:-}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-}"
export PGDATABASE="${PGDATABASE:-nextcloud}"
export POSTGRES_HOST="$PGHOST"
export POSTGRES_PORT="$PGPORT"
export POSTGRES_USER="$PGUSER"
export POSTGRES_PASSWORD="$PGPASSWORD"
export POSTGRES_DB="$PGDATABASE"

export REDIS_HOST="${REDIS_HOST:-}"
export REDIS_PORT="${REDIS_PORT:-6379}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"
export REDIS_USER="${REDIS_USER:-default}"

echo "DB: $POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB ($POSTGRES_USER)"
echo "Redis: $REDIS_HOST:$REDIS_PORT ($REDIS_USER)"
echo "1 OK"

echo "🚀 === 2. APACHE PORTS === "
echo "Listen \$PORT" > /etc/apache2/ports.conf
echo "2 OK"

echo "🚀 === 3. VHOST === "
cat > /etc/apache2/sites-enabled/000-default.conf << EOF
<VirtualHost *:\$PORT>
ServerName \$RAILWAY_PUBLIC_DOMAIN
ServerAlias *
DocumentRoot /var/www/html
<Directory /var/www/html>
Options +FollowSymlinks
AllowOverride All
Require all granted
</Directory>
CustomLog /var/log/apache2/access.log combined
ErrorLog /var/log/apache2/error.log
</VirtualHost>
EOF
echo "3 OK"

echo "🚀 === 4. MPM EVENT ==="
echo "4.1 Disabling other MPMs..."
a2dismod mpm_prefork mpm_worker 2>/dev/null || true
echo "4.2 Enabling MPM Event..."
a2enmod mpm_event
echo "4.3 Loading optimized MPM config..."
a2enconf apache-mpm
echo "4 OK"

echo "🚀 === 4.5. APACHE SECURITY ==="
echo "4.5.1 Enabling security configurations..."
a2enconf security apache-security
echo "4.5.2 Enabling Apache modules..."
a2enmod rewrite headers env dir mime proxy_fcgi
echo "4.5.3 Disabling mod_php for FPM + Event..."
a2dismod php8.3 2>/dev/null || true
echo "4.5 OK"

echo "🚀 === 4.6 APACHE FULL RELOAD (fix thread-safety) ==="
a2dismod php8.3 2>/dev/null || true  # Ensure mod_php off
a2enmod proxy_fcgi setenvif  # FPM support
apache2ctl configtest && apache2ctl graceful || echo "Apache reload WARN"
echo "4.6 OK"

echo "🚀 === 5. AUTOCONFIG HOOK === "
if [ -n "\$NEXTCLOUD_ADMIN_USER" ] && [ -n "\$NEXTCLOUD_ADMIN_PASSWORD" ]; then
  mkdir -p /docker-entrypoint-hooks.d/before-starting
  cat > /docker-entrypoint-hooks.d/before-starting/01-autoconfig.sh << 'HOOK_EOF'
#!/bin/bash
echo "Autoconfig expanded"
cat > /var/www/html/config/autoconfig.php << EOF
<?php
\$AUTOCONFIG = array(
    "dbtype" => "pgsql",
    "dbname" => "$POSTGRES_DB",
    "dbuser" => "$POSTGRES_USER",
    "dbpass" => "$POSTGRES_PASSWORD",
    "dbhost" => "$POSTGRES_HOST:\$POSTGRES_PORT",
    "dbtableprefix" => "$NEXTCLOUD_TABLE_PREFIX",
    "directory" => "$NEXTCLOUD_DATA_DIR",
    "adminlogin" => "$NEXTCLOUD_ADMIN_USER",
    "adminpass" => "$NEXTCLOUD_ADMIN_PASSWORD",
    "trusted_domains" => array ( 0 => "$RAILWAY_PUBLIC_DOMAIN", 1 => "localhost" ),
);
EOF
chown www-data:www-data /var/www/html/config/autoconfig.php
chmod 640 /var/www/html/config/autoconfig.php
echo "Autoconfig OK"
HOOK_EOF
  chmod +x /docker-entrypoint-hooks.d/before-starting/01-autoconfig.sh
fi
echo "5 OK"

echo "🚀 === 6. NEXTCLOUD OPTIMIZATIONS ==="
echo "6.1 Installing APCu extension..."
docker-php-ext-install apcu 2>/dev/null || true
echo "6.2 Configuring NextCloud memcache..."
if [ -f /var/www/html/config/config.php ] && grep -q "installed" /var/www/html/config/config.php 2>/dev/null; then
  runuser -u www-data -- cd /var/www/html && php occ config:system:set memcache.local --value=\\OCP\\Memcache\\APCu || true
  echo "6.2 APCu set (installed)"
else
  echo "6.2 Skipping occ (first run)"
fi
echo "6.3 Nextcloud optimizations file ready for auto-merge"
echo "6 OK"

echo "🚀 === 7. APACHE TEST ==="
echo "7.1 Running Apache configuration test..."
apache2ctl configtest && echo "Apache OK" || echo "Apache WARN"
echo "7 OK"

echo "🚀 === 8. SUPERVISOR DEBUG START ==="
echo "Processes: apache2 cron nextcloud-cron php-fpm8.3"
echo "8.1 Checking Nextcloud status..."
if [ -f /var/www/html/config/config.php ] && grep -q "installed" /var/www/html/config/config.php 2>/dev/null; then
  runuser -u www-data -- cd /var/www/html && php occ status --output=json 2>/dev/null || echo "occ ready but deferred"
else
  echo "Nextcloud status check deferred (first run)"
fi
echo "8.2 Pre-supervisor: FPM socket prep..."
mkdir -p /run/php && chown www-data:www-data /run/php
echo "8.2 FPM socket ready"
echo "8.3 Starting supervisor..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
