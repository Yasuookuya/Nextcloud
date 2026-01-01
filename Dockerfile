FROM nextcloud:29-fpm-alpine

# Tools for diagnostics
RUN apk add --no-cache gettext nginx supervisor curl postgresql-client procps net-tools bind-tools

# Copy configs/scripts
COPY config/nginx.conf /etc/nginx/nginx.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh

RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh

# Dirs
RUN mkdir -p /run/nginx /var/log/nginx /var/run/nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost/status.php || exit 1

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
