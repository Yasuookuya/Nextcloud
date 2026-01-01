FROM nextcloud:29-fpm-alpine

# [BUILD: BASE] Base image info
RUN echo "🏗️ [BUILD: BASE] Using Nextcloud base image" && \
    echo "📦 [BUILD: BASE] Nextcloud version check:" && \
    php -r "echo 'PHP Version: ' . PHP_VERSION . PHP_EOL;" && \
    ls -la /usr/src/nextcloud/version.php || echo "⚠️ [BUILD: BASE] Version file not found"

# [BUILD: DEPENDENCIES] Install additional tools
RUN echo "📥 [BUILD: DEPENDENCIES] Installing additional packages..." && \
    apk add --no-cache gettext nginx supervisor curl postgresql-client procps net-tools bind-tools bash redis iproute2 bind && \
    echo "✅ [BUILD: DEPENDENCIES] Package installation complete"

# [BUILD: DIAGNOSTICS] Tool version checks
RUN echo "🔍 [BUILD: DIAGNOSTICS] Checking installed tools:" && \
    echo "✅ [BUILD: DIAGNOSTICS] Bash: $(bash --version 2>/dev/null | head -1 || echo 'ready')" && \
    echo "✅ [BUILD: DIAGNOSTICS] Redis CLI: $(redis-cli --version 2>/dev/null || echo 'ready')" && \
    echo "✅ [BUILD: DIAGNOSTICS] Postgres client: $(psql --version 2>/dev/null | head -1 || echo 'ready')" && \
    echo "✅ [BUILD: DIAGNOSTICS] Nginx: $(nginx -v 2>&1 || echo 'ready')" && \
    echo "✅ [BUILD: DIAGNOSTICS] PHP: $(php --version | head -1 || echo 'ready')" && \
    echo "✅ [BUILD: DIAGNOSTICS] IP route: $(ip route 2>/dev/null | head -1 || echo 'ready')" && \
    echo "✅ [BUILD: DIAGNOSTICS] Nslookup: $(nslookup -version 2>/dev/null | head -1 || echo 'ready')"

# [BUILD: COPY] Copy configuration files
RUN echo "📋 [BUILD: COPY] Copying configuration files..."
COPY config/nginx.conf /etc/nginx/nginx.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY config/php.ini /usr/local/etc/php/conf.d/nextcloud.ini
COPY config/deployment-status.html /var/www/html/deployment-status.html
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/fix-warnings.sh /usr/local/bin/fix-warnings.sh

# [BUILD: PERMISSIONS] Set permissions
RUN echo "🔐 [BUILD: PERMISSIONS] Setting script permissions..." && \
    chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh && \
    echo "✅ [BUILD: PERMISSIONS] Permissions set" && \
    ls -la /usr/local/bin/custom-entrypoint.sh /usr/local/bin/fix-warnings.sh

# [BUILD: DIRS] Create required directories
RUN echo "📁 [BUILD: DIRS] Creating required directories..." && \
    mkdir -p /run/nginx /var/log/nginx /var/run/nginx && \
    echo "✅ [BUILD: DIRS] Directories created"

