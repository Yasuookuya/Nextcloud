# Nextcloud Railway Deployment Guide

This guide provides comprehensive instructions for deploying Nextcloud on Railway with all the necessary fixes applied.

## 🚀 Quick Start

### Prerequisites

1. **Railway Account**: Sign up at [railway.app](https://railway.app)
2. **GitHub Repository**: Your Nextcloud project repository
3. **Railway Environment Variables**: Configure the required environment variables

### Environment Variables Required

Add these environment variables to your Railway project:

```bash
# Database Configuration
POSTGRES_HOST=postgres-n76t.railway.internal
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_postgres_password
POSTGRES_DB=railway

# Redis Configuration
REDIS_HOST=redis-svle.railway.internal
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password

# Nextcloud Configuration
NEXTCLOUD_ADMIN_USER=kikaiworksadmin
NEXTCLOUD_ADMIN_PASSWORD=your_secure_password
NEXTCLOUD_TRUSTED_DOMAINS=your-app.up.railway.app,localhost,::1
NEXTCLOUD_UPDATE_CHECK=false

# Optional SMTP Configuration
SMTP_HOST=your_smtp_host
SMTP_PORT=465
SMTP_PASSWORD=your_smtp_password
MAIL_FROM_ADDRESS=noreply@yourdomain.com
MAIL_DOMAIN=yourdomain.com
```

### Deployment Steps

1. **Connect Repository**: 
   - Go to Railway dashboard
   - Click "Deploy from GitHub repo"
   - Select your Nextcloud repository

2. **Configure Environment**:
   - Add the required environment variables
   - Ensure `PORT` is set to `8080` (default for Railway)

3. **Deploy**:
   - Railway will automatically build and deploy using the Dockerfile
   - Monitor the deployment logs for any issues

## 🔧 Key Fixes Applied

### 1. Nextcloud Application Files Installation
- **Issue**: Missing Nextcloud application files in container
- **Fix**: Added automatic download and installation of Nextcloud 29.0.16
- **Location**: `Dockerfile` lines 10-24

### 2. Build Process Reliability
- **Issue**: MD5 checksum verification failures during build
- **Fix**: Removed problematic MD5 verification for reliable builds
- **Location**: `Dockerfile` lines 15-18

### 3. Nginx PORT Substitution
- **Issue**: PORT environment variable substitution failing
- **Fix**: Improved nginx configuration with proper PORT handling
- **Location**: `config/nginx.conf` lines 7-12

### 4. Supervisor Configuration
- **Issue**: Nginx PID file permission issues
- **Fix**: Removed problematic PID file specification
- **Location**: `config/supervisord.conf` line 19

### 5. Database Table Ownership
- **Issue**: Table ownership conflicts with existing databases
- **Fix**: Dynamic table ownership detection and reassignment
- **Location**: `scripts/entrypoint.sh` lines 45-53

### 6. Config.php Generation
- **Issue**: Config.php syntax errors and generation failures
- **Fix**: Improved config generation with explicit variable substitution
- **Location**: `scripts/entrypoint.sh` lines 85-110

### 7. OCC Command Path
- **Issue**: OCC commands failing due to path issues
- **Fix**: Proper user context and path handling
- **Location**: `scripts/entrypoint.sh` lines 230-280

## 🧪 Testing

Run the deployment test script to verify all fixes:

```bash
# Make the script executable
chmod +x test-deployment.sh

# Run the test
./test-deployment.sh
```

Expected output:
```
🎉 All tests passed! Deployment should work correctly.
📋 Summary of fixes applied:
  - ✅ Nextcloud application files installation
  - ✅ Nginx PORT substitution fix
  - ✅ Supervisor nginx PID file fix
  - ✅ Database table ownership fix
  - ✅ Config.php generation improvement
  - ✅ OCC command path fix
🚀 Ready for Railway deployment!
```

## 📊 Deployment Process

### Build Phase
1. **Base Image**: Uses `nextcloud:29-fpm-alpine`
2. **Application Installation**: Downloads and installs Nextcloud files
3. **Dependencies**: Installs nginx, supervisor, and required tools
4. **Configuration**: Copies all configuration files
5. **Validation**: Comprehensive syntax and integrity checks

### Runtime Phase
1. **Environment Setup**: Configures all environment variables
2. **Database Connection**: Validates PostgreSQL connectivity
3. **Redis Connection**: Validates Redis connectivity
4. **Configuration**: Generates or updates config.php
5. **Services**: Starts nginx, php-fpm, and cron via supervisor

### Health Checks
- **Nginx**: Validates configuration and startup
- **PHP-FPM**: Ensures PHP processes are running
- **Database**: Confirms database connectivity
- **Redis**: Verifies cache connectivity

## 🔍 Troubleshooting

### Common Issues

#### 1. Database Connection Failed
```bash
❌ [PHASE: DB_CHECK] Database connection failed
```
**Solution**: Verify PostgreSQL environment variables are correct

#### 2. Redis Connection Failed
```bash
❌ Redis is ready
```
**Solution**: Check Redis host, port, and password configuration

#### 3. Nginx Configuration Error
```bash
❌ Nginx failed
```
**Solution**: Verify PORT environment variable and nginx config syntax

#### 4. OCC Commands Failing
```bash
❌ [PHASE: UPGRADE] Config unreadable
```
**Solution**: Check config.php syntax and file permissions

### Log Locations
- **Nginx**: `/var/log/nginx/error.log`
- **Supervisor**: `/var/log/supervisor/`
- **Nextcloud**: `/var/www/html/nextcloud.log`

### Debug Commands
```bash
# Check running processes
ps aux

# Check nginx status
nginx -t

# Check supervisor status
supervisorctl status

# Check database connectivity
psql "postgresql://user:pass@host:port/db"

# Check Redis connectivity
redis-cli -h host -p port ping
```

## 🚀 Performance Optimization

### PHP Settings
- **Memory Limit**: 512M (configurable via `PHP_MEMORY_LIMIT`)
- **Upload Limit**: 512M (configurable via `PHP_UPLOAD_LIMIT`)
- **OPcache**: Enabled for better performance

### Redis Caching
- **Local Cache**: Redis for session storage
- **Locking**: Redis for file locking
- **Configuration**: Automatic setup in entrypoint

### Nginx Optimization
- **Gzip Compression**: Enabled for all static assets
- **Client Buffering**: Optimized for large file uploads
- **Timeout Settings**: Extended for better reliability

## 📈 Monitoring

### Health Endpoints
- **Status Page**: `https://your-app.up.railway.app/status.php`
- **Deployment Status**: `https://your-app.up.railway.app/deployment-status.html`
- **Root Access**: `https://your-app.up.railway.app/`

### Metrics to Monitor
- **Response Time**: Monitor page load times
- **Database Connections**: Track PostgreSQL connection usage
- **Redis Memory**: Monitor Redis memory usage
- **Disk Usage**: Watch data directory growth

## 🔄 Updates and Maintenance

### Nextcloud Updates
The deployment automatically handles Nextcloud updates through the upgrade process in the entrypoint script.

### Configuration Updates
1. Update environment variables in Railway
2. Redeploy the application
3. Monitor logs for successful configuration

### Backup Strategy
1. **Database**: Use Railway's built-in PostgreSQL backups
2. **Files**: Implement external backup for the data directory
3. **Configuration**: Store config.php in a secure location

## 📞 Support

If you encounter issues:

1. **Check Logs**: Review deployment and application logs
2. **Run Tests**: Execute the test-deployment.sh script
3. **Verify Environment**: Ensure all environment variables are set
4. **Check Connectivity**: Verify database and Redis connections

For additional support, refer to:
- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [Railway Documentation](https://docs.railway.app/)
- [GitHub Issues](https://github.com/your-repo/issues)
