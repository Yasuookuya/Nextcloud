FROM nextcloud:32-apache

RUN apt-get update && apt-get install -y \
  cron supervisor redis-tools \
  postgresql-client procps \
  curl wget smbclient libsmbclient-dev \
  && rm -rf /var/lib/apt/lists/*

# PECL/ext
RUN pecl install smbclient apcu && \
  docker-php-ext-enable smbclient apcu && \
  docker-php-ext-install pgsql pdo_pgsql && \
  echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/apcu.ini

RUN usermod -s /bin/bash www-data

COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh
RUN chmod +x /usr/local/bin/*.sh

# Perms
RUN mkdir -p /var/log/supervisor /var/log/php-fpm /run/php && \
  chown -R www-data /var/www/html /var/log/* /run/php && \
  find /var/www/html -type f -exec chmod 644 {} \; && \
  find /var/www/html -type d -exec chmod 755 {} \;

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["apache2-foreground"]
