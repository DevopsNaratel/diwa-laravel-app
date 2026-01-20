#!/bin/sh

# Exit immediately if a command exits with a non-zero status
set -e

# Clear caches to ensure configuration is up to date
echo "Clearing caches..."
php artisan optimize:clear

# Execute the main container command
exec "$@"
