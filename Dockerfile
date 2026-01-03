FROM nextcloud:latest

# Force Railway to rebuild and use updated entrypoint.sh without MPM conflicts
RUN echo "Cache bust - updated entrypoint.sh" > /tmp/cache-bust

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

# Install PHP extensions 
RUN pecl install smbclient \
    && docker-php-ext-enable smbclient \
    && docker-php-ext-install pgsql pdo_pgsql

# Copy PHP configuration
COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini

# Copy Apache configurations
COPY config/security.conf /etc/apache2/conf-available/security.conf
COPY config/apache-security.conf /etc/apache2/conf-available/apache-security.conf

# Enable Apache configurations and modules
RUN a2enconf security apache-security \
    && a2dismod mpm_worker mpm_prefork || true \
    && a2enmod mpm_event \
    && a2enmod rewrite headers env dir mime \
    && (a2enmod php8.3 || a2enmod php || echo "PHP module detection handled in entrypoint")

# Copy supervisor configuration
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy custom entrypoint and maintenance scripts
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh
RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh

# Set ownership and permissions
RUN chown -R www-data:www-data /var/www/html \
    && find /var/www/html -type f -exec chmod 644 {} \; \
    && find /var/www/html -type d -exec chmod 755 {} \;

# Expose HTTP port (Railway expects PORT=80)
EXPOSE 80

# Use custom entrypoint
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["apache2-foreground"]
