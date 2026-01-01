FROM nextcloud:fpm-alpine

# Install tools
RUN apk add --no-cache gettext nginx supervisor curl postgresql-client

# Copy configs
COPY config/nginx.conf /etc/nginx/http.d/default.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh

RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh

# Create dirs
RUN mkdir -p /var/run/nginx /var/log/nginx /run/nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost/ || exit 1

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
