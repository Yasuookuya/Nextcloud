#!/bin/bash
set -e

# Railway env (plugins auto-injected)
export PGSSLMODE=disable
export DATABASE_URL="postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$POSTGRES_DB"
export REDIS_PASSWORD="${REDISHOST_PASSWORD:-}"

# Fallback env vars for Railway compatibility
PGHOST="${PGHOST:-${POSTGRES_HOST:-postgres.railway.internal}}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-${POSTGRES_PASSWORD}}"
POSTGRES_DB="${POSTGRES_DB:-railway}"
REDISHOST="${REDISHOST:-${REDIS_HOST:-redis.railway.internal}}"
REDISPORT="${REDISPORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-${REDISHOST_PASSWORD}}"
REDISUSER="${REDISUSER:-default}"

# Validate
if [ -z "$PGHOST" ] || [ -z "$REDISHOST" ]; then
  echo "❌ Missing DB/Redis vars"
  exit 1
fi

echo "✅ Env OK: Postgres=$PGHOST:$PGPORT Redis=$REDISHOST:$REDISPORT"

# Wait DB/Redis
echo "⌛ Waiting DB/Redis..."
if timeout 60 sh -c "until PGPASSWORD=\"$PGPASSWORD\" psql -h \"$PGHOST\" -p \"$PGPORT\" -U \"$PGUSER\" -d postgres -c 'SELECT 1;' >/dev/null 2>&1; do sleep 2; done"; then
  echo "✅ DB ready"
else
  echo "⚠️ DB not ready, continuing anyway"
fi
if timeout 120 sh -c "until redis-cli -h $REDISHOST -p $REDISPORT ${REDIS_PASSWORD:+-a $REDIS_PASSWORD} ping; do sleep 2; done"; then
  echo "✅ Redis ready"
else
  echo "⚠️ Redis not ready, continuing anyway"
fi


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
  echo "✅ NextCloud already installed, checking database configuration"
  # Copy existing config to working location
  cp /var/www/html/data/config.php /var/www/html/config/config.php
  chown www-data:www-data /var/www/html/config/config.php

  # Check if database and Redis configuration matches current environment
  CURRENT_DB_HOST=$(php -r "include '/var/www/html/config/config.php'; echo \$CONFIG['dbhost'] ?? '';")
  CURRENT_DB_USER=$(php -r "include '/var/www/html/config/config.php'; echo \$CONFIG['dbuser'] ?? '';")
  CURRENT_DB_PASS=$(php -r "include '/var/www/html/config/config.php'; echo \$CONFIG['dbpassword'] ?? '';")
  CURRENT_DB_NAME=$(php -r "include '/var/www/html/config/config.php'; echo \$CONFIG['dbname'] ?? '';")
  CURRENT_REDIS_HOST=$(php -r "include '/var/www/html/config/config.php'; echo \$CONFIG['redis']['host'] ?? '';")

  CONFIG_CHANGED=false
  if [ "$CURRENT_DB_HOST" != "$PGHOST:$PGPORT" ]; then
    echo "🔄 Database host changed, updating config..."
    CONFIG_CHANGED=true
  fi
  if [ "$CURRENT_DB_USER" != "$PGUSER" ]; then
    echo "🔄 Database user changed, updating config..."
    CONFIG_CHANGED=true
  fi
  if [ "$CURRENT_DB_PASS" != "$PGPASSWORD" ]; then
    echo "🔄 Database password changed, updating config..."
    CONFIG_CHANGED=true
  fi
  if [ "$CURRENT_DB_NAME" != "$POSTGRES_DB" ]; then
    echo "🔄 Database name changed, updating config..."
    CONFIG_CHANGED=true
  fi
  if [ "$CURRENT_REDIS_HOST" != "$REDISHOST" ]; then
    echo "🔄 Redis host changed, updating config..."
    CONFIG_CHANGED=true
  fi

  if [ "$CONFIG_CHANGED" = true ]; then
    echo "🔧 Updating configuration files directly..."
    # Update both config locations
    CONFIG_FILES=("/var/www/html/config/config.php" "/var/www/html/data/config.php")

    for config_file in "${CONFIG_FILES[@]}"; do
      if [ -f "$config_file" ]; then
        # Update database host
        if [ "$CURRENT_DB_HOST" != "$PGHOST:$PGPORT" ]; then
          sed -i "s|$CURRENT_DB_HOST|$PGHOST:$PGPORT|g" "$config_file"
          echo "✅ Updated database host in $config_file"
        fi

        # Update database user
        if [ "$CURRENT_DB_USER" != "$PGUSER" ]; then
          sed -i "s|'dbuser' => '[^']*'|'dbuser' => '$PGUSER'|g" "$config_file"
          echo "✅ Updated database user in $config_file"
        fi

        # Update database password
        if [ "$CURRENT_DB_PASS" != "$PGPASSWORD" ]; then
          sed -i "s|'dbpassword' => '[^']*'|'dbpassword' => '$PGPASSWORD'|g" "$config_file"
          echo "✅ Updated database password in $config_file"
        fi

        # Update database name
        if [ "$CURRENT_DB_NAME" != "$POSTGRES_DB" ]; then
          sed -i "s|'dbname' => '[^']*'|'dbname' => '$POSTGRES_DB'|g" "$config_file"
          echo "✅ Updated database name in $config_file"
        fi

        # Update Redis host if present
        if [ "$CURRENT_REDIS_HOST" != "$REDISHOST" ]; then
          sed -i "s|'host' => '$CURRENT_REDIS_HOST'|'host' => '$REDISHOST'|g" "$config_file"
          echo "✅ Updated Redis host in $config_file"
        fi
      fi
    done

    echo "✅ Database and Redis configuration updated in all config files"
  else
    echo "✅ Database and Redis configuration is current"
  fi
