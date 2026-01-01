FROM nextcloud:29-fpm

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
    nginx \
    && rm -rf /var/lib/apt/lists/*

# Install smbclient PHP extension and ensure PostgreSQL support
RUN pecl install smbclient \
    && docker-php-ext-enable smbclient \
    && docker-php-ext-install pgsql pdo_pgsql

# Copy PHP configuration
COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini

# Copy Nginx configuration (new: we'll create this)
COPY config/nginx.conf /etc/nginx/sites-available/default

# Copy supervisor configuration (adapted for Nginx)
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy custom entrypoint and maintenance scripts
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh
RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh

# Create necessary directories and set permissions
RUN mkdir -p /var/log/supervisor /var/run/nginx && \
    chown -R www-data:www-data /var/www/html && \
    find /var/www/html -type f -exec chmod 644 {} \; && \
    find /var/www/html -type d -exec chmod 755 {} \;

# Healthcheck for Railway (checks if Nextcloud is responsive)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/status.php || exit 1

# Expose HTTP port
EXPOSE 80

# Use custom entrypoint
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
