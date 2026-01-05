FROM nextcloud:32-apache

RUN apt-get update && apt-get install -y \
    smbclient libsmbclient-dev \
    cron \
    procps lsof net-tools \
    postgresql-client libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pecl install smbclient apcu && \
    docker-php-ext-enable smbclient apcu && \
    docker-php-ext-install pgsql pdo_pgsql && \
    echo "apc.enable_cli=1" >> /usr/local/etc/php/conf.d/apcu.ini

COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini
COPY config/security.conf /etc/apache2/conf-available/security.conf
COPY config/apache-security.conf /etc/apache2/conf-available/apache-security.conf
RUN a2enconf security apache-security && a2enmod rewrite headers env dir mime php8.3 || a2enmod php

COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
RUN chmod +x /usr/local/bin/custom-entrypoint.sh

RUN chown -R www-data:www-data /var/www/html && find /var/www/html -type f -exec chmod 644 {} \; && find /var/www/html -type d -exec chmod 755 {} \;

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["apache2-foreground"]
