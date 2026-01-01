#!/bin/bash

# Railway configuration script - sets environment variables for Nextcloud deployment
# Replaces functionality from railway.json and railway.toml

# Build settings (handled by Railway detecting Dockerfile)
# builder = "dockerfile"

# Deploy settings (handled by Railway)
# numReplicas = 1
# sleepApplication = false
# restartPolicyType = "ON_FAILURE"
# restartPolicyMaxRetries = 3
# startCommand = "/usr/local/bin/custom-entrypoint.sh"

# Healthcheck (handled by Railway)
# path = "/"
# timeout = 300

# Environment variables
export POSTGRES_HOST=${POSTGRES_HOST:-${{Postgres.RAILWAY_PRIVATE_DOMAIN}}}
export POSTGRES_USER=${POSTGRES_USER:-${{Postgres.PGUSER}}}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-${{Postgres.POSTGRES_PASSWORD}}}
export POSTGRES_DB=${POSTGRES_DB:-${{Postgres.POSTGRES_DB}}}

export REDIS_HOST=${REDIS_HOST:-${{Redis.RAILWAY_PRIVATE_DOMAIN}}}
export REDIS_PORT=${REDIS_PORT:-${{Redis.REDISPORT}}}
export REDIS_PASSWORD=${REDIS_PASSWORD:-${{Redis.REDIS_PASSWORD}}}

export NEXTCLOUD_TRUSTED_DOMAINS=${NEXTCLOUD_TRUSTED_DOMAINS:-"${{RAILWAY_PUBLIC_DOMAIN}} localhost"}
export NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-""}
export NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-""}
export NC_setup_create_db_user=${NC_setup_create_db_user:-"false"}
export NEXTCLOUD_DATA_DIR=${NEXTCLOUD_DATA_DIR:-"/data"}
export OVERWRITEPROTOCOL=${OVERWRITEPROTOCOL:-"https"}

export PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-"512M"}
export PHP_UPLOAD_LIMIT=${PHP_UPLOAD_LIMIT:-"512M"}

# SMTP settings (optional)
export SMTP_HOST=${SMTP_HOST:-null}
export SMTP_SECURE=${SMTP_SECURE:-"ssl"}
export SMTP_PORT=${SMTP_PORT:-"465"}
export SMTP_AUTHTYPE=${SMTP_AUTHTYPE:-"LOGIN"}
export SMTP_NAME=${SMTP_NAME:-null}
export SMTP_PASSWORD=${SMTP_PASSWORD:-null}
export MAIL_FROM_ADDRESS=${MAIL_FROM_ADDRESS:-null}
export MAIL_DOMAIN=${MAIL_DOMAIN:-null}

echo "✅ Railway environment variables set from railway.sh"
