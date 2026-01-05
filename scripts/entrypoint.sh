#!/bin/bash

# Template-style entrypoint for Nextcloud Railway deployment
# Based on working mod_php setup with auto-green section 9

set -e

# Debug environment
echo "=== DEBUG: Environment ==="
env | grep -E "(POSTGRES|REDIS|NEXTCLOUD|PORT|RAILWAY)" | sort || true

# Parse database connection
if [ -n "$DATABASE_URL
