<?php
$CONFIG = array (
  'htaccess.RewriteBase' => '/',
  'memcache.local' => '\\OC\\Memcache\\APCu',
  'apps_paths' =>
  array (
    0 =>
    array (
      'path' => '/var/www/html/apps',
      'url' => '/apps',
      'writable' => false,
    ),
    1 =>
    array (
      'path' => '/var/www/html/custom_apps',
      'url' => '/custom_apps',
      'writable' => true,
    ),
  ),
  'memcache.distributed' => '\\OC\\Memcache\\APCu',
  'memcache.locking' => '\\OC\\Memcache\\APCu',
  'upgrade.disable-web' => true,
  'instanceid' => 'oc7zu366lhjo',
  'passwordsalt' => 'c2Gehy6+qVjOTvM9HTfRt8UmrG4A7X',
  'secret' => 'wG91u4UihYueDc2MV4IAHBHuPwYldxprsdWqVceyUlkB0EZ3',
  'trusted_domains' =>
  array (
    0 => 'engineering.kikaiworks.com',
    1 => 'nextcloud-website.up.railway.app',
    2 => 'localhost',
  ),
  'datadirectory' => '/var/www/html/data',
  'dbtype' => 'pgsql',
  'dbhost' => 'postgres-ig4t.railway.internal',
  'dbport' => 5432,
  'dbuser' => 'postgres',
  'dbpassword' => 'wttqJuaNvUEwxhEOGHXloZUffysVyIrO',
  'dbname' => 'railway',
  'dbtableprefix' => 'oc_',
  'version' => '32.0.3.2',
  'overwrite.cli.url' => 'https://engineering.kikaiworks.com',
  'installed' => false,
  'maintenance' => false,
  'overwriteprotocol' => 'https',
);
