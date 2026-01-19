# Stage 1: Build Frontend Assets
FROM node:20-alpine as frontend
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run prod

# Stage 2: Install Backend Dependencies
FROM composer:2 as backend
WORKDIR /app
COPY composer.json composer.lock ./
# Install prod dependencies only, no scripts (to avoid errors before code copy)
RUN composer install --no-dev --ignore-platform-reqs --no-scripts --prefer-dist --no-interaction

# Stage 3: Final Production Image (Nginx + PHP-FPM)
FROM php:8.3-fpm
WORKDIR /var/www

# Install system dependencies, Nginx, and Supervisor
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    zip \
    unzip \
    libzip-dev \
    nginx \
    supervisor \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip

# Copy Application Code (Except .dockerignore)
COPY . /var/www

# Copy Vendor from Backend Stage
COPY --from=backend /app/vendor /var/www/vendor

# Copy Assets from Frontend Stage
COPY --from=frontend /app/public/css /var/www/public/css
COPY --from=frontend /app/public/js /var/www/public/js
COPY --from=frontend /app/public/mix-manifest.json /var/www/mix-manifest.json

# Configure Nginx
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Configure Supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Permission Setup
RUN chown -R www-data:www-data /var/www \
    && chmod -R 775 /var/www/storage \
    && chmod -R 775 /var/www/bootstrap/cache

# Expose Port 80 (HTTP) instead of 9000 (FastCGI)
EXPOSE 80

# Use Supervisor as the entrypoint to run both Nginx and PHP-FPM
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]