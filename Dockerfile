FROM nextcloud:latest

# Install additional packages
RUN apt-get update && apt-get install -y \
    smbclient \
    libsmbclient-dev \
    cron \
    supervisor \
    redis-tools \
    postgresql-client \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install smbclient PHP extension and PostgreSQL support
RUN pecl install smbclient \
    && docker-php-ext-enable smbclient \
    && docker-php-ext-install pgsql pdo_pgsql

# Copy PHP configuration
COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini

# Copy Apache configurations
COPY config/security.conf /etc/apache2/conf-available/security.conf
COPY config/apache-security.conf /etc/apache2/conf-available/apache-security.conf

# Enable Apache configs and modules
RUN a2enconf security apache-security && \
    a2enmod rewrite headers env dir mime && \
    a2enmod mpm_prefork

# Copy supervisor config
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy custom entrypoint and fix script
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh
RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh

# Set ownership and permissions
RUN chown -R www-data:www-data /var/www/html && \
    find /var/www/html -type f -exec chmod 644 {} \; && \
    find /var/www/html -type d -exec chmod 755 {} \;

EXPOSE 80

# Use custom entrypoint
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
