# ============================================
# Stage: PHP 8.5 base (Rocky Linux 9 + Remi)
# ============================================
FROM rockylinux:9 AS php-base

RUN dnf install -y epel-release \
    && dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm \
    && dnf module reset php -y \
    && dnf module enable php:remi-8.5 -y \
    && dnf install -y \
        php-cli \
        php-common \
        php-bcmath \
        php-curl \
        php-gd \
        php-intl \
        php-mbstring \
        php-mysqlnd \
        php-opcache \
        php-pdo \
        php-pgsql \
        php-process \
        php-sodium \
        php-xml \
        php-zip \
        php-pecl-redis5 \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && groupadd -r nginx \
    && useradd -r -g nginx -d /var/cache/nginx -s /sbin/nologin nginx

# ============================================
# Stage: Build (PHP + Node.js for asset compilation)
# ============================================
FROM php-base AS build

RUN dnf install -y dnf-utils \
    && dnf module reset nodejs -y \
    && dnf module enable nodejs:22 -y \
    && dnf install -y nodejs npm \
    && dnf clean all \
    && rm -rf /var/cache/dnf

RUN curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress --no-scripts

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN composer dump-autoload --optimize \
    && php artisan package:discover --ansi

RUN npm run build

# ============================================
# Stage: web (nginx + php-fpm via supervisor)
# ============================================
FROM php-base AS web

RUN dnf install -y php-fpm nginx supervisor \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY docker/php/www.conf /etc/php-fpm.d/www.conf
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY docker/supervisor/supervisord.conf /etc/supervisord.conf
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN rm -f /etc/nginx/conf.d/php-fpm.conf \
    && rm -f /etc/nginx/default.d/php.conf \
    && mkdir -p /run/php-fpm \
    && chown nginx:nginx /run/php-fpm \
    && chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /app

COPY --from=build /app /app

RUN mkdir -p /app/storage/logs \
    /app/storage/framework/cache \
    /app/storage/framework/sessions \
    /app/storage/framework/views \
    /app/bootstrap/cache \
    && touch /app/database/database.sqlite \
    && chown -R nginx:nginx /app/storage /app/bootstrap/cache /app/database/database.sqlite \
    && chmod -R 775 /app/storage /app/bootstrap/cache

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]

# ============================================
# Stage: worker (queue:work)
# ============================================
FROM php-base AS worker

WORKDIR /app

COPY --from=build /app /app

RUN mkdir -p /app/storage/logs \
    /app/storage/framework/cache \
    /app/storage/framework/sessions \
    /app/storage/framework/views \
    /app/bootstrap/cache \
    && touch /app/database/database.sqlite \
    && chown -R nginx:nginx /app/storage /app/bootstrap/cache /app/database/database.sqlite \
    && chmod -R 775 /app/storage /app/bootstrap/cache

ENTRYPOINT ["php", "artisan"]
CMD ["queue:work", "--sleep=3", "--tries=3", "--max-time=3600"]