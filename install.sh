#!/bin/bash
# ============================================================
#  AUTO INSTALLER PTERODACTYL - ASTRACODE
#  Credit : AstraCodeX | WhatsApp : wa.me/6287748920504
# ============================================================

# ---------- WARNA ----------
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
#  FIX: PASTIKAN SCRIPT JALAN SEBAGAI ROOT
#  (menyelesaikan error "Permission denied" & prompt sudo berulang)
# ============================================================
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}[!] Script ini perlu akses root. Menjalankan ulang dengan sudo...${NC}"

  # Jika dijalankan lewat "bash <(curl ...)" atau "curl ... | bash",
  # $0 bukan file fisik (mis. /dev/fd/63) sehingga tidak bisa dibuka lagi
  # oleh proses sudo yang baru. Solusinya: salin isi script ke file
  # sementara di /tmp dulu, baru dijalankan ulang dengan sudo dari sana.
  TMP_SCRIPT=$(mktemp /tmp/astra-installer.XXXXXX.sh)

  if ! cat "$0" > "$TMP_SCRIPT" 2>/dev/null || [ ! -s "$TMP_SCRIPT" ]; then
    cat /dev/stdin > "$TMP_SCRIPT" 2>/dev/null
  fi

  if [ ! -s "$TMP_SCRIPT" ]; then
    echo -e "${RED}[x] Gagal menyiapkan ulang script untuk dijalankan sebagai root.${NC}"
    echo -e "${YELLOW}    Coba jalankan dengan cara berikut sebagai gantinya:${NC}"
    echo -e "    curl -s https://raw.githubusercontent.com/Astra-Devl/installer/main/install.sh -o install.sh && sudo bash install.sh"
    rm -f "$TMP_SCRIPT"
    exit 1
  fi

  chmod +x "$TMP_SCRIPT"
  exec sudo bash "$TMP_SCRIPT" "$@"
fi

# ============================================================
#  FIX: NAIKKAN LIMIT INOTIFY & OPEN FILES
#  (menyelesaikan error "Failed to allocate directory watch: Too many open files")
# ============================================================
fix_inotify_limits() {
  CURRENT_WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)
  CURRENT_INSTANCES=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)

  if [ "$CURRENT_WATCHES" -lt 524288 ] 2>/dev/null; then
    grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf 2>/dev/null \
      && sed -i 's/^fs.inotify.max_user_watches=.*/fs.inotify.max_user_watches=524288/' /etc/sysctl.conf \
      || echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf
  fi

  if [ "$CURRENT_INSTANCES" -lt 512 ] 2>/dev/null; then
    grep -q "fs.inotify.max_user_instances" /etc/sysctl.conf 2>/dev/null \
      && sed -i 's/^fs.inotify.max_user_instances=.*/fs.inotify.max_user_instances=512/' /etc/sysctl.conf \
      || echo "fs.inotify.max_user_instances=512" >> /etc/sysctl.conf
  fi

  sysctl -p >/dev/null 2>&1
  ulimit -n 65536 2>/dev/null
}

# ---------- GLOBAL VAR ----------
PANEL_DIR="/var/www/pterodactyl"
WORK_DIR="/root/protect-tmp"
EXISTING_LOCK="$PANEL_DIR/.protect.lock"

# ============================================================
#  FUNGSI BANTUAN
# ============================================================
banner() {
  echo -e ""
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e "${BLUE}[+]   $1${NC}"
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e ""
}

ok_msg() {
  echo -e "${GREEN}[✓] $1${NC}"
}

err_msg() {
  echo -e "${RED}[x] $1${NC}"
}

warn_msg() {
  echo -e "${YELLOW}[!] $1${NC}"
}

info_msg() {
  echo -e "${CYAN}[i] $1${NC}"
}

fail() {
  err_msg "$1"
  sleep 2
  return 1
}

pause_clear() {
  sleep 2
  clear
}

fix_permission() {
  chown -R www-data:www-data "$PANEL_DIR" 2>/dev/null
  find "$PANEL_DIR" -type d -exec chmod 755 {} \; 2>/dev/null
  find "$PANEL_DIR" -type f -exec chmod 644 {} \; 2>/dev/null
}

clear_cache() {
  cd "$PANEL_DIR" || return
  php artisan view:clear   >/dev/null 2>&1
  php artisan config:clear >/dev/null 2>&1
  php artisan route:clear  >/dev/null 2>&1
  php artisan cache:clear  >/dev/null 2>&1
}

