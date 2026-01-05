#!/bin/bash
set -e

# FIXED ENV (PG* + POSTGRES*)
export POSTGRES_HOST="${PGHOST:-}"
export POSTGRES_PORT="${PGPORT:-5432}"
export POSTGRES_USER="${PGUSER:-postgres}"
export POSTGRES_PASSWORD="${PGPASSWORD:-}"
export POSTGRES_DB="${PGDATABASE:-railway}"
export REDIS_HOST="${REDIS_HOST:-}"
export REDIS_PORT="${REDIS_PORT:-6379}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"

echo "DB: $POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB ($POSTGRES_USER)"
echo "Redis: $REDIS_HOST:$REDIS_PORT"
echo "1 OK"

# Apache $PORT
echo "Listen $PORT" > /etc/apache2/ports.conf

# FIXED VHOST + FPM PROXY
cat > /etc/apache2/sites-enabled/000-default.conf << EOF
<VirtualHost *:$PORT>
ServerName $RAILWAY_PUBLIC_DOMAIN
DocumentRoot /var/www/html

<Directory /var/www/html>
Options +FollowSymlinks
AllowOverride All
Require all granted
</Directory>

# FPM Proxy
ProxyPassMatch ^/(.*\.php(/.*)?)$ unix:/run/php/php8.3-fpm.sock|fcgi://localhost/var/www/html/\$1
ProxyPassReverse / unix:/run/php/php8.3-fpm.sock|fcgi://localhost/var/www/html/

CustomLog /var/log/apache2/access.log combined
ErrorLog /var/log/apache2/error.log
</VirtualHost>
EOF

# Reload configs
a2enconf apache-mpm security apache-security
# apache2ctl configtest && apache2ctl graceful || echo "Apache reload WARN"
echo "Apache config ready (supervisor starts)"

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
  runuser www-data -c "cd /var/www/html && php occ config:system:set memcache.local --value=\\OCP\\Memcache\\APCu" || true
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
  runuser www-data -c "cd /var/www/html && php occ status --output=json" 2>/dev/null || echo "occ ready but deferred"
else
  echo "Nextcloud status check deferred (first run)"
fi
echo "8.2 Pre-supervisor: FPM socket prep..."
mkdir -p /run/php && chown -R www-data:www-data /run/php /var/log/php-fpm* && chmod 777 /run/php && chown www-data /run/php/php-fpm.* 2>/dev/null || true
echo "8.2 FPM socket ready"

echo "🚀 === 9. POST-INSTALL FIXES ==="
if grep -q "'installed'=>true" /var/www/html/config/config.php; then
  chown -R www-data /var/www/html
  # Merge optimizations if not already included
  if ! grep -q "optimizations.php" /var/www/html/config/config.php; then
    sed -i '/\$CONFIG = array(/a $CONFIG_INCLUDES[] = include("/var/www/html/config/nextcloud-optimizations.php");' /var/www/html/config/config.php
  fi
  # Redis config
  runuser www-data -c "cd /var/www/html && php occ redis:config --host=$REDIS_HOST --port=$REDIS_PORT --password=$REDIS_PASSWORD --dbindex=0" || true
  # Run fix script
  /usr/local/bin/fix-warnings.sh
  # Files scan
  runuser www-data -c "cd /var/www/html && php occ files:scan --all --quiet" || true
  echo "9 ✅ Green!"
fi

echo "8.3 Starting supervisor..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
