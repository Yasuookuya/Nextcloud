#!/bin/bash
set -e

# Railway env (plugins auto-injected)
export PGSSLMODE=disable
export DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
export REDIS_PASSWORD="${REDIS_HOST_PASSWORD:-}"

# Validate
if [ -z "$POSTGRES_HOST" ] || [ -z "$REDIS_HOST" ]; then
  echo "❌ Missing DB/Redis vars"
  exit 1
fi

echo "✅ Env OK: Postgres=$POSTGRES_HOST Redis=$REDIS_HOST"

# Wait DB/Redis
echo "⌛ Waiting DB/Redis..."
timeout 60 sh -c "until pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT; do sleep 2; done"
timeout 60 sh -c "until redis-cli -h $REDIS_HOST -p $REDIS_PORT ${REDIS_PASSWORD:+-a $REDIS_PASSWORD} ping; do sleep 2; done"


fix_permissions() {
  mkdir -p /var/www/html/{config,data}
  chown -R www-data:www-data /var/www/html{,/config,/data}
  find /var/www/html/ -type d -exec chmod 750 {} + 2>/dev/null || true
  find /var/www/html/ -type f -exec chmod 640 {} + 2>/dev/null || true
  chmod 770 /var/www/html/data
  echo "✅ Perms fixed"
}

# Check if NextCloud is already installed (config.php exists)
if [ -f "/var/www/html/data/config.php" ]; then
  echo "✅ NextCloud already installed, using existing config"
  # Copy existing config to working location
  cp /var/www/html/data/config.php /var/www/html/config/config.php
  chown www-data:www-data /var/www/html/config/config.php
else
  echo "🏗️ Setting up automatic installation..."
  # Create autoconfig.php for automatic installation
  mkdir -p /var/www/html/config
  cat > /var/www/html/config/autoconfig.php << EOF
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
  "trusted_domains" => array(
    0 => "localhost",
    1 => "${RAILWAY_PUBLIC_DOMAIN:-nextcloud.railway.app}",
    2 => "${RAILWAY_PRIVATE_DOMAIN:-}",
    3 => "${RAILWAY_STATIC_URL:-}",
  ),
);
EOF
  chown www-data:www-data /var/www/html/config/autoconfig.php
  chmod 640 /var/www/html/config/autoconfig.php
  echo "✅ Autoconfig.php created for automatic installation"
fi

fix_permissions

# Essentials ONLY (upgrade for existing DBs, no app:update → UI handles)
su www-data -s /bin/bash -c "
  cd /var/www/html &&
  echo '🔄 Checking for upgrades...' &&
  php occ maintenance:mode --on &&
  php occ upgrade --no-interaction || echo '⚠️ Upgrade failed or not needed' &&
  php occ maintenance:mode --off &&
  php occ maintenance:mode --off &&
  php occ config:system:set htaccess.RewriteBase --value=/ &&
  php occ maintenance:update:htaccess &&
  php occ config:system:set config_is_read_only --value=true
"

touch /var/www/html/.deployment_complete
chown www-data:www-data /var/www/html/.deployment_complete

echo "🚀 Ready! Login: https://${RAILWAY_PUBLIC_DOMAIN}"
echo "🔍 Status:"
su www-data -s /bin/bash -c "cd /var/www/html && php occ status"

# Nginx subst + supervisor
envsubst '\${PORT}' < /etc/nginx/nginx.conf > /tmp/nginx.conf && mv /tmp/nginx.conf /etc/nginx/nginx.conf
nginx -t && php-fpm -t || exit 1

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