# ============================================================
#  WELCOME
# ============================================================
display_welcome() {
  clear
  echo -e "${CYAN}"
  cat << "EOF"
    ___         __             ______          __        _  __
   /   |  _____/ /_____ ______ / ____/___  ____/ /__     | |/ /
  / /| | / ___/ __/ __ `/ ___// /   / __ \/ __  / _ \    |   / 
 / ___ |(__  ) /_/ /_/ / /   / /___/ /_/ / /_/ /  __/   /   |  
/_/  |_/____/\__/\__,_/_/    \____/\____/\__,_/\___/   /_/|_|  
EOF
  echo -e "${NC}"
  echo -e "${YELLOW}              ═══ AUTO INSTALLER PTERODACTYL ═══${NC}"
  echo -e "${BLUE}                  © AstraCodeX${NC}"
  echo -e "${BLUE}              Telegram : t.me/astradigitalz${NC}"
  echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
  echo -e ""
  echo -e "${GREEN}  ⚡ Selamat datang di Auto Installer AstraCodeX${NC}"
  echo -e "  Script ini dibuat untuk mempermudah instalasi"
  echo -e "  theme, panel, dan node Pterodactyl secara otomatis."
  echo -e ""
  echo -e "${RED}  ⚠ Dilarang Keras Share Bebas Tanpa Izin!${NC}"
  echo -e ""
  echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
  echo -e "${YELLOW}  Memuat menu utama...${NC}"
  echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
  echo -e ""
  sleep 4
  clear
}

# ============================================================
#  UPDATE & INSTALL JQ
# ============================================================
install_jq() {
  banner "UPDATE & INSTALL JQ                           "
  apt update && apt install -y jq
  if [ $? -eq 0 ]; then
    ok_msg "INSTALL JQ BERHASIL"
  else
    err_msg "INSTALL JQ GAGAL"
    exit 1
  fi
  pause_clear
}

# ============================================================
#  INSTALL THEME
# ============================================================
install_theme() {
  while true; do
    clear
    echo -e "${CYAN}"
    cat << "EOF"
    ___         __             ______          __        _  __
   /   |  _____/ /_____ ______ / ____/___  ____/ /__     | |/ /
  / /| | / ___/ __/ __ `/ ___// /   / __ \/ __  / _ \    |   / 
 / ___ |(__  ) /_/ /_/ / /   / /___/ /_/ / /_/ /  __/   /   |  
/_/  |_/____/\__/\__,_/_/    \____/\____/\__,_/\___/   /_/|_|  
EOF
    echo -e "${NC}"
    echo -e "${YELLOW}              ═══ AUTO INSTALLER PTERODACTYL ═══${NC}"
    echo -e "${BLUE}                  © AstraCodeX | zerodev${NC}"
    echo -e "${BLUE}              Telegram : t.me/ext4you${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
    echo -e ""
    echo -e "${GREEN}  [ PILIH THEME YANG INGIN DIINSTALL ]${NC}"
    echo -e ""
    echo -e "  ${CYAN}[1]${NC}  Stellar"
    echo -e "  ${CYAN}[2]${NC}  Billing"
    echo -e "  ${CYAN}[3]${NC}  Enigma"
    echo -e "  ${CYAN}[4]${NC}  NeoBrutalism"
    echo -e "  ${CYAN}[5]${NC}  Elysium"
    echo -e "  ${CYAN}[6]${NC}  Nebula ${YELLOW}(butuh Blueprint)${NC}"
    echo -e "  ${CYAN}[7]${NC}  Blueprint Framework"
    echo -e ""
    echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
    echo -e "  ${RED}[x]${NC}  Kembali ke Menu Utama"
    echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
    echo -e ""
    echo -ne "${YELLOW}  ➜ Pilih theme [1-7/x] : ${NC}"
    read -r SELECT_THEME

    case "$SELECT_THEME" in
      1) THEME_URL="https://github.com/Astra-Devl/installer/raw/refs/heads/main/theme/stellar.zip"; THEME_NAME="stellar"; break ;;
      2) THEME_URL="https://github.com/Astra-Devl/installer/raw/refs/heads/main/theme/billing.zip"; THEME_NAME="billing"; break ;;
      3) THEME_URL="https://github.com/Astra-Devl/installer/raw/refs/heads/main/theme/enigma.zip"; THEME_NAME="enigma"; break ;;
      4) THEME_URL="https://github.com/Astra-Devl/installer/raw/refs/heads/main/theme/NeoBrutalism.zip"; THEME_NAME="NeoBrutalism"; break ;;
      5) THEME_URL="https://github.com/Astra-Devl/installer/raw/refs/heads/main/theme/Elysium.zip"; THEME_NAME="ElysiumTheme"; break ;;
      6) THEME_URL="https://github.com/Astra-Devl/installer/raw/refs/heads/main/theme/nebulaptero.zip"; THEME_NAME="nebulaptero"; break ;;
      7) THEME_URL=""; THEME_NAME="blueprint"; break ;;
      x|X) return ;;
      *) err_msg "Pilihan tidak valid, silahkan coba lagi."; sleep 1 ;;
    esac
  done

  # ===================== BLUEPRINT =====================
  if [ "$SELECT_THEME" = "7" ]; then
    banner "INSTALL BLUEPRINT FRAMEWORK                   "
    apt-get update
    apt-get install -y ca-certificates curl gnupg zip unzip git curl wget

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
      gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | \
      tee /etc/apt/sources.list.d/nodesource.list
    apt-get update
    apt-get install -y nodejs
    npm i -g yarn

    cd "$PANEL_DIR" || return
    yarn
    yarn add cross-env

    wget "$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest | grep 'browser_download_url' | cut -d '"' -f 4)" -O release.zip
    mv release.zip "$PANEL_DIR/release.zip"
    cd "$PANEL_DIR" || return
    unzip -o release.zip

    FOLDER="$PANEL_DIR"
    WEBUSER="www-data"; USERSHELL="/bin/bash"; PERMISSIONS="www-data:www-data"

    sed -i -E \
      -e "s|WEBUSER=\"www-data\" #;|WEBUSER=\"$WEBUSER\" #;|g" \
      -e "s|USERSHELL=\"/bin/bash\" #;|USERSHELL=\"$USERSHELL\" #;|g" \
      -e "s|OWNERSHIP=\"www-data:www-data\" #;|OWNERSHIP=\"$PERMISSIONS\" #;|g" \
      "$FOLDER/blueprint.sh"

    chmod +x blueprint.sh
    bash blueprint.sh

    ok_msg "Blueprint berhasil diinstall."
    pause_clear
    return
  fi

  # ===================== NEBULA (butuh Blueprint) =====================
  if [ "$SELECT_THEME" = "6" ]; then
    if [ ! -f "$PANEL_DIR/blueprint.sh" ] && ! command -v blueprint >/dev/null 2>&1; then
      err_msg "Blueprint belum diinstall. Silakan pilih opsi 7 terlebih dahulu."
      sleep 3
      return
    fi

    banner "INSTALL NEBULA THEME                          "
    cd /root || return
    wget -q "$THEME_URL" -O /root/nebulaptero.zip
    rm -rf /root/nebula-tmp
    unzip -o /root/nebulaptero.zip -d /root/nebula-tmp

    BLUEPRINT_ARC=$(find /root/nebula-tmp -name "*.blueprint" | head -n1)
    if [ -z "$BLUEPRINT_ARC" ]; then
      err_msg "File .blueprint tidak ditemukan di dalam zip Nebula."
      rm -rf /root/nebula-tmp /root/nebulaptero.zip
      return
    fi

    cd "$PANEL_DIR" || return
    cp "$BLUEPRINT_ARC" "$PANEL_DIR/nebula.blueprint"
    blueprint -install nebula

    cd "$PANEL_DIR" && rm -f nebula.blueprint
    rm -rf /root/nebula-tmp /root/nebulaptero.zip

    ok_msg "Nebula Theme berhasil diinstall."
    pause_clear
    return
  fi

  # ===================== ELYSIUM =====================
  if [ "$SELECT_THEME" = "5" ]; then
    banner "INSTALL ELYSIUM THEME                         "
    cd /root || return
    wget -q "$THEME_URL" -O /root/ElysiumTheme.zip
    mv /root/ElysiumTheme.zip /var/www/
    unzip -o /var/www/ElysiumTheme.zip -d /var/www/
    rm -f /var/www/ElysiumTheme.zip

    # Node.js 22 (URL sudah diperbaiki)
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
      gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | \
      tee /etc/apt/sources.list.d/nodesource.list
    apt update
    apt install -y nodejs npm
    npm i -g yarn

    cd "$PANEL_DIR" || return
    yarn
    yarn build:production
    php artisan migrate --force
    php artisan view:clear

    ok_msg "Tema Elysium berhasil diinstall."
    pause_clear
    return
  fi

  # ===================== THEME LAMA (1-4) =====================
  if [ -e /root/pterodactyl ]; then
    rm -rf /root/pterodactyl
  fi
  cd /root || return
  wget -q "$THEME_URL" -O "/root/${THEME_NAME}.zip"
  unzip -o "/root/${THEME_NAME}.zip" -d /root/

  # ---------- STELLAR ----------
  if [ "$SELECT_THEME" = "1" ]; then
    banner "INSTALL THEME STELLAR                         "
    cp -rfT /root/pterodactyl "$PANEL_DIR"
    curl -sL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
    npm i -g yarn
    cd "$PANEL_DIR" || return
    yarn add react-feather
    php artisan migrate --force
    yarn build:production
    php artisan view:clear
    rm -f "/root/${THEME_NAME}.zip"
    rm -rf /root/pterodactyl
    ok_msg "INSTALL SUCCESS"
    pause_clear
    return
  fi

  # ---------- BILLING ----------
  if [ "$SELECT_THEME" = "2" ]; then
    banner "INSTALL THEME BILLING                         "
    cp -rfT /root/pterodactyl "$PANEL_DIR"
    curl -sL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
    npm i -g yarn
    cd "$PANEL_DIR" || return
    yarn add react-feather
    php artisan billing:install stable
    php artisan migrate --force
    yarn build:production
    php artisan view:clear
    rm -f "/root/${THEME_NAME}.zip"
    rm -rf /root/pterodactyl
    ok_msg "INSTALL SUCCESS"
    pause_clear
    return
  fi

  # ---------- ENIGMA ----------
  if [ "$SELECT_THEME" = "3" ]; then
    banner "INSTALL THEME ENIGMA                          "
    echo -e "${YELLOW}Masukkan link wa (https://wa.me...) : ${NC}"
    read -r LINK_WA
    echo -e "${YELLOW}Masukkan link group (https://.....) : ${NC}"
    read -r LINK_GROUP
    echo -e "${YELLOW}Masukkan link channel (https://...) : ${NC}"
    read -r LINK_CHNL

    DASH_FILE="/root/pterodactyl/resources/scripts/components/dashboard/DashboardContainer.tsx"
    if [ -f "$DASH_FILE" ]; then
      sed -i "s|LINK_WA|$LINK_WA|g" "$DASH_FILE"
      sed -i "s|LINK_GROUP|$LINK_GROUP|g" "$DASH_FILE"
      sed -i "s|LINK_CHNL|$LINK_CHNL|g" "$DASH_FILE"
    fi

    cp -rfT /root/pterodactyl "$PANEL_DIR"
    curl -sL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
    npm i -g yarn
    cd "$PANEL_DIR" || return
    yarn add react-feather
    php artisan migrate --force
    yarn build:production
    php artisan view:clear
    rm -f "/root/${THEME_NAME}.zip"
    rm -rf /root/pterodactyl
    ok_msg "INSTALL SUCCESS"
    sleep 3
    clear
    return
  fi

  # ---------- CLAYMORPHISM ----------
  if [ "$SELECT_THEME" = "4" ]; then
    banner "INSTALL THEME CLAYMORPHISM                    "
    cd /root || return
    apt install -y unzip
    rm -rf /root/clay-tmp
    unzip -oq "/root/${THEME_NAME}.zip" -d /root/clay-tmp

    tar -czf "/root/panel-backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C /var/www pterodactyl

    cp -rfT /root/clay-tmp/pterodactyl "$PANEL_DIR"

    cd "$PANEL_DIR" || return
    grep -q "theme-admin.php" routes/admin.php || \
      echo "require __DIR__ . '/theme-admin.php';" | tee -a routes/admin.php > /dev/null

    curl -sL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
    npm i -g yarn

    yarn add react-feather
    php artisan migrate --force
    yarn build:production

    php artisan view:clear
    php artisan config:clear
    php artisan route:clear
    php artisan queue:restart
    chown -R www-data:www-data "$PANEL_DIR"/*

    rm -f "/root/${THEME_NAME}.zip"
    rm -rf /root/clay-tmp

    ok_msg "INSTALL SUCCESS"
    pause_clear
    return
  fi

  err_msg "Pilihan tidak valid."
}

# ============================================================
#  UNINSTALL THEME
# ============================================================
uninstall_theme() {
  banner "DELETE THEME                                 "
  bash <(curl -s https://raw.githubusercontent.com/Astra-Devl/installer/refs/heads/main/repair.sh)
  ok_msg "DELETE THEME SUKSES"
  pause_clear
}

# ============================================================
#  INSTALL PROTECT
# ============================================================
install_protect() {
  banner "INSTALL PROTECT                              "

  [ -d "$PANEL_DIR" ] || { err_msg "Panel tidak ditemukan di $PANEL_DIR"; sleep 2; return; }

  PROTECT_URL="https://github.com/Astra-Devl/installer/raw/refs/heads/main/theme/protect.zip"

  info_msg "Mengunduh file proteksi..."
  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR" || return

  wget -q --show-progress "$PROTECT_URL" -O protect.zip || {
    err_msg "Gagal mengunduh file proteksi."
    rm -rf "$WORK_DIR"
    sleep 2
    return
  }

  # Validasi file bukan HTML 404 dan ukurannya wajar
  if [ ! -s protect.zip ] || ! unzip -tq protect.zip >/dev/null 2>&1; then
    err_msg "File protect.zip tidak valid (kemungkinan 404 / bukan zip)."
    rm -rf "$WORK_DIR"
    sleep 2
    return
  fi

  unzip -oq protect.zip -d "$WORK_DIR" || {
    err_msg "Gagal mengekstrak file proteksi."
    rm -rf "$WORK_DIR"
    sleep 2
    return
  }

  if [ ! -d "$WORK_DIR/pterodactyl" ]; then
    err_msg "Struktur folder proteksi tidak valid."
    rm -rf "$WORK_DIR"
    sleep 2
    return
  fi

  info_msg "Membuat backup panel..."
  BACKUP_FILE="/root/panel-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$BACKUP_FILE" -C /var/www pterodactyl || { err_msg "Gagal membuat backup."; return; }

  # Daftar file yang akan ditimpa
  FILE_LIST="$WORK_DIR/filelist.txt"
  ( cd "$WORK_DIR/pterodactyl" && find . -type f ) > "$FILE_LIST"

  echo "$BACKUP_FILE" > "$EXISTING_LOCK"

  info_msg "Menyalin file proteksi ke panel..."
  cp -rfT "$WORK_DIR/pterodactyl" "$PANEL_DIR" || {
    err_msg "Gagal menyalin file proteksi."
    tar -xzf "$BACKUP_FILE" -C /var/www
    fix_permission
    return
  }

  # Cek syntax PHP
  info_msg "Memeriksa syntax PHP..."
  SYNTAX_OK=1
  while read -r f; do
    case "$f" in
      *.php)
        if ! php -l "$PANEL_DIR/$f" >/dev/null 2>&1; then
          err_msg "Syntax error: $f"
          SYNTAX_OK=0
        fi
        ;;
    esac
  done < "$FILE_LIST"

  if [ "$SYNTAX_OK" -eq 0 ]; then
    warn_msg "Rollback ke file asli..."
    tar -xzf "$BACKUP_FILE" -C /var/www
    fix_permission
    err_msg "Install dibatalkan karena ada syntax error."
    sleep 2
    return
  fi

  fix_permission
  clear_cache
  rm -rf "$WORK_DIR"

  TOTAL=$(wc -l < "$FILE_LIST")
  echo -e ""
  echo -e "${GREEN}[✓] Backup disimpan: $BACKUP_FILE${NC}"
  echo -e "${GREEN}[✓] $TOTAL file proteksi terpasang.${NC}"
  echo -e "${YELLOW}Untuk melepas proteksi: bash install.sh restore${NC}"
  echo -e ""
  sleep 3
  clear
}

# ============================================================
#  RESTORE PROTECT
# ============================================================
restore_protect() {
  banner "RESTORE PROTECT                              "

  if [ ! -f "$EXISTING_LOCK" ]; then
    err_msg "Tidak ada lock file. Proteksi tidak terpasang."
    sleep 2
    return
  fi

  BACKUP_FILE=$(cat "$EXISTING_LOCK")
  if [ ! -f "$BACKUP_FILE" ]; then
    err_msg "Backup file tidak ditemukan: $BACKUP_FILE"
    sleep 2
    return
  fi

  warn_msg "Merestore panel dari backup: $BACKUP_FILE"
  tar -xzf "$BACKUP_FILE" -C /var/www

  fix_permission
  clear_cache

  rm -f "$EXISTING_LOCK"
  ok_msg "Proteksi berhasil dilepas."
  pause_clear
}

# ============================================================
#  CREATE NODE
# ============================================================
create_node() {
  banner "CREATE NODE                                  "
  read -p "Masukkan nama lokasi: " location_name
  read -p "Masukkan deskripsi lokasi: " location_description
  read -p "Masukkan domain: " domain
  read -p "Masukkan nama node: " node_name
  read -p "Masukkan RAM (dalam MB): " ram
  read -p "Masukkan jumlah maksimum disk space (dalam MB): " disk_space
  read -p "Masukkan Locid: " locid

  cd "$PANEL_DIR" || { err_msg "Direktori tidak ditemukan"; return; }

  php artisan p:location:make <<EOF
$location_name
$location_description
EOF

  php artisan p:node:make <<EOF
$node_name
$location_description
$locid
https
$domain
yes
no
no
$ram
$ram
$disk_space
$disk_space
100
8080
2022
/var/lib/pterodactyl/volumes
EOF

  ok_msg "CREATE NODE & LOCATION SUKSES"
  pause_clear
}

# ============================================================
#  INSTALL PANEL
# ============================================================
install_panel() {
  banner "INSTALL PANEL & WINGS (NODE)                 "

  read -p "Masukkan Domain Panel (cth: panel.domain.com) : " domainpanel
  read -p "Masukkan Domain Node  (cth: node.domain.com)  : " domainnode
  read -p "Masukkan RAM Server (dalam MB, cth: 100000)  : " ramserver
  read -p "Masukkan Username Admin                      : " useradmin
  read -p "Masukkan Password Admin                      : " pwadmin

  if [[ -z "$domainpanel" || -z "$domainnode" || -z "$ramserver" || -z "$useradmin" || -z "$pwadmin" ]]; then
    err_msg "Ada input yang kosong! Silahkan ulangi."
    sleep 2
    return
  fi

  info_msg "Memproses Instalasi Panel..."

  bash <(curl -s https://pterodactyl-installer.se) <<EOF
0
y
y
y
Asia/Jakarta
${useradmin}@gmail.com
${useradmin}@gmail.com
${useradmin}
${useradmin}
${useradmin}
${pwadmin}
${domainpanel}
y
y
${useradmin}@gmail.com
y
EOF

  info_msg "Panel selesai. Memproses Wings..."

  bash <(curl -s https://pterodactyl-installer.se) <<EOF
1
y
${domainpanel}
admin
admin
${domainnode}
${useradmin}@gmail.com
y
EOF

  info_msg "Membuat Node Otomatis di Panel..."
  bash <(curl -s https://raw.githubusercontent.com/Astra-Devl/installer/main/createnode.sh) <<EOF
Singapore
Node By AstraCodeX
${domainnode}
Node By AstraCodeX
${ramserver}
${ramserver}
1
EOF

  echo -e ""
  ok_msg "INSTALL PANEL & WINGS SUKSES"
  echo -e "Detail Akun:"
  echo -e " - Domain Panel : ${domainpanel}"
  echo -e " - Domain Node  : ${domainnode}"
  echo -e " - Username     : ${useradmin}"
  echo -e " - Password     : ${pwadmin}"
  echo -e " - RAM Node     : ${ramserver} MB"
  echo -e ""
  sleep 3
  clear
}

# ============================================================
#  UNINSTALL PANEL
# ============================================================
uninstall_panel() {
  banner "UNINSTALL PANEL                              "
  bash <(curl -s https://pterodactyl-installer.se) <<EOF
y
y
y
y
EOF
  ok_msg "UNINSTALL PANEL SUKSES"
  pause_clear
}

# ============================================================
#  CONFIGURE WINGS
# ============================================================
configure_wings() {
  banner "CONFIGURE WINGS                              "
  read -p "Masukkan token Configure menjalankan wings: " wings

  if [[ "$wings" == *"systemctl"* ]] || [[ "$wings" == *"wings"* ]]; then
    # Hanya izinkan token yang jelas command-nya
    bash -c "$wings"
  else
    warn_msg "Token tidak valid, coba jalankan manual."
  fi

  systemctl start wings
  ok_msg "CONFIGURE WINGS SUKSES"
  pause_clear
}

# ============================================================
#  RECOVERY ADMIN (buat akun admin baru untuk recovery akses panel sendiri
#  jika lupa password akun utama)
# ============================================================
recovery_admin() {
  banner "RECOVERY ADMIN PANEL                         "
  read -p "Masukkan Username Panel: " user
  read -p "Password login: " psswdhb

  cd "$PANEL_DIR" || { err_msg "Direktori tidak ditemukan"; return; }

  php artisan p:user:make <<EOF
yes
hackback@gmail.com
$user
$user
$user
$psswdhb
EOF

  ok_msg "AKUN TELAH DI ADD"
  sleep 2
}

# ============================================================
#  UBAH PASSWORD VPS
# ============================================================
ubahpw_vps() {
  banner "UBAH PASSWORD VPS                            "
  read -p "Masukkan Pw Baru: " pw
  read -p "Masukkan Ulang Pw Baru: " pw2

  if [ "$pw" != "$pw2" ]; then
    err_msg "Password tidak sama!"
    sleep 2
    return
  fi

  echo "root:$pw" | chpasswd
  ok_msg "GANTI PW VPS SUKSES"
  sleep 2
}

# ============================================================
#  MAIN MENU
# ============================================================
display_welcome
fix_inotify_limits
install_jq

# ============================================================
#  MAIN MENU - SIMPLE & CLEAN
# ============================================================
main_menu() {
  clear
  echo -e "${CYAN}"
  cat << "EOF"
    ___         __             ______          __        _  __
   /   |  _____/ /_____ ______ / ____/___  ____/ /__     | |/ /
  / /| | / ___/ __/ __ `/ ___// /   / __ \/ __  / _ \    |   / 
 / ___ |(__  ) /_/ /_/ / /   / /___/ /_/ / /_/ /  __/   /   |  
/_/  |_/____/\__/\__,_/_/    \____/\____/\__,_/\___/   /_/|_|  
EOF
  echo -e "${NC}"
  echo -e "${YELLOW}              ═══ AUTO INSTALLER PTERODACTYL ═══${NC}"
  echo -e "${BLUE}                  © AstraCodeX | zerodev${NC}"
  echo -e "${BLUE}              Telegram : t.me/ext4you${NC}"
  echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
  echo -e ""
  echo -e "${GREEN}  [ THEME MANAGEMENT ]${NC}"
  echo -e "  ${CYAN}[1]${NC}  Install Theme"
  echo -e "  ${CYAN}[2]${NC}  Uninstall Theme"
  echo -e ""
  echo -e "${GREEN}  [ PANEL MANAGEMENT ]${NC}"
  echo -e "  ${CYAN}[3]${NC}  Install Panel & Wings"
  echo -e "  ${CYAN}[4]${NC}  Uninstall Panel"
  echo -e "  ${CYAN}[5]${NC}  Configure Wings"
  echo -e "  ${CYAN}[6]${NC}  Create Node"
  echo -e ""
  echo -e "${GREEN}  [ SECURITY & UTILITY ]${NC}"
  echo -e "  ${CYAN}[7]${NC}  Install Protect"
  echo -e "  ${CYAN}[8]${NC}  Restore Protect"
  echo -e "  ${CYAN}[9]${NC}  Recovery Admin Panel"
  echo -e "  ${CYAN}[10]${NC} Ubah Password VPS"
  echo -e ""
  echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
  echo -e "  ${RED}[x]${NC}  Exit"
  echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
  echo -e ""
  echo -ne "${YELLOW}  ➜ Pilih menu [1-10/x] : ${NC}"
  read -r MENU_CHOICE
}

# ============================================================
#  LOOP UTAMA
# ============================================================
while true; do
  main_menu
  clear
  case "$MENU_CHOICE" in
    1)  install_theme ;;
    2)  uninstall_theme ;;
    3)  install_panel ;;
    4)  uninstall_panel ;;
    5)  configure_wings ;;
    6)  create_node ;;
    7)  install_protect ;;
    8)  restore_protect ;;
    9)  recovery_admin ;;
    10) ubahpw_vps ;;
    x|X) echo -e "${GREEN}[✓] Terima kasih telah menggunakan AstraCodeX!${NC}"; exit 0 ;;
    *)  err_msg "Pilihan tidak valid."; sleep 1 ;;
  esac

  echo -e ""
  echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
  echo -ne "${YELLOW}  Tekan [ENTER] untuk kembali ke menu...${NC}"
  read -r
done
