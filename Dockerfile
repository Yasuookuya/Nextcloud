FROM nextcloud:fpm

RUN apt-get update && apt-get install -y gettext-base nginx supervisor curl postgresql-client procps net-tools bind9-utils bash redis-tools iproute2 php8.3-fpm php8.3-pgsql php8.3-redis php8.3-gd php8.3-curl php8.3-zip php8.3-xml php8.3-mbstring php8.3-intl && \
    apt-get clean && \
    ln -sf /usr/sbin/php-fpm8.3 /usr/bin/php-fpm

COPY config/nginx.conf /etc/nginx/nginx.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh

RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh && \
    mkdir -p /run/nginx /var/log/nginx /var/run/nginx

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
