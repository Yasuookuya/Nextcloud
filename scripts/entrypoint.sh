#!/bin/bash
set -e

# Railway env (plugins auto-injected)
export PGSSLMODE=disable
export DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

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

# Install IF NEEDED (simple: no tables)
if ! psql "$DATABASE_URL" -lqt | cut -d \| -f 1 | grep -qw oc_; then
  echo "🏗️ Fresh install..."
  su www-data -s /bin/bash -c "
    cd /var/www/html &&
    php occ maintenance:install \
      --database 'pgsql' --database-host '$POSTGRES_HOST' --database-port '$POSTGRES_PORT' \
      --database-name '$POSTGRES_DB' --database-user '$POSTGRES_USER' --database-pass '$POSTGRES_PASSWORD' \
      --admin-user '$NEXTCLOUD_ADMIN_USER' --admin-pass '$NEXTCLOUD_ADMIN_PASSWORD' \
      --data-dir '/var/www/html/data'
  "
  echo "✅ Installed"
  # After install, copy config to persistent location
  cp /var/www/html/config/config.php /var/www/html/data/config.php
  chown www-data:www-data /var/www/html/data/config.php
else
  echo "✅ Install skipped (existing DB)"
  # For existing DB, create config if missing
  CONFIG_FILE="/var/www/html/data/config.php"
  if [ ! -f "$CONFIG_FILE" ]; then
    export INSTANCEID="oc$(openssl rand -hex 10)"
    export PASSWORDSALT="$(openssl rand -base64 30)"
    export SECRET="$(openssl rand -base64 30)"
  else
    # Preserve
    INSTANCEID=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['instanceid'] ?? 'oc$(openssl rand -hex 10)';")
    PASSWORDSALT=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['passwordsalt'] ?? '$(openssl rand -base64 30)';")
    SECRET=$(php -r "include '$CONFIG_FILE'; echo \$CONFIG['secret'] ?? '$(openssl rand -base64 30)';")
  fi
  export INSTANCEID PASSWORDSALT SECRET

  cat > /var/www/html/config/config.php << EOF
<?php
\$CONFIG = array (
  'dbtype' => 'pgsql',
  'dbhost' => '$POSTGRES_HOST',
  'dbport' => '$POSTGRES_PORT',
  'dbtableprefix' => 'oc_',
  'dbname' => '$POSTGRES_DB',
  'dbuser' => '$POSTGRES_USER',
  'dbpassword' => '$POSTGRES_PASSWORD',
  'installed' => true,
  'instanceid' => '$INSTANCEID',
  'passwordsalt' => '$PASSWORDSALT',
  'secret' => '$SECRET',
  'trusted_domains' => array (
    0 => '${RAILWAY_PUBLIC_DOMAIN:-nextcloud.railway.app}',
    1 => 'localhost', 2 => '::1',
    3 => '${RAILWAY_PRIVATE_DOMAIN:-}',
    4 => '${RAILWAY_STATIC_URL:-}',
  ),
  'datadirectory' => '/var/www/html/data',
  'overwrite.cli.url' => 'https://${RAILWAY_PUBLIC_DOMAIN:-nextcloud.railway.app}',
  'overwriteprotocol' => 'https',
  'htaccess.RewriteBase' => '/',
  'memcache.local' => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'redis' => array (
    'host' => '$REDIS_HOST', 'port' => '$REDIS_PORT',
    'password' => '${REDIS_PASSWORD:-}',
  ),
  'config_is_read_only' => true,
);
EOF

  # Lint & persist
  php -l /var/www/html/config/config.php || { echo "❌ Config lint fail"; cat /var/www/html/config/config.php; exit 1; }
  cp /var/www/html/config/config.php "$CONFIG_FILE"
  chown www-data:www-data /var/www/html/config/config.php "$CONFIG_FILE"
fi

fix_permissions

# Essentials ONLY (no upgrade/app:update → UI handles)
su www-data -s /bin/bash -c "
  cd /var/www/html &&
  php occ maintenance:mode --off &&
  php occ config:system:set config_is_read_only --value=true &&
  php occ config:system:set htaccess.RewriteBase --value=/ &&
  php occ maintenance:update:htaccess
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
