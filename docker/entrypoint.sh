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

APP_ROLE="${1:-web}"

case "${APP_ROLE}" in
    web)
        exec /usr/bin/supervisord -c /etc/supervisord.conf
        ;;
    worker)
        exec php artisan queue:work --sleep=3 --tries=3 --max-time=3600
        ;;
    *)
        echo "Unknown APP_ROLE: ${APP_ROLE}. Must be 'web' or 'worker'."
        exit 1
        ;;
esac