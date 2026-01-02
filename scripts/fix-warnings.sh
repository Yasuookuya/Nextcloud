#!/bin/bash
# NextCloud Security & Setup Warnings Fix Script
# Run this after NextCloud is fully installed and configured

set -e

echo "🔧 Fixing NextCloud Security & Setup Warnings..."
echo "⚠️  IMPORTANT: This script should only be run AFTER NextCloud setup is complete!"
echo ""

# Function to run occ commands as www-data user
run_occ() {
    if command -v sudo >/dev/null 2>&1; then
        sudo -u www-data php /var/www/html/occ "$@"
    else
        # In Railway, we might be running as root already
        runuser -u www-data -- php /var/www/html/occ "$@" 2>/dev/null || php /var/www/html/occ "$@"
    fi
}

# Check if NextCloud is installed
echo "🔍 Checking NextCloud installation status..."

# First check if the occ file exists
if [ ! -f "/var/www/html/occ" ]; then
    echo "❌ NextCloud occ command not found!"
    echo "   This usually means NextCloud is still starting up."
    echo "   Please wait for NextCloud to fully start before running this script."
    echo ""
    echo "   You can check if NextCloud is ready by visiting your Railway URL."
    echo "   Once you see the NextCloud interface (setup wizard or login), you can run this script."
    exit 1
fi

# Check if NextCloud is installed
if ! run_occ status 2>/dev/null | grep -q "installed: true"; then
    echo "❌ NextCloud is not yet installed!"
    echo "   Please complete the NextCloud setup first:"
    echo "   1. Visit your Railway URL"
    echo "   2. Complete the setup wizard (create admin account)"
    echo "   3. Then run this script to fix security warnings"
    echo ""
    echo "   Current NextCloud status:"
    run_occ status 2>/dev/null || echo "   (NextCloud not responding)"
    exit 1
fi

echo "✅ NextCloud is ready, proceeding with fixes..."

# Update apps if needed (before DB fixes)
echo "📱 Updating apps if needed..."
run_occ app:update --all --no-interaction || echo "Apps skipped (upgrade state)"

# Fix database issues
echo "🗄️ Adding missing database columns..."
run_occ db:add-missing-columns

echo "📊 Adding missing database indices..."
run_occ db:add-missing-indices

echo "🔑 Adding missing primary keys..."
run_occ db:add-missing-primary-keys

# Fix mimetype migrations
echo "📁 Running mimetype migrations..."
run_occ maintenance:repair --include-expensive

# Update system configurations
echo "⚙️ Updating system configurations..."
run_occ config:system:set maintenance_window_start --value=2 --type=integer
run_occ config:system:set default_phone_region --value="US"

# Enhanced Redis configuration (add password/port, prioritize Redis for local cache)
if [ -n "$REDIS_HOST" ]; then
    echo "🔴 Configuring Redis caching..."
    run_occ config:system:set memcache.local --value="\\OC\\Memcache\\Redis"  # Prioritize Redis over APCu for better perf
    run_occ config:system:set memcache.distributed --value="\\OC\\Memcache\\Redis"
    run_occ config:system:set memcache.locking --value="\\OC\\Memcache\\Redis"
    run_occ config:system:set redis host --value="$REDIS_HOST"
    run_occ config:system:set redis port --value="${REDIS_PORT:-6379}"
    if [ -n "$REDIS_PASSWORD" ]; then
        run_occ config:system:set redis password --value="$REDIS_PASSWORD"
    fi
fi

# Disable update checker for containerized deployments
echo "📦 Configuring for containerized deployment..."
run_occ config:system:set updatechecker --value=false --type=boolean

# Add Railway-specific: Trusted proxies for reverse proxy (Railway's HTTPS)
echo "🌐 Configuring trusted proxies for Railway..."
run_occ config:system:set trusted_proxies 0 --value="127.0.0.1"  # Localhost for internal
run_occ config:system:set trusted_proxies 1 --value="::1"  # IPv6
# Add more if needed (e.g., Railway's internal IPs from docs)

# Run final maintenance
echo "🧹 Running final maintenance..."
run_occ maintenance:mode --off

echo "✅ NextCloud Security & Setup Warnings fixed successfully!"
echo "ℹ️  You may need to refresh your NextCloud admin page to see the changes."