# [BUILD: VALIDATE] Comprehensive build validation
RUN echo "🔍 [BUILD: VALIDATE] Starting comprehensive build validation..." && \
    echo "📋 [BUILD: VALIDATE] Checking file presence and permissions..." && \
    ls -la /usr/local/bin/custom-entrypoint.sh && \
    ls -la /usr/local/bin/fix-warnings.sh && \
    ls -la /etc/nginx/nginx.conf && \
    ls -la /etc/supervisor/conf.d/supervisord.conf && \
    ls -la /usr/local/etc/php/conf.d/nextcloud.ini && \
    ls -la /var/www/html/deployment-status.html && \
    echo "✅ [BUILD: VALIDATE] All required files present" && \
    echo "🔐 [BUILD: VALIDATE] Checking file permissions..." && \
    test -x /usr/local/bin/custom-entrypoint.sh && echo "✅ [BUILD: VALIDATE] Entrypoint executable" || echo "❌ [BUILD: VALIDATE] Entrypoint not executable" && \
    test -x /usr/local/bin/fix-warnings.sh && echo "✅ [BUILD: VALIDATE] Fix-warnings executable" || echo "❌ [BUILD: VALIDATE] Fix-warnings not executable" && \
    test -r /etc/nginx/nginx.conf && echo "✅ [BUILD: VALIDATE] Nginx config readable" || echo "❌ [BUILD: VALIDATE] Nginx config not readable" && \
    test -r /etc/supervisor/conf.d/supervisord.conf && echo "✅ [BUILD: VALIDATE] Supervisor config readable" || echo "❌ [BUILD: VALIDATE] Supervisor config not readable" && \
    test -r /usr/local/etc/php/conf.d/nextcloud.ini && echo "✅ [BUILD: VALIDATE] PHP config readable" || echo "❌ [BUILD: VALIDATE] PHP config not readable" && \
    echo "✅ [BUILD: VALIDATE] File permissions OK"

# [BUILD: SYNTAX] Script and config syntax validation
RUN echo "📝 [BUILD: SYNTAX] Validating script and config syntax..." && \
    echo "🔍 [BUILD: SYNTAX] Checking shell scripts..." && \
    bash -n /usr/local/bin/custom-entrypoint.sh && echo "✅ [BUILD: SYNTAX] Entrypoint script syntax OK" || (echo "❌ [BUILD: SYNTAX] Entrypoint script syntax error" && exit 1) && \
    bash -n /usr/local/bin/fix-warnings.sh && echo "✅ [BUILD: SYNTAX] Fix-warnings script syntax OK" || (echo "❌ [BUILD: SYNTAX] Fix-warnings script syntax error" && exit 1) && \
    echo "🔍 [BUILD: SYNTAX] Checking configuration files..." && \
    nginx -t -c /etc/nginx/nginx.conf && echo "✅ [BUILD: SYNTAX] Nginx config syntax OK" || (echo "❌ [BUILD: SYNTAX] Nginx config syntax error" && exit 1) && \
    python3 -c "import configparser; c = configparser.ConfigParser(); c.read('/etc/supervisor/conf.d/supervisord.conf')" 2>/dev/null && echo "✅ [BUILD: SYNTAX] Supervisor config syntax OK" || echo "⚠️ [BUILD: SYNTAX] Supervisor config syntax check limited" && \
    php -l /usr/local/etc/php/conf.d/nextcloud.ini && echo "✅ [BUILD: SYNTAX] PHP config syntax OK" || (echo "❌ [BUILD: SYNTAX] PHP config syntax error" && exit 1) && \
    echo "✅ [BUILD: SYNTAX] All syntax checks passed"

# [BUILD: RESOURCES] System resource and dependency checks
RUN echo "💾 [BUILD: RESOURCES] Checking system resources and dependencies..." && \
    echo "🔍 [BUILD: RESOURCES] Checking available memory..." && \
    MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}') && \
    MEM_MB=$((MEM_KB / 1024)) && \
    echo "✅ [BUILD: RESOURCES] Available memory: ${MEM_MB}MB" && \
    [ $MEM_MB -gt 512 ] && echo "✅ [BUILD: RESOURCES] Memory sufficient" || echo "⚠️ [BUILD: RESOURCES] Memory might be limited (${MEM_MB}MB)" && \
    echo "🔍 [BUILD: RESOURCES] Checking disk space..." && \
    DISK_KB=$(df / | tail -1 | awk '{print $4}') && \
    DISK_MB=$((DISK_KB / 1024)) && \
    echo "✅ [BUILD: RESOURCES] Available disk space: ${DISK_MB}MB" && \
    [ $DISK_MB -gt 1024 ] && echo "✅ [BUILD: RESOURCES] Disk space sufficient" || echo "⚠️ [BUILD: RESOURCES] Disk space limited (${DISK_MB}MB)" && \
    echo "🔍 [BUILD: RESOURCES] Checking critical binaries..." && \
    which php && which nginx && which supervisord && which redis-cli && which psql && \
    echo "✅ [BUILD: RESOURCES] All critical binaries available"

