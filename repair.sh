#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "Silahkan jalankan sebagai root (gunakan sudo)."
    exit 1
fi

repairPanel() {
    cd /var/www/pterodactyl

    php artisan down || true

    # Hapus resource theme yang terpasang
    rm -rf /var/www/pterodactyl/resources
    rm -rf /var/www/pterodactyl/public/themes
    rm -rf /var/www/pterodactyl/public/assets

    # Unduh ulang panel versi terbaru (fresh)
    curl -fsSL https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz \
        | tar -xzv

    chmod -R 755 storage/* bootstrap/cache

    composer install --no-dev --optimize-autoloader

    php artisan view:clear
    php artisan config:clear
    php artisan migrate --seed --force

    chown -R www-data:www-data /var/www/pterodactyl/*

    php artisan queue:restart
    php artisan up
}

repairPanel