else
  echo "🏗️ Setting up automatic installation..."
  # Create autoconfig.php for automatic installation
  mkdir -p /var/www/html/config
  cat > /var/www/html/config/autoconfig.php << EOF
<?php
\$AUTOCONFIG = array(
  "dbtype" => "pgsql",
  "dbname" => "$POSTGRES_DB",
  "dbuser" => "$PGUSER",
  "dbpass" => "$PGPASSWORD",
  "dbhost" => "$PGHOST:$PGPORT",
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

# Test DB connection with current config (only for existing installs)
if [ -f "/var/www/html/data/config.php" ]; then
  echo "🔍 Testing DB connection..."
  if ! PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
    echo "❌ DB connection failed. Resetting config for fresh install."
    rm -f /var/www/html/config/config.php /var/www/html/data/config.php
    # Create autoconfig.php for reinstall
    mkdir -p /var/www/html/config
    cat > /var/www/html/config/autoconfig.php << EOF
<?php
\$AUTOCONFIG = array(
  "dbtype" => "pgsql",
  "dbname" => "$POSTGRES_DB",
  "dbuser" => "$PGUSER",
  "dbpass" => "$PGPASSWORD",
  "dbhost" => "$PGHOST:$PGPORT",
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
    echo "✅ Reset autoconfig created for reinstall"
  else
    echo "✅ DB connection OK"
  fi

  # Essentials ONLY (upgrade for existing DBs, no app:update → UI handles)
  su www-data -s /bin/bash -c "
    cd /var/www/html &&
    echo '🔄 Checking for upgrades...' &&
    php console.php maintenance:mode --on &&
    php console.php upgrade --no-interaction || echo '⚠️ Upgrade failed or not needed' &&
    php console.php maintenance:mode --off &&
    php console.php maintenance:mode --off &&
    php console.php config:system:set htaccess.RewriteBase --value=/ &&
    php console.php maintenance:update:htaccess &&
    php console.php config:system:set config_is_read_only --value=true &&
    # Configure Redis if available
    if [ -n \"\$REDISHOST\" ] && [ -n \"\$REDIS_PASSWORD\" ]; then
      echo '🔧 Configuring Redis...' &&
      php console.php config:system:set redis host --value=\"\$REDISHOST\" || true &&
      php console.php config:system:set redis port --value=\"\$REDISPORT\" || true &&
      php console.php config:system:set redis user --value=\"\$REDISUSER\" || true &&
      php console.php config:system:set redis password --value=\"\$REDIS_PASSWORD\" || true &&
      php console.php config:system:set redis timeout --value=0.0 || true &&
      php console.php config:system:set memcache.locking redis || true &&
      echo '✅ Redis configured'
    fi
  "
else
  echo "✅ Fresh install - skipping upgrade commands (installation via web)"
fi

touch /var/www/html/.deployment_complete
chown www-data:www-data /var/www/html/.deployment_complete

echo "🚀 Ready! Login: https://${RAILWAY_PUBLIC_DOMAIN}"
echo "🔍 Status:"
su www-data -s /bin/bash -c "cd /var/www/html && php console.php status"

# Nginx subst + supervisor
envsubst '\${PORT}' < /etc/nginx/nginx.conf > /tmp/nginx.conf && mv /tmp/nginx.conf /etc/nginx/nginx.conf
nginx -t || exit 1

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
