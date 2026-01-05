FROM nextcloud:32-apache

RUN echo "=== BUILD: APT UPDATE ===" && apt-get update && \
    echo "=== BUILD: APT INSTALL ===" && apt-get install -y \
    smbclient libsmbclient-dev \
    cron supervisor redis-tools \
    postgresql-client libpq-dev \
    procps lsof net-tools strace \
    curl \
    && echo "=== BUILD: APT CLEANUP ===" && rm -rf /var/lib/apt/lists/* && echo "=== BUILD: APT PACKAGES INSTALLED ==="

RUN echo "=== BUILD: PECL INSTALL ===" && \
    pecl install smbclient apcu && \
    echo "=== BUILD: PHP EXT ENABLE ===" && \
    docker-php-ext-enable smbclient apcu && \
    echo "=== BUILD: PHP PGSQL EXT ===" && \
    docker-php-ext-install pgsql pdo_pgsql && \
    echo "=== BUILD: APCU CONFIG ===" && \
    echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/apcu.ini && \
    echo "=== BUILD: PHP EXTENSIONS COMPLETED ==="

COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini

COPY config/security.conf /etc/apache2/conf-available/security.conf
COPY config/apache-security.conf /etc/apache2/conf-available/apache-security.conf

RUN echo "=== APACHE CONF COPIED ==="

COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh
RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh && echo "SCRIPTS OK"

RUN echo "=== BUILD: CREATE LOG DIR ===" && \
    mkdir -p /var/log/supervisor && \
    echo "=== BUILD: SET OWNERSHIP ===" && \
    chown -R www-data:www-data /var/www/html && \
    echo "=== BUILD: SET FILE PERMS ===" && \
    find /var/www/html -type f -exec chmod 644 {} \; && \
    echo "=== BUILD: SET DIR PERMS ===" && \
    find /var/www/html -type d -exec chmod 755 {} \; && \
    echo "=== BUILD: PERMISSIONS SET ==="

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["apache2-foreground"]
