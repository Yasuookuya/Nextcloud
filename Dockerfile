FROM nextcloud:32-apache

RUN echo "=== APT PKGS ===" && apt-get update && apt-get install -y \
    smbclient libsmbclient-dev \
    cron supervisor redis-tools \
    postgresql-client libpq-dev \
    procps lsof net-tools strace \
    curl \
    && rm -rf /var/lib/apt/lists/* && echo "APT OK"

RUN echo "=== PHP EXT ===" && \
    pecl install smbclient apcu && \
    docker-php-ext-enable smbclient apcu && \
    docker-php-ext-install pgsql pdo_pgsql && \
    echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/apcu.ini && \
    echo "PHP EXT OK"

COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini && echo "PHP INI OK"

COPY config/security.conf /etc/apache2/conf-available/security.conf
COPY config/apache-security.conf /etc/apache2/conf-available/apache-security.conf

RUN echo "=== APACHE CONF ===" && \
    a2enconf security apache-security && \
    a2enmod rewrite headers env dir mime php8.3 || a2enmod php && \
    echo "APACHE CONF OK"

COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf && echo "SUPERVISOR OK"

COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh
RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh && echo "SCRIPTS OK"

RUN echo "=== PERMS ===" && \
    mkdir -p /var/log/supervisor && \
    chown -R www-data:www-data /var/www/html && \
    find /var/www/html -type f -exec chmod 644 {} \; && \
    find /var/www/html -type d -exec chmod 755 {} \; && \
    echo "PERMS OK"

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["apache2-foreground"]
