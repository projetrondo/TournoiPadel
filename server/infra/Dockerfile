# Image de l'API EAGLE (Symfony 7.4, PHP 8.4, FPM), même socle que l'API de Rondo.
FROM php:8.4-fpm-alpine AS base

RUN apk add --no-cache icu-dev postgresql-dev \
    && docker-php-ext-install -j"$(nproc)" intl pdo_pgsql opcache

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /app

# ---------- production ----------
FROM base AS prod

ENV APP_ENV=prod APP_DEBUG=0
RUN { \
      echo 'opcache.enable=1'; \
      echo 'opcache.validate_timestamps=0'; \
      echo 'opcache.memory_consumption=64'; \
      echo 'expose_php=0'; \
    } > /usr/local/etc/php/conf.d/zz-eagle.ini

# Dépendances d'abord : la couche est réutilisée tant que composer.lock ne change pas.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --no-interaction --prefer-dist

COPY bin bin
COPY config config
COPY migrations migrations
COPY public public
COPY src src
COPY .env .env
RUN composer dump-autoload --no-dev --classmap-authoritative \
    && php bin/console cache:warmup \
    && chown -R www-data:www-data var

USER www-data
