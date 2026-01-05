<?php
// Nextcloud Performance Optimizations based on official documentation
// This file contains PHP configurations optimized for Railway deployment

// Database optimizations for PostgreSQL
$CONFIG['dbpersistent'] = true;
$CONFIG['dbconnections'] = 2;

// Redis caching optimizations
$CONFIG['memcache.locking'] = '\\OC\\Memcache\\Redis';
$CONFIG['memcache.distributed'] = '\\OC\\Memcache\\Redis';
$CONFIG['redis'] = [
    'host' => getenv('REDIS_HOST') ?: 'localhost',
    'port' => getenv('REDIS_PORT') ?: 6379,
    'password' => getenv('REDIS_PASSWORD') ?: '',
    'dbindex' => 0,
    'timeout' => 1.5,
];

// File locking optimizations
$CONFIG['filelocking.enabled'] = true;
$CONFIG['filelocking.ttl'] = 3600;

// Performance optimizations
$CONFIG['preview_max_x'] = 2048;
$CONFIG['preview_max_y'] = 2048;
$CONFIG['jpeg_quality'] = 60;

// Cron optimizations
$CONFIG['cronjob_check_interval'] = 900; // 15 minutes

// Maintenance optimizations
$CONFIG['maintenance_window_start'] = 1; // 1:00 AM

// Security optimizations for Railway
$CONFIG['overwrite.cli.url'] = 'https://' . getenv('RAILWAY_PUBLIC_DOMAIN');
$CONFIG['overwriteprotocol'] = 'https';

// Railway-specific optimizations
$CONFIG['log_type'] = 'file';
$CONFIG['logfile'] = '/var/log/nextcloud.log';
$CONFIG['loglevel'] = 2; // Warnings and errors only
$CONFIG['logdateformat'] = 'Y-m-d H:i:s';

// Performance monitoring
$CONFIG['debug'] = false;
$CONFIG['profiler'] = false;

// APCu optimizations (already configured in php.ini)
$CONFIG['memcache.local'] = '\\OC\\Memcache\\APCu';

// Chunking for large file uploads
$CONFIG['chunking_parallel_upload'] = true;

// Background job optimizations
$CONFIG['background_job_max_age'] = 24 * 60 * 60; // 24 hours

?>
