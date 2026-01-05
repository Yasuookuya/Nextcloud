#!/bin/bash
set -e

# Envs
export POSTGRES_HOST=${POSTGRES_HOST:-$PGHOST:-postgres.railway.internal}
export POSTGRES_PORT=${POSTGRES_PORT:-$PGPORT:-5432}
export POSTGRES_USER=${POSTGRES_USER:-$PGUSER:-postgres}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$PGPASSWORD}
export POSTGRES_DB=${POSTGRES_DB:-$PGDATABASE:-railway}

export PORT=${PORT:-8080}
echo "Listen $PORT" > /etc/apache2/ports.conf

# Vhost minimal
cat > /etc/apache2/sites-enabled/000-default.conf << EOF
<VirtualHost *:$PORT>
ServerName $RAILWAY_PUBLIC_DOMAIN
ServerAlias *
DocumentRoot /var/www/html
<Directory /var/www/html>
Options +FollowSymlinks
AllowOverride All
Require all granted
</Directory>
CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF

a2dismod mpm_event mpm_worker
a2enmod mpm_prefork
apache2ctl configtest

# Autoconfig EXPANDED
if [ -n "$NEXTCLOUD_ADMIN_USER" ] && [ -n "$NEXTCLOUD_ADMIN_PASSWORD" ]; then
  mkdir -p /docker-entrypoint-hooks.d/before-starting
  cat > /docker-entrypoint-hooks.d/before-starting/01-autoconfig.sh << EOF
#!/bin/bash
cat > /var/www/html/config/autoconfig.php << CONFIG
<?php
\$AUTOCONFIG = array(
    "dbtype" => "pgsql",
    "dbname" => "$POSTGRES_DB",
    "dbuser" => "$POSTGRES_USER",
    "dbpass" => "$POSTGRES_PASSWORD",
    "dbhost" => "$POSTGRES_HOST:$POSTGRES_PORT",
    "dbtableprefix" => "oc_",
    "directory" => "/var/www/html/data",
    "adminlogin" => "$NEXTCLOUD_ADMIN_USER",
    "adminpass" => "$NEXTCLOUD_ADMIN_PASSWORD",
    "trusted_domains" => array (
        0 => "$RAILWAY_PUBLIC_DOMAIN",
        1 => "localhost",
    ),
);
CONFIG
chown www-data /var/www/html/config/autoconfig.php
EOF
  chmod +x /docker-entrypoint-hooks.d/before-starting/01-autoconfig.sh
fi

# APCu memcache
su www-data -c "php occ config:system:set memcache.local --value=\\\\OCP\\\\Memcache\\\\APCu"

# Hook permissions
chown -R www-data:www-data /docker-entrypoint-hooks.d 2>/dev/null || true

# Enable additional apache configs
a2enconf apache-security 2>/dev/null || true

exec /entrypoint.sh apache2-foreground
