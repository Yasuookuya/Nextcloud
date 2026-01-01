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
export POSTGRES_HOST=${POSTGRES_HOST:-"postgres-n76t.railway.internal"}
export POSTGRES_PORT=${POSTGRES_PORT:-"5432"}
export POSTGRES_USER=${POSTGRES_USER:-"postgres"}
export POSTGRES_DB=${POSTGRES_DB:-"railway"}

export DATABASE_URL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

export REDIS_HOST=${REDIS_HOST:-"redis-svle.railway.internal"}
export REDIS_PORT=${REDIS_PORT:-"6379"}
export REDIS_HOST_PASSWORD=${REDIS_HOST_PASSWORD:-"OyHpmNkWOQsPxrzLBxrXiAlnRlYbWeFY"}

export NEXTCLOUD_TRUSTED_DOMAINS=${NEXTCLOUD_TRUSTED_DOMAINS:-"nextcloud-railway-template-website.up.railway.app,localhost,::1,RAILWAY_PRIVATE_DOMAIN,RAILWAY_STATIC_URL"}
export NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-"kikaiworksadmin"}
export NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-"2046S@nto!7669Y@"}
export NEXTCLOUD_UPDATE_CHECK=${NEXTCLOUD_UPDATE_CHECK:-"false"}
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