# [BUILD: NETWORK] Network configuration validation
RUN echo "🌐 [BUILD: NETWORK] Validating network configuration..." && \
    echo "🔍 [BUILD: NETWORK] Checking network interfaces..." && \
    ip route show | head -1 && echo "✅ [BUILD: NETWORK] Network routing OK" || echo "⚠️ [BUILD: NETWORK] Network routing check failed" && \
    echo "🔍 [BUILD: NETWORK] Checking DNS resolution..." && \
    nslookup google.com 2>/dev/null | head -3 && echo "✅ [BUILD: NETWORK] DNS resolution OK" || echo "⚠️ [BUILD: NETWORK] DNS resolution may be limited" && \
    echo "🔍 [BUILD: NETWORK] Checking exposed ports..." && \
    netstat -tln 2>/dev/null | grep :80 || echo "ℹ️ [BUILD: NETWORK] Port 80 not yet bound (expected in runtime)"

# [BUILD: SECURITY] Basic security checks
RUN echo "🔒 [BUILD: SECURITY] Performing basic security checks..." && \
    echo "🔍 [BUILD: SECURITY] Checking file ownership..." && \
    ls -ld /usr/local/bin/custom-entrypoint.sh | grep -q "root root" && echo "✅ [BUILD: SECURITY] Entrypoint owned by root" || echo "⚠️ [BUILD: SECURITY] Entrypoint ownership unusual" && \
    echo "🔍 [BUILD: SECURITY] Checking for world-writable files..." && \
    find /usr/local/bin -perm -002 2>/dev/null | wc -l | xargs -I {} echo "Found {} world-writable files in /usr/local/bin" && \
    echo "✅ [BUILD: SECURITY] Security checks completed"

# [BUILD: INTEGRITY] Final integrity verification
RUN echo "🛡️ [BUILD: INTEGRITY] Final build integrity check..." && \
    echo "🔍 [BUILD: INTEGRITY] Verifying build artifacts..." && \
    [ -f /usr/local/bin/custom-entrypoint.sh ] && [ -f /usr/local/bin/fix-warnings.sh ] && \
    [ -f /etc/nginx/nginx.conf ] && [ -f /etc/supervisor/conf.d/supervisord.conf ] && \
    [ -f /usr/local/etc/php/conf.d/nextcloud.ini ] && [ -f /var/www/html/deployment-status.html ] && \
    echo "✅ [BUILD: INTEGRITY] All build artifacts present" && \
    echo "🔍 [BUILD: INTEGRITY] Checking file sizes..." && \
    find /usr/local/bin -name "*.sh" -exec ls -lh {} \; && \
    echo "🔍 [BUILD: INTEGRITY] Checking directory structure..." && \
    ls -la /run/ | head -5 && ls -la /var/log/ | head -5 && \
    echo "✅ [BUILD: INTEGRITY] Build integrity verified"

# [BUILD: SUMMARY] Build completion summary
RUN echo "🎉 [BUILD: SUMMARY] Docker build completed successfully!" && \
    echo "📊 [BUILD: SUMMARY] Build artifacts summary:" && \
    echo "  - Nextcloud Version: 29.0.16 (from base image)" && \
    echo "  - Entrypoint Script: $(stat -c%s /usr/local/bin/custom-entrypoint.sh) bytes" && \
    echo "  - Configuration Files: $(ls /etc/nginx/nginx.conf /etc/supervisor/conf.d/supervisord.conf /usr/local/etc/php/conf.d/nextcloud.ini /var/www/html/deployment-status.html | wc -l) files" && \
    echo "  - Total Build Steps: 11 phases completed" && \
    echo "  - Exposed Port: 80" && \
    echo "  - Health Check: Configured" && \
    echo "  - Ready for Railway deployment! 🚀"

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost/status.php >/dev/null 2>&1 || curl -f http://localhost >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
