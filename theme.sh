#!/usr/bin/env bash
# =============================================================================
#  GlassBrutal Theme — installer (unduh zip dari GitHub, lalu pasang)
#  Pemakaian:
#     bash installer.sh              -> menu
#     bash installer.sh install      -> unduh + pasang / update tema
#     bash installer.sh uninstall    -> hapus tema, kembalikan file asli
#     bash installer.sh reset        -> reset pengaturan tema ke default
#  Satu baris (langsung dari GitHub):
#     bash <(curl -fsSL https://github.com/Astra-Devl/installer/raw/refs/heads/main/installer.sh) install
#  Env opsional: PANEL_DIR=/var/www/pterodactyl
#                THEME_ZIP_URL=<url zip lain>   YES=1   KEEP_SETTINGS=1
# =============================================================================
set -euo pipefail

THEME_ZIP_URL="${THEME_ZIP_URL:-https://github.com/Astra-Devl/installer/raw/refs/heads/main/theme/.zip}"
export PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
ACTION="${1:-menu}"

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_off=$'\e[0m'
info() { echo "${c_grn}[+]${c_off} $*"; }
warn() { echo "${c_ylw}[!]${c_off} $*"; }
die()  { echo "${c_red}[x]${c_off} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Jalankan sebagai root (sudo bash $0)"
[[ -f "$PANEL_DIR/artisan" ]] || die "Panel tidak ditemukan di $PANEL_DIR (set PANEL_DIR=...)"

TMP="$(mktemp -d /tmp/glassbrutal.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

need_unzip() {
  command -v unzip >/dev/null && return 0
  warn "unzip belum ada, mencoba memasang..."
  if command -v apt-get >/dev/null; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y unzip >/dev/null 2>&1
  elif command -v dnf >/dev/null; then
    dnf install -y unzip >/dev/null 2>&1
  elif command -v yum >/dev/null; then
    yum install -y unzip >/dev/null 2>&1
  fi
  command -v unzip >/dev/null || die "Gagal memasang unzip, pasang manual lalu ulangi."
}

download() {
  info "Mengunduh tema: $THEME_ZIP_URL"
  if command -v curl >/dev/null; then
    curl -fsSL --retry 3 --connect-timeout 15 -o "$TMP/theme.zip" "$THEME_ZIP_URL" \
      || die "Gagal mengunduh zip (cek URL / koneksi)."
  elif command -v wget >/dev/null; then
    wget -q --tries=3 --timeout=15 -O "$TMP/theme.zip" "$THEME_ZIP_URL" \
      || die "Gagal mengunduh zip (cek URL / koneksi)."
  else
    die "curl atau wget tidak ditemukan."
  fi
  [[ -s "$TMP/theme.zip" ]] || die "File zip kosong."
}

fetch_theme() {
  need_unzip
  download
  unzip -tq "$TMP/theme.zip" >/dev/null 2>&1 || die "File zip rusak atau bukan zip (cek URL raw)."
  unzip -q "$TMP/theme.zip" -d "$TMP/x"
  INSTALL_SH="$(find "$TMP/x" -type f -name install.sh | head -n 1)"
  [[ -n "$INSTALL_SH" ]] || die "install.sh tidak ditemukan di dalam zip."
}

run() { # aksi
  fetch_theme
  bash "$INSTALL_SH" "$1"
}

menu() {
  echo "=== GlassBrutal Theme Installer ==="
  echo " 1) Install / update tema"
  echo " 2) Uninstall tema"
  echo " 3) Reset pengaturan ke default"
  echo " 0) Keluar"
  local c=""
  read -r -p "Pilih: " c || true
  case "$c" in
    1) run install ;;
    2) run uninstall ;;
    3) run reset ;;
    *) exit 0 ;;
  esac
}

case "$ACTION" in
  menu) menu ;;
  install|uninstall|reset) run "$ACTION" ;;
  *) die "Aksi tidak dikenal: $ACTION (install | uninstall | reset)" ;;
esac
