#!/bin/bash
set -e

echo "🚀 === 1. ENV VARS ==="
echo "1.1 Setting PostgreSQL environment variables..."
export POSTGRES_HOST=\${POSTGRES_HOST:-\$PGHOST}
export POSTGRES_PORT=\${POSTGRES_PORT:-\$PGPORT:-5432}
export POSTGRES_USER=\${POSTGRES_USER:-\$PGUSER:-postgres}
export POSTGRES_PASSWORD=\${POSTGRES_PASSWORD:-\$PGPASSWORD}
export POSTGRES_DB=\${POSTGRES_DB:-\$PGDATABASE:-railway}
echo "1.2 Setting Redis environment variables..."
export REDIS_HOST=\${REDIS_HOST:-\$REDISHOST}
export REDIS_PORT=\${REDIS_PORT:-\$REDISPORT:-6379}
export REDIS_PASSWORD=\${REDIS_PASSWORD:-\$REDISPASSWORD}
export REDIS_USER=\${REDIS_USER:-\$REDISUSER:-default}
echo "DB: \$POSTGRES_HOST:\$POSTGRES_PORT/\$POSTGRES_DB (\$POSTGRES_USER)"
echo "Redis: \$REDIS_HOST:\$REDIS_PORT (\$REDIS_USER)"
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
echo "4.5.3 Starting PHP-FPM..."
mkdir -p /run/php
php-fpm8.3 -D
echo "4.5 OK"

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
su www-data -c "cd /var/www/html && php occ config:system:set memcache.local --value=\\\\OCP\\\\Memcache\\\\APCu || true"
echo "6.3 Applying Nextcloud performance optimizations..."
if [ -f /var/www/html/config/nextcloud-optimizations.php ]; then
    echo "6.4 Nextcloud optimizations applied"
fi
echo "6 OK"

echo "🚀 === 7. APACHE TEST ==="
echo "7.1 Running Apache configuration test..."
apache2ctl configtest && echo "Apache OK" || echo "Apache WARN"
echo "7 OK"

echo "🚀 EXEC ORIGINAL"
exec /entrypoint.sh apache2-foreground
