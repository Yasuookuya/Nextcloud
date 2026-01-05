FROM nextcloud:32-apache

# Install additional packages and PHP extensions
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

# Install smbclient PHP extension and ensure PostgreSQL support
RUN pecl install smbclient \
    && docker-php-ext-enable smbclient \
    && docker-php-ext-install pgsql pdo_pgsql

# Copy PHP configuration
COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini

# Copy Apache configurations
COPY config/security.conf /etc/apache2/conf-available/security.conf
COPY config/apache-security.conf /etc/apache2/conf-available/apache-security.conf

# Enable Apache configurations and modules
RUN a2enconf security apache-security && \
    a2enmod rewrite headers env dir mime && \
    # Enable PHP module (version may vary)
    (a2enmod php8.3 || a2enmod php || echo "PHP module detection will be handled in entrypoint") && \
    # Fix MPM conflict - force prefork for mod_php
    rm -f /etc/apache2/mods-enabled/mpm_event.load /etc/apache2/mods-enabled/mpm_worker.load && \
    a2dismod mpm_event mpm_worker || true && \
    a2enmod mpm_prefork && \
    # Comment out conflicting MPM LoadModule lines in all conf
    find /etc/apache2 -name "*.conf" -o -name "*.load" | xargs sed -i '/LoadModule.*mpm_(event|worker)_module/ s/^/#/'

# Copy supervisor configuration
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy custom entrypoint and maintenance scripts
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh
RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh

# Create necessary directories and set permissions
RUN mkdir -p /var/log/supervisor && \
    # Ensure NextCloud files are present and accessible
    ls -la /var/www/html/ && \
    # Set proper ownership and permissions
    chown -R www-data:www-data /var/www/html && \
    find /var/www/html -type f -exec chmod 644 {} \; && \
    find /var/www/html -type d -exec chmod 755 {} \; && \
    chmod +x /usr/local/bin/custom-entrypoint.sh

# Expose HTTP port (Railway expects PORT=80)
EXPOSE 80

# Use custom entrypoint (handles everything including starting supervisord)
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["apache2-foreground"]
