#!/bin/bash
set -e

chown -R nginx:nginx /app/storage /app/bootstrap/cache
chmod -R 775 /app/storage /app/bootstrap/cache

if [ -f /app/database/database.sqlite ]; then
    chown nginx:nginx /app/database/database.sqlite
fi

if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
    php artisan migrate --force
fi

if [ "${OPTIMIZE:-false}" = "true" ]; then
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
fi

exec "$@"