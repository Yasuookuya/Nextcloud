FROM nextcloud:32-fpm

RUN apt-get update && apt-get install -y \
    apache2 \
    smbclient libsmbclient-dev \
    cron supervisor redis-tools \
    postgresql-client libpq-dev \
    procps lsof net-tools strace \
    curl wget \
    && rm -rf /var/lib/apt/lists/*

RUN pecl install smbclient apcu && \
    docker-php-ext-enable smbclient apcu && \
    docker-php-ext-install pgsql pdo_pgsql && \
    echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/apcu.ini

RUN usermod -s /bin/bash www-data && \
    a2dismod mpm_prefork && \
    a2enmod mpm_event proxy proxy_fcgi rewrite headers env dir mime setenvif && \
    echo "=== FPM + Apache Proxy Ready ==="

COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini
COPY config/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf
COPY config/security.conf /etc/apache2/conf-available/
COPY config/apache-security.conf /etc/apache2/conf-available/
COPY config/apache-mpm.conf /etc/apache2/conf-available/

COPY config/nextcloud-optimizations.php /var/www/html/config/
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh
RUN chmod +x /usr/local/bin/*.sh

RUN mkdir -p /var/log/supervisor /var/log/php-fpm /run/php && \
    chown -R www-data:www-data /var/www/html /var/log/supervisor /var/log/php-fpm /run/php && \
    find /var/www/html -type f -exec chmod 644 {} \; -o -type d -exec chmod 755 {} \;

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:${PORT:-80}/status.php || exit 1

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
