FROM nextcloud:32-apache

RUN apt-get update && apt-get install -y \
  smbclient libsmbclient-dev \
  cron supervisor redis-tools \
  postgresql-client libpq-dev \
  procps lsof net-tools strace \
  curl wget \
  && rm -rf /var/lib/apt/lists/*

# PECL/ext
RUN pecl install smbclient apcu && \
  docker-php-ext-enable smbclient apcu && \
  docker-php-ext-install pgsql pdo_pgsql && \
  echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/apcu.ini

RUN usermod -s /bin/bash www-data

COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy ALL configs
COPY config/apache-mpm.conf /etc/apache2/mods-available/mpm_event.conf
COPY config/apache-security.conf /etc/apache2/conf-enabled/security.conf
COPY config/nextcloud-optimizations.php /var/www/html/config/nextcloud-optimizations.php

COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh
RUN chmod +x /usr/local/bin/*.sh

# Perms + Apache mods
RUN a2enmod rewrite headers ssl proxy_http && \
  mkdir -p /var/log/supervisor /var/log/php-fpm /run/php && \
  chown -R www-data /var/www/html /var/log/* /run/php && \
  find /var/www/html -type f -exec chmod 644 {} \; && \
  find /var/www/html -type d -exec chmod 755 {} \;

EXPOSE ${PORT:-8080}

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
  CMD curl -f http://localhost:${PORT:-8080}/status.php || exit 1

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["apache2-foreground"]
