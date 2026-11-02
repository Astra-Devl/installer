#!/usr/bin/env bash
# =============================================================================
#  Pterodactyl Panel Protect Installer  (tanpa whitelist IP VPS) + Tema Neo Brutalism
#  Pemakaian:
#     bash protect-pterodactyl.sh              -> menu
#     bash protect-pterodactyl.sh install      -> install / update protect
#     bash protect-pterodactyl.sh uninstall    -> hapus protect (tanpa input IP)
#     bash protect-pterodactyl.sh theme-login | theme-app | theme-admin | theme-all
#     bash protect-pterodactyl.sh theme-brand  -> atur nama + logo header
#     bash protect-pterodactyl.sh theme-uninstall
#  Opsional (env): PANEL_DIR=/var/www/pterodactyl  SUPPORT_URL=https://t.me/xxx
#                  BRAND_NAME="Nama Panel"  BRAND_LOGO="https://.../logo.png | /path/logo.png"
#                  YES=1 (lewati konfirmasi uninstall)
# =============================================================================
set -euo pipefail

PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
ACTION="${1:-menu}"
BK="$PANEL_DIR/storage/protect-backup"
PROTECT_DIR="$PANEL_DIR/storage/protect"

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_off=$'\e[0m'
info() { echo "${c_grn}[+]${c_off} $*"; }
warn() { echo "${c_ylw}[!]${c_off} $*"; }
die()  { echo "${c_red}[x]${c_off} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Jalankan sebagai root (sudo bash $0)"
[[ -f "$PANEL_DIR/artisan" ]] || die "Panel tidak ditemukan di $PANEL_DIR (set PANEL_DIR=...)"
command -v php >/dev/null || die "php tidak ditemukan"
command -v perl >/dev/null || die "perl tidak ditemukan"

OWNER="$(stat -c %U "$PANEL_DIR/artisan")"

# ----------------------------------------------------------------- helpers ---
rel_of() { echo "${1#"$PANEL_DIR"/}"; }

backup() {
  local f="$1" rel; rel="$(rel_of "$f")"
  if [[ -f "$f" && ! -e "$BK/original/$rel" ]]; then
    mkdir -p "$BK/original/$(dirname "$rel")"
    cp -p "$f" "$BK/original/$rel"
  fi
}

in_created() { grep -qxF "$(rel_of "$1")" "$BK/created.list" 2>/dev/null; }

mark_created() {
  local rel; rel="$(rel_of "$1")"
  [[ -e "$BK/original/$rel" ]] && return 0
  in_created "$1" || echo "$rel" >> "$BK/created.list"
}

# write_file <path>  (isi dari stdin)
write_file() {
  local f="$1"
  mkdir -p "$(dirname "$f")" "$BK"
  if [[ -f "$f" ]]; then
    in_created "$f" || backup "$f"
  else
    mark_created "$f"
  fi
  cat > "$f"
}

as_owner() {
  if command -v runuser >/dev/null; then
    (cd "$PANEL_DIR" && runuser -u "$OWNER" -- "$@")
  else
    (cd "$PANEL_DIR" && sudo -u "$OWNER" "$@")
  fi
}

post_steps() {
  chown -R "$OWNER:$OWNER" "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache" 2>/dev/null || true
  as_owner php artisan view:clear  >/dev/null 2>&1 || warn "view:clear gagal"
  as_owner php artisan cache:clear >/dev/null 2>&1 || true
  as_owner php artisan queue:restart >/dev/null 2>&1 || true
  for u in $(systemctl list-units --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^php[0-9.]*-fpm\.service$' || true); do
    systemctl reload "$u" >/dev/null 2>&1 || true
  done
}

restore_original() {
  [[ -d "$BK" ]] || die "Backup tidak ditemukan, tidak ada yang bisa dikembalikan."
  if [[ -d "$BK/original" ]]; then
    (cd "$BK/original" && find . -type f) | while read -r rel; do
      cp -p "$BK/original/$rel" "$PANEL_DIR/$rel"
    done
  fi
  if [[ -f "$BK/created.list" ]]; then
    while read -r rel; do rm -f "$PANEL_DIR/$rel"; done < "$BK/created.list"
  fi
  rm -rf "$PROTECT_DIR" "$BK"
  # file blade yang dikembalikan bisa menghapus injeksi tema: pasang ulang bila tema aktif
  if [[ -f "${THEME_CFG:-/nonexistent}" ]]; then theme_inject_all || true; fi
  post_steps
}

# Uninstall: cukup konfirmasi y/N (tidak lagi meminta IP VPS)
uninstall_protect() {
  [[ -d "$BK" ]] || die "Protect belum terpasang (backup tidak ditemukan)."
  if [[ "${YES:-0}" != "1" ]]; then
    local a=""
    read -r -p "Hapus proteksi dan kembalikan file asli? [y/N]: " a || true
    [[ "${a,,}" == "y" || "${a,,}" == "yes" ]] || die "Uninstall dibatalkan."
  fi
  restore_original
  info "Proteksi dihapus, file asli dikembalikan."
  exit 0
}

# =================================================================== TEMA ===
# Tema Neo Brutalism murni (tanpa build ulang frontend): shell baru (header + sidebar),
# ikon Font Awesome solid/regular, nama & logo header bisa diatur (theme-brand).
THEME_DIR="$PANEL_DIR/storage/protect-theme"
THEME_CFG="$THEME_DIR/theme.json"
THEME_PUB="$PANEL_DIR/public/protect-theme"
THEME_PARTIAL="$PANEL_DIR/resources/views/partials/protect-theme.blade.php"
THEME_WRAPPER_VIEW="$PANEL_DIR/resources/views/templates/wrapper.blade.php"
THEME_CORE_VIEW="$PANEL_DIR/resources/views/templates/base/core.blade.php"
THEME_ADMIN_VIEW="$PANEL_DIR/resources/views/layouts/admin.blade.php"

theme_flag() { if grep -q "\"$1\":true" "$THEME_CFG" 2>/dev/null; then echo true; else echo false; fi; }
theme_get() { # key default
  php -r '$j=json_decode((string)@file_get_contents($argv[1]),true)?:[];$v=$j[$argv[2]]??$argv[3];echo is_bool($v)?($v?"true":"false"):$v;' \
    "$THEME_CFG" "$1" "${2:-}"
}
theme_set() { # key type(bool|str) value
  mkdir -p "$THEME_DIR"
  php -r '$f=$argv[1];$j=json_decode((string)@file_get_contents($f),true)?:[];
          $j[$argv[2]]=$argv[3]==="bool"?($argv[4]==="true"):$argv[4];$j["v"]=(string)time();
          file_put_contents($f,json_encode($j,JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE)."\n");' \
    "$THEME_CFG" "$1" "$2" "$3"
}

theme_user_view() { # view yang punya <head>/<body> (wrapper React app)
  if [[ -f "$THEME_WRAPPER_VIEW" ]]; then echo "$THEME_WRAPPER_VIEW"; else echo "$THEME_CORE_VIEW"; fi
}

theme_inject() { # file, area
  local f="$1" area="$2" tag
  [[ -f "$f" ]] || { warn "Tidak ditemukan: $(rel_of "$f")"; return 1; }
  if grep -q 'partials.protect-theme' "$f"; then return 0; fi
  backup "$f"
  for tag in '</head\s*>' '</body\s*>'; do
    AREA="$area" TAG="$tag" perl -0pi -e 'my $i = q{@includeIf("partials.protect-theme", ["area" => "} . $ENV{AREA} . q{"])}; s/($ENV{TAG})/$i\n$1/i' "$f"
    if grep -q 'partials.protect-theme' "$f"; then
      info "Patch tema: $(rel_of "$f")"
      return 0
    fi
  done
  printf '\n@includeIf("partials.protect-theme", ["area" => "%s"])\n' "$area" >> "$f"
  warn "Tag </head> dan </body> tidak ada di $(rel_of "$f"); include ditambahkan di akhir file."
}
theme_strip() { # hapus include tema dari sebuah view
  local f="$1"
  [[ -f "$f" ]] || return 0
  perl -0pi -e 's/[ \t]*\@includeIf\("partials\.protect-theme"[^\n]*\n?//g' "$f"
}
theme_inject_all() {
  # versi lama menyuntik ke core.blade.php (tidak punya <head>); bersihkan bila wrapper tersedia
  if [[ -f "$THEME_WRAPPER_VIEW" ]]; then theme_strip "$THEME_CORE_VIEW"; fi
  theme_inject "$(theme_user_view)" user || true
  theme_inject "$THEME_ADMIN_VIEW" admin || true
}

theme_write_partial() {
  mkdir -p "$(dirname "$THEME_PARTIAL")"
  cat > "$THEME_PARTIAL" <<'BLADE'
@php
    $__th = json_decode((string) @file_get_contents(storage_path('protect-theme/theme.json')), true) ?: [];
    $__v = $__th['v'] ?? '1';
    $__admin = ($area ?? 'user') === 'admin';
    $__cfg = json_encode([
        'brand' => (string) ($__th['brand'] ?? 'Pterodactyl'),
        'logo' => (string) ($__th['logo'] ?? ''),
        'login' => !empty($__th['login']),
        'app' => !empty($__th['app']),
    ], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
@endphp
@if ($__admin)
    @if (!empty($__th['admin']))
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/v4-shims.min.css">
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;700&display=swap">
        <link rel="stylesheet" href="/protect-theme/base.css?v={{ $__v }}">
        <link rel="stylesheet" href="/protect-theme/admin.css?v={{ $__v }}">
        <script>window.__PTN = {!! $__cfg !!};</script>
        <script src="/protect-theme/admin.js?v={{ $__v }}" defer></script>
    @endif
@elseif (!empty($__th['login']) || !empty($__th['app']))
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;700&display=swap">
    <link rel="stylesheet" href="/protect-theme/base.css?v={{ $__v }}">
    <script>
        window.__PTN = {!! $__cfg !!};
        document.documentElement.classList.add(location.pathname.indexOf('/auth') === 0 ? 'ptn-auth' : 'ptn-app');
    </script>
    @if (!empty($__th['login']))
        <link rel="stylesheet" href="/protect-theme/login.css?v={{ $__v }}">
    @endif
    @if (!empty($__th['app']))
        <link rel="stylesheet" href="/protect-theme/app.css?v={{ $__v }}">
    @endif
    <script src="/protect-theme/sidebar.js?v={{ $__v }}" defer></script>
@endif
BLADE
}

theme_write_base() {
  cat > "$THEME_PUB/base.css" <<'CSS'
/* Neo Brutalism - variabel dasar */
:root{
  --ptn-bg:#FFF4D6;--ptn-ink:#111111;
  --ptn-yellow:#FFD60A;--ptn-pink:#FF6B9D;--ptn-blue:#4D96FF;--ptn-green:#5BE584;--ptn-orange:#FF9F1C;
  --ptn-font:"Space Grotesk","Archivo",system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
  --ptn-mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
}
::selection{background:var(--ptn-yellow);color:#111}
.ptn-logo img{display:block;max-height:34px;width:auto}
CSS
}

theme_write_login() {
  cat > "$THEME_PUB/login.css" <<'CSS'
/* Neo Brutalism - halaman login (/auth/*) */
html.ptn-auth body{
  background-color:var(--ptn-bg)!important;
  background-image:radial-gradient(rgba(17,17,17,.14) 1.5px,transparent 1.5px);
  background-size:24px 24px;
  color:var(--ptn-ink)!important;font-family:var(--ptn-font)!important;padding-top:64px;
}
html.ptn-auth #app,html.ptn-auth #app > div{background:transparent!important}
html.ptn-auth form > div{
  background:#fff!important;border:4px solid #111!important;border-radius:0!important;
  box-shadow:10px 10px 0 #111!important;position:relative;
}
html.ptn-auth form > div::before{
  content:"LOGIN";position:absolute;top:-18px;left:18px;padding:3px 12px;
  background:var(--ptn-yellow);border:3px solid #111;font:900 13px/1.4 var(--ptn-font);letter-spacing:.14em;color:#111;
}
html.ptn-auth h1,html.ptn-auth h2,html.ptn-auth h3{color:#111!important;font-weight:900!important;text-transform:uppercase;letter-spacing:-.01em}
html.ptn-auth label{color:#111!important;font-weight:800!important;text-transform:uppercase;font-size:12px!important;letter-spacing:.06em}
html.ptn-auth input:not([type=checkbox]):not([type=radio]){
  background:#fff!important;color:#111!important;border:3px solid #111!important;border-radius:0!important;
  box-shadow:4px 4px 0 #111!important;font-family:var(--ptn-font)!important;font-weight:600;
}
html.ptn-auth input:focus{outline:none!important;background:#FFFBD6!important;box-shadow:6px 6px 0 #111!important}
html.ptn-auth button[type=submit]{
  background:var(--ptn-yellow)!important;color:#111!important;border:3px solid #111!important;border-radius:0!important;
  box-shadow:5px 5px 0 #111!important;font:900 14px var(--ptn-font)!important;text-transform:uppercase;letter-spacing:.06em;
  transition:transform .08s,box-shadow .08s;
}
html.ptn-auth button[type=submit]:hover{transform:translate(-2px,-2px);box-shadow:8px 8px 0 #111!important;background:var(--ptn-pink)!important}
html.ptn-auth button[type=submit]:active{transform:translate(4px,4px);box-shadow:0 0 0 #111!important}
html.ptn-auth a{color:#111!important;font-weight:800;text-decoration:underline;text-decoration-thickness:3px;text-decoration-color:var(--ptn-yellow);text-underline-offset:3px}
html.ptn-auth a:hover{background:var(--ptn-yellow)}
html.ptn-auth p{color:#111!important}
html.ptn-auth img{filter:none}
/* header brand di halaman login */
#ptn-authbrand{
  position:fixed;top:0;left:0;right:0;height:64px;z-index:80;display:flex;align-items:center;padding:0 16px;
  background:var(--ptn-yellow);border-bottom:4px solid #111;font-family:var(--ptn-font);
}
#ptn-authbrand .ptn-logo{
  display:flex;align-items:center;gap:10px;padding:4px 14px;background:#fff;color:#111;text-decoration:none;
  border:3px solid #111;box-shadow:4px 4px 0 #111;font:900 22px var(--ptn-font);text-transform:uppercase;letter-spacing:-.02em;
}
#ptn-authbrand .ptn-logo i{font-size:20px}
CSS
}

theme_write_app() {
  cat > "$THEME_PUB/app.css" <<'CSS'
/* Neo Brutalism - dashboard utama (client area): shell baru + isi halaman */
html.ptn-app body{
  background-color:var(--ptn-bg)!important;
  background-image:radial-gradient(rgba(17,17,17,.12) 1.5px,transparent 1.5px);
  background-size:24px 24px;color:var(--ptn-ink);font-family:var(--ptn-font);
}
html.ptn-app #app{min-height:100vh}
html.ptn-app.ptn-has-sidebar #app{margin-left:280px;padding-top:64px}
html.ptn-app.ptn-has-sidebar .ptn-hide{display:none!important}
html.ptn-app h1,html.ptn-app h2,html.ptn-app h3{font-weight:900;text-transform:uppercase;letter-spacing:-.01em}

/* pewarnaan otomatis isi halaman (sidebar.js) */
html.ptn-app .ptn-s0{background:transparent!important}
html.ptn-app .ptn-s1{background:#fff!important;border:3px solid #111!important;box-shadow:5px 5px 0 #111!important;border-radius:0!important}
html.ptn-app .ptn-s2{background:var(--ptn-bg)!important;border:2px solid #111!important;border-radius:0!important;box-shadow:none!important}
html.ptn-app .ptn-accent{border:3px solid #111!important;box-shadow:3px 3px 0 #111!important;border-radius:0!important;filter:saturate(1.35)}
html.ptn-app .ptn-t{color:#111!important}
html.ptn-app button.ptn-s1,html.ptn-app button.ptn-s2,html.ptn-app a.ptn-s1,html.ptn-app a.ptn-s2{background:#fff!important;box-shadow:3px 3px 0 #111!important;font-weight:800}
html.ptn-app button.ptn-s1:hover,html.ptn-app button.ptn-s2:hover,html.ptn-app a.ptn-s1:hover,html.ptn-app a.ptn-s2:hover{background:var(--ptn-yellow)!important}
html.ptn-app button.ptn-accent,html.ptn-app a.ptn-accent{font-weight:800;transition:transform .08s,box-shadow .08s}
html.ptn-app button.ptn-accent:hover,html.ptn-app a.ptn-accent:hover{transform:translate(-2px,-2px);box-shadow:6px 6px 0 #111!important}
html.ptn-app button.ptn-accent:active{transform:translate(2px,2px);box-shadow:none!important}
html.ptn-app #app *{border-radius:0!important}
html.ptn-app input:not([type=checkbox]):not([type=radio]),html.ptn-app select,html.ptn-app textarea{
  background:#fff!important;color:#111!important;border:3px solid #111!important;
  box-shadow:3px 3px 0 #111!important;font-family:var(--ptn-font);
}
html.ptn-app input:focus,html.ptn-app select:focus,html.ptn-app textarea:focus{outline:none!important;background:#FFFBD6!important}
html.ptn-app table{border-collapse:separate;border-spacing:0}
html.ptn-app code,html.ptn-app pre,html.ptn-app .font-mono{font-family:var(--ptn-mono)}
html.ptn-app .xterm{border:3px solid #111}

/* header */
#ptn-header{
  position:fixed;top:0;left:0;right:0;height:64px;z-index:80;display:flex;align-items:center;gap:10px;padding:0 14px;
  background:var(--ptn-yellow);border-bottom:4px solid #111;font-family:var(--ptn-font);color:#111;
}
#ptn-header .ptn-logo{
  display:flex;align-items:center;gap:10px;padding:4px 14px;background:#fff;color:#111;text-decoration:none;
  border:3px solid #111;box-shadow:4px 4px 0 #111;font:900 22px var(--ptn-font);text-transform:uppercase;letter-spacing:-.02em;
  max-width:55vw;overflow:hidden;white-space:nowrap;
}
#ptn-header .ptn-logo i{font-size:20px}
#ptn-header .ptn-sp{flex:1}
#ptn-header .ptn-act{
  display:flex;align-items:center;gap:8px;padding:8px 14px;cursor:pointer;background:#fff;color:#111;
  border:3px solid #111;box-shadow:3px 3px 0 #111;font:800 13px var(--ptn-font);text-transform:uppercase;text-decoration:none;
  transition:transform .08s,box-shadow .08s,background .08s;
}
#ptn-header .ptn-act:hover{transform:translate(-2px,-2px);box-shadow:5px 5px 0 #111;background:var(--ptn-pink)}
#ptn-header .ptn-act.ptn-out{background:#111;color:var(--ptn-yellow)}
#ptn-header .ptn-act.ptn-out:hover{background:var(--ptn-pink);color:#111}
#ptn-burger{display:none}

/* sidebar */
#ptn-sidebar{
  position:fixed;top:64px;bottom:0;left:0;width:280px;z-index:60;display:flex;flex-direction:column;
  background:#fff;border-right:4px solid #111;overflow-y:auto;font-family:var(--ptn-font);color:#111;
}
#ptn-sidebar nav{display:flex;flex-direction:column;gap:10px;padding:16px;flex:1}
#ptn-sidebar .ptn-label{
  margin:10px 0 0;padding:3px 10px;font-size:11px;font-weight:900;letter-spacing:.14em;text-transform:uppercase;
  background:#111;color:var(--ptn-yellow);align-self:flex-start;
}
#ptn-sidebar a{
  display:flex;align-items:center;gap:12px;width:100%;padding:11px 14px;text-align:left;cursor:pointer;
  background:#fff;color:#111;border:3px solid #111;box-shadow:4px 4px 0 #111;
  font:800 13px var(--ptn-font);text-transform:uppercase;letter-spacing:.03em;text-decoration:none;
  transition:transform .08s,box-shadow .08s,background .08s;
}
#ptn-sidebar a i{width:20px;text-align:center;font-size:15px}
#ptn-sidebar a:hover{transform:translate(-2px,-2px);box-shadow:6px 6px 0 #111;background:var(--ptn-yellow)}
#ptn-sidebar a.ptn-active{background:var(--ptn-pink);transform:translate(2px,2px);box-shadow:2px 2px 0 #111}

@media (max-width:960px){
  html.ptn-app.ptn-has-sidebar #app{margin-left:0}
  #ptn-sidebar{transform:translateX(-102%);transition:transform .2s}
  html.ptn-open #ptn-sidebar{transform:none}
  #ptn-burger{display:flex}
  #ptn-header .ptn-act span{display:none}
}
CSS
}

theme_write_sidebar_js() {
  cat > "$THEME_PUB/sidebar.js" <<'JS'
/* Neo Brutalism - header + sidebar baru, ikon Font Awesome, pewarnaan isi halaman (tanpa build ulang) */
(function () {
  'use strict';
  if (window.__ptnTheme) { return; }
  window.__ptnTheme = true;

  var CFG = window.__PTN || { brand: 'Pterodactyl', logo: '', login: true, app: true };
  var root = document.documentElement;
  var sigCache = '';
  var adminSeen = false;

  function isAuth() { return location.pathname.indexOf('/auth') === 0; }
  function syncMode() {
    root.classList.toggle('ptn-auth', isAuth());
    root.classList.toggle('ptn-app', !isAuth());
  }
  function mk(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) { e.className = cls; }
    if (text != null) { e.textContent = text; }
    return e;
  }
  function ic(cls) { var i = mk('i', cls); i.setAttribute('aria-hidden', 'true'); return i; }
  function go(href) {
    if (/^\/(admin|auth)(\/|$)/.test(href)) { location.href = href; return; }
    if (href === location.pathname) { return; }
    history.pushState({}, '', href);
    window.dispatchEvent(new PopStateEvent('popstate', { state: {} }));
  }
  function logout() {
    var m = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]+)/);
    fetch('/auth/logout', {
      method: 'POST', credentials: 'same-origin',
      headers: { 'X-XSRF-TOKEN': m ? decodeURIComponent(m[1]) : '', 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'application/json' }
    }).then(function () {}, function () {}).then(function () { location.href = '/auth/login'; });
  }

  /* ---------------------------------------------------------- brand */
  function brandLink() {
    var a = mk('a', 'ptn-logo');
    a.href = '/';
    if (CFG.logo) {
      var im = mk('img'); im.src = CFG.logo; im.alt = ''; a.appendChild(im);
    } else {
      a.appendChild(ic('fa-solid fa-dragon'));
    }
    a.appendChild(mk('span', 'ptn-name', CFG.brand || 'Pterodactyl'));
    return a;
  }

  /* ------------------------------------------------ navigasi server */
  var ICONS = {
    '': 'fa-solid fa-terminal', files: 'fa-regular fa-folder-open', databases: 'fa-solid fa-database',
    schedules: 'fa-regular fa-clock', users: 'fa-solid fa-users', backups: 'fa-regular fa-floppy-disk',
    network: 'fa-solid fa-network-wired', startup: 'fa-solid fa-play', settings: 'fa-solid fa-gear',
    activity: 'fa-solid fa-clock-rotate-left'
  };
  function topBar() {
    var l = document.getElementById('logo');
    var bar = l && l.parentElement && l.parentElement.parentElement;
    if (!bar || (bar.innerText || '').length > 400 || bar.querySelector('input,textarea')) { return null; }
    return bar;
  }
  function serverNav() {
    var m = location.pathname.match(/^\/server\/([^\/]+)/);
    if (!m) { return { id: null, items: [], bar: null }; }
    var base = '/server/' + m[1], groups = [];
    [].forEach.call(document.querySelectorAll('a[href^="' + base + '"]'), function (a) {
      if (a.closest('#ptn-sidebar,#ptn-header')) { return; }
      var h = a.getAttribute('href');
      if (h !== base && h.indexOf(base + '/') !== 0) { return; }
      var g = null;
      groups.forEach(function (x) { if (x.p === a.parentElement) { g = x; } });
      if (!g) { g = { p: a.parentElement, arr: [] }; groups.push(g); }
      g.arr.push(a);
    });
    var best = null;
    groups.forEach(function (g) { if (!best || g.arr.length > best.arr.length) { best = g; } });
    if (!best || best.arr.length < 3) { return { id: m[1], items: [], bar: null }; }
    var seen = {}, items = [];
    best.arr.forEach(function (a) {
      var h = a.getAttribute('href'), t = (a.textContent || '').trim();
      var k = h === base ? '' : h.slice(base.length + 1).split('/')[0];
      if (t && !seen[h]) { seen[h] = 1; items.push({ href: h, label: t, icon: ICONS[k] || 'fa-solid fa-circle' }); }
    });
    var bar = best.p.parentElement;
    if (!bar || (bar.innerText || '').length > 400 || bar.querySelector('input,textarea,table')) { bar = null; }
    return { id: m[1], items: items, bar: bar };
  }
  function addLink(parent, it) {
    var a = mk('a');
    a.href = it.href;
    a.appendChild(ic(it.icon));
    a.appendChild(mk('span', '', it.label));
    a.addEventListener('click', function (e) {
      if (e.ctrlKey || e.metaKey || e.shiftKey || e.button === 1) { return; }
      e.preventDefault();
      root.classList.remove('ptn-open');
      go(it.href);
    });
    parent.appendChild(a);
  }
  function actLink(href, icon, label, admin) {
    var a = mk('a', 'ptn-act');
    a.href = href;
    a.appendChild(ic(icon));
    a.appendChild(mk('span', '', label));
    a.addEventListener('click', function (e) {
      if (e.ctrlKey || e.metaKey || e.shiftKey || e.button === 1 || admin) { return; }
      e.preventDefault();
      go(href);
    });
    return a;
  }
  function buildHeader() {
    var old = document.getElementById('ptn-header');
    if (old) { old.remove(); }
    var h = mk('header');
    h.id = 'ptn-header';
    var b = mk('button', 'ptn-act');
    b.id = 'ptn-burger'; b.type = 'button';
    b.appendChild(ic('fa-solid fa-bars'));
    b.addEventListener('click', function () { root.classList.toggle('ptn-open'); });
    h.appendChild(b);
    h.appendChild(brandLink());
    h.appendChild(mk('div', 'ptn-sp'));
    h.appendChild(actLink('/account', 'fa-regular fa-circle-user', 'Account', false));
    if (adminSeen) { h.appendChild(actLink('/admin', 'fa-solid fa-screwdriver-wrench', 'Admin', true)); }
    var out = mk('button', 'ptn-act ptn-out');
    out.type = 'button';
    out.appendChild(ic('fa-solid fa-right-from-bracket'));
    out.appendChild(mk('span', '', 'Logout'));
    out.addEventListener('click', logout);
    h.appendChild(out);
    document.body.appendChild(h);
  }
  function buildSidebar(srv) {
    var old = document.getElementById('ptn-sidebar');
    if (old) { old.remove(); }
    var aside = mk('aside');
    aside.id = 'ptn-sidebar';
    var nav = mk('nav');
    nav.appendChild(mk('div', 'ptn-label', 'Menu'));
    var main = [
      { href: '/', label: 'Dashboard', icon: 'fa-solid fa-house' },
      { href: '/account', label: 'Account', icon: 'fa-regular fa-user' },
      { href: '/account/api', label: 'API Credentials', icon: 'fa-solid fa-key' },
      { href: '/account/ssh', label: 'SSH Keys', icon: 'fa-solid fa-lock' }
    ];
    if (adminSeen) { main.push({ href: '/admin', label: 'Admin Panel', icon: 'fa-solid fa-screwdriver-wrench' }); }
    main.forEach(function (it) { addLink(nav, it); });
    if (srv.items.length) {
      nav.appendChild(mk('div', 'ptn-label', 'Server'));
      srv.items.forEach(function (it) { addLink(nav, it); });
    }
    aside.appendChild(nav);
    document.body.appendChild(aside);
  }
  function markActive() {
    var links = document.querySelectorAll('#ptn-sidebar nav a'), best = null, bestLen = -1, p = location.pathname.replace(/\/+$/, '') || '/';
    [].forEach.call(links, function (a) {
      a.classList.remove('ptn-active');
      var h = a.getAttribute('href').replace(/\/+$/, '') || '/';
      var hit = h === p || (h !== '/' && p.indexOf(h + '/') === 0);
      if (hit && h.length > bestLen) { best = a; bestLen = h.length; }
    });
    if (best) { best.classList.add('ptn-active'); }
  }
  function removeShell() {
    ['ptn-sidebar', 'ptn-header'].forEach(function (id) {
      var e = document.getElementById(id);
      if (e) { e.remove(); }
    });
    root.classList.remove('ptn-has-sidebar', 'ptn-open');
  }
  function render() {
    syncMode();
    if (isAuth()) {
      removeShell();
      var ab = document.getElementById('ptn-authbrand');
      if (CFG.login) {
        if (!ab) {
          ab = mk('div'); ab.id = 'ptn-authbrand';
          ab.appendChild(brandLink());
          document.body.appendChild(ab);
        }
      } else if (ab) { ab.remove(); }
      return;
    }
    var ab2 = document.getElementById('ptn-authbrand');
    if (ab2) { ab2.remove(); }
    if (!CFG.app) { return; }
    var hasShell = !!document.getElementById('ptn-sidebar');
    if (!document.getElementById('logo') && !hasShell) { return; }
    if (document.querySelector('a[href="/admin"]:not(#ptn-sidebar a):not(#ptn-header a)')) { adminSeen = true; }
    var srv = serverNav();
    var sig = JSON.stringify([adminSeen, srv.id, srv.items]);
    if (!hasShell || sig !== sigCache) { buildHeader(); buildSidebar(srv); sigCache = sig; }
    var tb = topBar();
    if (tb) { tb.classList.add('ptn-hide'); }
    if (srv.bar) { srv.bar.classList.add('ptn-hide'); }
    root.classList.add('ptn-has-sidebar');
    markActive();
  }
  var timer = null;
  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(render, 120);
  }

  /* --------------------------------------- pewarnaan otomatis ke Neo Brutalism */
  function parse(c) {
    var m = c && c.match(/rgba?\(([^)]+)\)/);
    if (!m) { return null; }
    var p = m[1].split(/[ ,\/]+/).filter(Boolean).map(parseFloat);
    return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
  }
  function lum(c) {
    var a = [c.r, c.g, c.b].map(function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
    return 0.2126 * a[0] + 0.7152 * a[1] + 0.0722 * a[2];
  }
  function sat(c) {
    var mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b);
    return mx === 0 ? 0 : (mx - mn) / mx;
  }
  var seen = new WeakSet();
  function paint(el) {
    if (el.nodeType !== 1 || seen.has(el)) { return; }
    seen.add(el);
    if (el.closest('svg,canvas,.xterm,#ptn-sidebar,#ptn-header,#ptn-authbrand,.ptn-keep,script,style,img,video,iframe')) { return; }
    var cs = getComputedStyle(el);
    var bg = parse(cs.backgroundColor);
    if (bg && bg.a > 0.95) {
      var l = lum(bg), s = sat(bg);
      if (s < 0.28 && l < 0.5) {
        var r = el.getBoundingClientRect();
        var big = r.width > innerWidth * 0.85 && r.height > innerHeight * 0.5;
        var inner = el.parentElement && el.parentElement.closest('.ptn-s1');
        el.classList.add(big ? 'ptn-s0' : (inner ? 'ptn-s2' : 'ptn-s1'));
      } else if (s >= 0.28) {
        el.classList.add('ptn-accent');
      }
    }
    var c = parse(cs.color);
    if (c && lum(c) > 0.55 && !el.closest('.ptn-accent')) { el.classList.add('ptn-t'); }
  }
  var queue = [], qi = 0, pending = false;
  function flush() {
    pending = false;
    if (isAuth() || !CFG.app) { queue = []; qi = 0; return; }
    var n = 0;
    while (qi < queue.length && n < 400) { paint(queue[qi++]); n++; }
    if (qi < queue.length) { pending = true; requestAnimationFrame(flush); } else { queue = []; qi = 0; }
  }
  function enqueue(node) {
    if (node.nodeType !== 1) { return; }
    queue.push(node);
    var all = node.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) { queue.push(all[i]); }
    if (!pending) { pending = true; requestAnimationFrame(flush); }
  }

  /* ------------------------------------------------------------- start */
  ['pushState', 'replaceState'].forEach(function (k) {
    var o = history[k];
    history[k] = function () {
      var r = o.apply(this, arguments);
      window.dispatchEvent(new Event('ptn:nav'));
      return r;
    };
  });
  window.addEventListener('popstate', schedule);
  window.addEventListener('ptn:nav', schedule);

  function start() {
    syncMode();
    new MutationObserver(function (muts) {
      muts.forEach(function (m) { [].forEach.call(m.addedNodes, enqueue); });
      schedule();
    }).observe(document.body, { childList: true, subtree: true });
    enqueue(document.body);
    schedule();
  }
  if (document.body) { start(); } else { document.addEventListener('DOMContentLoaded', start); }
})();
JS
}

theme_write_admin_js() {
  cat > "$THEME_PUB/admin.js" <<'JS'
/* Neo Brutalism - header admin: logo + nama brand custom */
(function () {
  'use strict';
  var C = window.__PTN || { brand: 'Pterodactyl', logo: '' };
  function mk(t, c, x) { var e = document.createElement(t); if (c) { e.className = c; } if (x != null) { e.textContent = x; } return e; }
  function run() {
    var l = document.querySelector('.main-header .logo');
    if (!l) { return; }
    l.textContent = '';
    l.href = '/admin';
    var lg = mk('span', 'logo-lg ptn-logo'), mini = mk('span', 'logo-mini ptn-logo');
    if (C.logo) {
      [lg, mini].forEach(function (s) { var i = mk('img'); i.src = C.logo; i.alt = ''; s.appendChild(i); });
    } else {
      [lg, mini].forEach(function (s) { var i = mk('i', 'fa-solid fa-dragon'); s.appendChild(i); });
    }
    lg.appendChild(mk('span', 'ptn-name', C.brand || 'Pterodactyl'));
    l.appendChild(lg);
    l.appendChild(mini);
  }
  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', run); } else { run(); }
})();
JS
}

theme_write_admin() {
  cat > "$THEME_PUB/admin.css" <<'CSS'
/* Neo Brutalism - panel admin (AdminLTE) */
body.skin-blue,.skin-blue .wrapper,.skin-blue .content-wrapper,.skin-blue .right-side{
  background-color:var(--ptn-bg)!important;font-family:var(--ptn-font)!important;color:#111;
}
.skin-blue .content-wrapper{background-image:radial-gradient(rgba(17,17,17,.12) 1.5px,transparent 1.5px);background-size:24px 24px}
.skin-blue .main-header .logo{
  background:var(--ptn-yellow)!important;color:#111!important;border-right:4px solid #111;border-bottom:4px solid #111;
  font-family:var(--ptn-font)!important;font-weight:900;text-transform:uppercase;letter-spacing:-.02em;
}
.skin-blue .main-header .logo .ptn-logo{display:inline-flex;align-items:center;gap:8px;justify-content:center;width:100%;line-height:50px}
.skin-blue .main-header .logo .ptn-logo img{max-height:30px;width:auto}
.skin-blue .main-header .navbar{background:var(--ptn-yellow)!important;border-bottom:4px solid #111}
.skin-blue .main-header .navbar .nav>li>a,.skin-blue .main-header .navbar .sidebar-toggle{color:#111!important;font-weight:800}
.skin-blue .main-header .navbar .nav>li>a:hover,.skin-blue .main-header .navbar .sidebar-toggle:hover{background:var(--ptn-pink)!important}
.skin-blue .main-sidebar,.skin-blue .left-side{background:#fff!important;border-right:4px solid #111}
.skin-blue .sidebar-menu>li.header{background:#111!important;color:var(--ptn-yellow)!important;font-weight:900;letter-spacing:.14em}
.skin-blue .sidebar-menu>li>a{color:#111!important;font-weight:800;text-transform:uppercase;font-size:12px;border:3px solid transparent;margin:3px 10px;border-radius:0}
.skin-blue .sidebar-menu>li:hover>a,.skin-blue .sidebar-menu>li.active>a{background:var(--ptn-pink)!important;color:#111!important;border:3px solid #111;box-shadow:4px 4px 0 #111}
.skin-blue .sidebar-menu>li>.treeview-menu{background:var(--ptn-bg)!important;margin:0 10px;border:3px solid #111;border-top:0}
.skin-blue .sidebar-menu .treeview-menu>li>a{color:#111!important;font-weight:700}
.skin-blue .sidebar-menu .treeview-menu>li.active>a,.skin-blue .sidebar-menu .treeview-menu>li>a:hover{background:var(--ptn-yellow)!important;color:#111!important}
.content-header>h1{font-weight:900;text-transform:uppercase;letter-spacing:-.02em}
.content-header>h1>small{color:#111;font-weight:700}
.content-header>.breadcrumb>li>a{color:#111}
.box,.small-box,.info-box{background:#fff!important;border:3px solid #111!important;border-top:3px solid #111!important;border-radius:0!important;box-shadow:6px 6px 0 #111!important}
.box-header{border-bottom:3px solid #111;background:var(--ptn-yellow)}
.box-header .box-title{font-weight:900;text-transform:uppercase;color:#111}
.box-footer{border-top:3px solid #111;background:var(--ptn-bg)}
.small-box>.small-box-footer{background:#111!important;color:var(--ptn-yellow)!important;font-weight:800}
.btn{border:3px solid #111!important;border-radius:0!important;box-shadow:3px 3px 0 #111;font-weight:800;text-transform:uppercase;transition:transform .08s,box-shadow .08s}
.btn:hover{transform:translate(-2px,-2px);box-shadow:6px 6px 0 #111}
.btn:active{transform:translate(2px,2px);box-shadow:none}
.btn-primary{background:var(--ptn-blue)!important;color:#fff!important}
.btn-success{background:var(--ptn-green)!important;color:#111!important}
.btn-danger{background:var(--ptn-pink)!important;color:#111!important}
.btn-warning{background:var(--ptn-orange)!important;color:#111!important}
.btn-default,.btn-info{background:#fff!important;color:#111!important}
.form-control,.select2-container--default .select2-selection--single,.select2-container--default .select2-selection--multiple{
  border:3px solid #111!important;border-radius:0!important;box-shadow:none!important;background:#fff;color:#111;font-weight:600;
}
.form-control:focus{background:#FFFBD6;box-shadow:4px 4px 0 #111!important}
.input-group-addon{border:3px solid #111!important;border-radius:0!important;background:var(--ptn-yellow);color:#111;font-weight:800}
.table>thead>tr>th{background:#111;color:var(--ptn-yellow);border-bottom:3px solid #111;text-transform:uppercase;font-weight:900;font-size:12px;letter-spacing:.06em}
.table>tbody>tr>td{border-top:2px solid #111!important}
.table-hover>tbody>tr:hover{background:var(--ptn-yellow)!important}
.label,.badge{border:2px solid #111;border-radius:0!important;color:#111!important;font-weight:800}
.label-success{background:var(--ptn-green)!important}.label-danger{background:var(--ptn-pink)!important}
.label-warning{background:var(--ptn-orange)!important}.label-primary,.label-info{background:var(--ptn-blue)!important;color:#fff!important}
.label-default{background:#fff!important}
.callout,.alert{border:3px solid #111!important;border-left-width:10px!important;border-radius:0!important;color:#111!important;font-weight:600}
.alert-success,.callout-success{background:var(--ptn-green)!important}
.alert-danger,.callout-danger{background:var(--ptn-pink)!important}
.alert-warning,.callout-warning{background:var(--ptn-orange)!important}
.alert-info,.callout-info{background:var(--ptn-blue)!important;color:#fff!important}
.modal-content{border:4px solid #111!important;border-radius:0!important;box-shadow:10px 10px 0 #111!important}
.modal-header{background:var(--ptn-yellow);border-bottom:3px solid #111}
.modal-footer{border-top:3px solid #111;background:var(--ptn-bg)}
.nav-tabs-custom{border:3px solid #111;border-radius:0;box-shadow:6px 6px 0 #111}
.nav-tabs-custom>.nav-tabs>li.active{border-top-color:#111}
.nav-tabs-custom>.nav-tabs>li>a{font-weight:800;text-transform:uppercase;color:#111}
.pagination>li>a,.pagination>li>span{border:2px solid #111!important;border-radius:0!important;color:#111;font-weight:800}
.pagination>.active>a,.pagination>.active>span{background:var(--ptn-pink)!important;color:#111!important}
.main-footer{background:#111!important;color:var(--ptn-yellow)!important;border-top:4px solid #111}
.main-footer a{color:var(--ptn-pink)!important}
CSS
}

theme_begin() {
  mkdir -p "$THEME_PUB" "$THEME_DIR"
  [[ -f "$THEME_CFG" ]] || theme_set brand str "Pterodactyl"
  theme_write_base
  theme_write_sidebar_js
  theme_write_partial
  theme_inject_all
}
theme_end() {
  chmod -R a+rX "$THEME_PUB" 2>/dev/null || true
  chown -R "$OWNER:$OWNER" "$THEME_PUB" "$THEME_DIR" 2>/dev/null || true
  post_steps
  info "Selesai. Tekan Ctrl+F5 di browser untuk memuat tema baru."
}

install_theme_login() { theme_begin; theme_write_login; theme_set login bool true; theme_end; info "Tampilan Login terpasang."; }
install_theme_app()   { theme_begin; theme_write_app;   theme_set app bool true;   theme_end; info "Tampilan Dashboard Server (header + sidebar baru) terpasang."; }
install_theme_admin() { theme_begin; theme_write_admin; theme_write_admin_js; theme_set admin bool true; theme_end; info "Tampilan Dashboard Admin terpasang."; }

# Nama + logo header. Logo: URL http(s), path web (/xx.png) atau file lokal di VPS (disalin ke public/protect-theme).
install_brand() {
  mkdir -p "$THEME_PUB" "$THEME_DIR"
  local name="${BRAND_NAME-}" logo="${BRAND_LOGO-}" cur_n cur_l ext
  cur_n="$(theme_get brand Pterodactyl)"; cur_l="$(theme_get logo '')"
  if [[ -z "${BRAND_NAME+x}" ]]; then
    read -r -p "Nama header [Enter = $cur_n]: " name || true
  fi
  if [[ -z "${BRAND_LOGO+x}" ]]; then
    read -r -p "Logo (URL / path file) [Enter = tetap${cur_l:+ ($cur_l)}, 'hapus' = ikon bawaan]: " logo || true
  fi
  name="${name//[[:cntrl:]]/}"; name="${name:0:40}"
  [[ -n "$name" ]] || name="$cur_n"
  theme_set brand str "$name"
  if [[ "${logo,,}" == "hapus" ]]; then
    rm -f "$THEME_PUB"/logo.* 2>/dev/null || true
    theme_set logo str ""
  elif [[ -n "$logo" ]]; then
    if [[ "$logo" =~ ^https?://[A-Za-z0-9._~:/?#@!\&\(\)*+,\;=%-]+$ ]]; then
      theme_set logo str "$logo"
    elif [[ -f "$logo" ]]; then
      ext="${logo##*.}"; ext="${ext,,}"
      [[ "$ext" =~ ^(png|jpg|jpeg|svg|webp|gif|ico)$ ]] || die "Format logo harus png/jpg/jpeg/svg/webp/gif/ico."
      rm -f "$THEME_PUB"/logo.* 2>/dev/null || true
      cp "$logo" "$THEME_PUB/logo.$ext"
      theme_set logo str "/protect-theme/logo.$ext"
    elif [[ "$logo" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
      theme_set logo str "$logo"
    else
      die "Logo tidak valid: gunakan URL http(s), path web (/logo.png), atau file lokal yang ada."
    fi
  fi
  theme_write_partial
  theme_end
  info "Header: nama '$(theme_get brand)' logo '$(theme_get logo '(ikon bawaan)')'."
}

theme_menu() {
  local t
  while true; do
    echo "---------- Install Theme (Neo Brutalism) ----------"
    echo " 1) Install Tampilan Login"
    echo " 2) Install Tampilan Dashboard Server (Dashboard Utama)"
    echo " 3) Install Tampilan Dashboard Admin"
    echo " 4) Atur Logo & Nama Header"
    echo " 0) Selesai"
    read -r -p "Pilih [0-4]: " t || true
    case "${t:-0}" in
      1) install_theme_login ;;
      2) install_theme_app ;;
      3) install_theme_admin ;;
      4) install_brand ;;
      *) break ;;
    esac
  done
}

theme_uninstall() {
  [[ -f "$THEME_CFG" || -d "$THEME_PUB" ]] || die "Tema belum terpasang."
  local f
  for f in "$THEME_WRAPPER_VIEW" "$THEME_CORE_VIEW" "$THEME_ADMIN_VIEW"; do theme_strip "$f"; done
  rm -rf "$THEME_PUB" "$THEME_DIR" "$THEME_PARTIAL"
  post_steps
  info "Tema dihapus, tampilan bawaan panel dikembalikan."
}

# ------------------------------------------------------------------- menu ---
if [[ "$ACTION" == "menu" ]]; then
  echo "========== Pterodactyl Protect =========="
  echo " 1) Install Protect"
  echo " 2) Uninstall Protect"
  echo " 3) Install Theme   (Login, Dashboard Server/Utama, Dashboard Admin, Logo & Nama)"
  echo " 4) Uninstall Theme"
  echo " 5) Atur Logo & Nama Header"
  echo " 0) Exit"
  read -r -p "Pilih [0-5]: " choice || true
  case "${choice:-0}" in
    1) ACTION="install" ;;
    2) ACTION="uninstall" ;;
    3) ACTION="theme" ;;
    4) ACTION="theme-uninstall" ;;
    5) ACTION="theme-brand" ;;
    *) exit 0 ;;
  esac
fi
case "$ACTION" in
  install|1)         ACTION="install" ;;
  uninstall|2)       ACTION="uninstall" ;;
  theme|3)           ACTION="theme" ;;
  theme-uninstall|4) ACTION="theme-uninstall" ;;
  theme-login|theme-app|theme-admin|theme-all|theme-brand) ;;
  *) die "Pilihan tidak dikenal: $ACTION (pakai: install | uninstall | theme | theme-uninstall | theme-login | theme-app | theme-admin | theme-all | theme-brand)" ;;
esac
case "$ACTION" in
  uninstall)       uninstall_protect ;;
  theme)           theme_menu; exit 0 ;;
  theme-login)     install_theme_login; exit 0 ;;
  theme-app)       install_theme_app; exit 0 ;;
  theme-admin)     install_theme_admin; exit 0 ;;
  theme-all)       install_theme_login; install_theme_app; install_theme_admin; exit 0 ;;
  theme-brand)     install_brand; exit 0 ;;
  theme-uninstall) theme_uninstall; exit 0 ;;
esac

# ------------------------------------------------------------- input config ---
SUPPORT_URL="${SUPPORT_URL:-}"
OLD_SUPPORT=""
if [[ -f "$PROTECT_DIR/config.json" ]]; then
  OLD_SUPPORT="$(grep -o '"support_url":"[^"]*"' "$PROTECT_DIR/config.json" | cut -d'"' -f4 || true)"
fi
if [[ -z "$SUPPORT_URL" ]]; then
  read -r -p "Link contact support (https://t.me/username)${OLD_SUPPORT:+ [Enter = pakai $OLD_SUPPORT]}: " SUPPORT_URL || true
  SUPPORT_URL="${SUPPORT_URL:-$OLD_SUPPORT}"
fi
url_re='^https?://[A-Za-z0-9._~:/?#@!&()*+,;=%-]+$'
if [[ -n "$SUPPORT_URL" && ! "$SUPPORT_URL" =~ $url_re ]]; then
  die "Link support tidak valid (harus diawali http:// atau https://)."
fi

mkdir -p "$PROTECT_DIR" "$BK"
printf '{"support_url":"%s"}\n' "$SUPPORT_URL" > "$PROTECT_DIR/config.json"
# Sisa fitur whitelist IP versi lama dibersihkan (tidak dipakai lagi)
rm -f "$PROTECT_DIR"/{panel_ips.txt,allowed_ips.txt,trusted_proxies.txt,real_ip_header.txt,disable_ip_lock,local_networks.txt}

# ------------------------------------------------------ 1. kelas proteksi ---
info "Membuat app/Http/Middleware/Protect/PanelProtect.php"
write_file "$PANEL_DIR/app/Http/Middleware/Protect/PanelProtect.php" <<'PHP'
<?php

namespace Pterodactyl\Http\Middleware\Protect;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Pterodactyl\Models\ApiKey;
use Pterodactyl\Models\Server;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

class PanelProtect
{
    /** ID user owner: satu-satunya yang punya akses penuh. */
    public const OWNER_ID = 1;

    /** Bagian admin / Application API yang hanya boleh dipakai owner. */
    public const OWNER_ONLY_SECTIONS = ['nodes', 'locations', 'nests', 'settings'];

    /** Dipanggil dari AdminAuthenticate (semua halaman /admin). */
    public static function admin(Request $request): void
    {
        $user = $request->user();
        if (!$user) {
            return;
        }

        $seg = $request->segments(); // [admin, section, ...]

        // Berlaku untuk semua admin (termasuk owner): key ptla milik admin lain tidak boleh disentuh.
        self::guardApiKeys($request, $user, $seg);

        if ((int) $user->id === self::OWNER_ID) {
            return;
        }

        $section = $seg[1] ?? '';
        $method = strtoupper($request->method());

        if (in_array($section, self::OWNER_ONLY_SECTIONS, true)) {
            self::deny($request, 'Halaman ini hanya bisa diakses oleh owner panel.');
        }

        // Yang ditolak hanya menghapus server milik orang lain.
        if ($section === 'servers' && ($seg[2] ?? '') === 'view' && isset($seg[3]) && ctype_digit($seg[3])
            && ($seg[4] ?? '') === 'delete') {
            $server = Server::query()->find((int) $seg[3]);
            if ($server && (int) $server->owner_id !== (int) $user->id) {
                self::deny($request, 'Kamu tidak boleh menghapus server milik orang lain.');
            }
        }

        // Hanya owner (id 1) yang boleh membuat / menjadikan user dengan role admin.
        if ($section === 'users' && in_array($method, ['POST', 'PATCH', 'PUT'], true)
            && $request->boolean('root_admin')) {
            self::deny($request, 'Hanya owner panel yang bisa membuat atau menjadikan user admin.');
        }

        // Admin utama (id 1): tidak boleh diedit / dihapus.
        if ($section === 'users' && ($seg[2] ?? '') === 'view'
            && (int) ($seg[3] ?? 0) === self::OWNER_ID && $method !== 'GET') {
            self::deny($request, 'Akun owner panel tidak boleh diedit atau dihapus.');
        }
    }

    /** Dashboard server: hanya owner panel (id 1), pemilik server, dan subuser sah. */
    public static function clientServer(Request $request): void
    {
        $user = $request->user();
        if (!$user || (int) $user->id === self::OWNER_ID) {
            return;
        }

        $server = $request->route('server');
        if (!$server instanceof Server) {
            return;
        }

        if ((int) $server->owner_id === (int) $user->id) {
            return;
        }

        if ($server->subusers()->where('user_id', $user->id)->exists()) {
            return;
        }

        self::deny($request, 'Server ini hanya bisa dibuka oleh owner panel dan pemilik server.');
    }

    /** Daftar server di dashboard: mode "lihat semua server" hanya untuk id 1. */
    public static function clientList(Request $request): void
    {
        $user = $request->user();
        if (!$user || (int) $user->id === self::OWNER_ID) {
            return;
        }

        $seg = $request->segments();
        if (($seg[0] ?? '') === 'api' && ($seg[1] ?? '') === 'client' && count($seg) === 2
            && in_array((string) $request->query('type'), ['admin', 'admin-all'], true)) {
            self::deny($request, 'Melihat semua server hanya untuk owner panel.');
        }
    }

    /** Application API key (ptla): hanya pemilik key yang boleh mencabut/mengelolanya. */
    private static function guardApiKeys(Request $request, $user, array $seg): void
    {
        if (($seg[1] ?? '') !== 'api' || ($seg[2] ?? '') !== 'revoke' || empty($seg[3])) {
            return;
        }

        $id = (string) $seg[3];
        $ids = array_values(array_unique([$id, preg_replace('/^ptl[ac]_/', '', $id)]));
        $key = ApiKey::query()->whereIn('identifier', $ids)->first();

        if ($key && (int) $key->user_id !== (int) $user->id) {
            self::deny($request, 'Application API key milik admin lain tidak bisa diakses.');
        }
    }

    /** Dipanggil dari AuthenticateApplicationUser (semua /api/application). Tanpa batas IP. */
    public static function api(Request $request): void
    {
        $path = $request->segments();
        if (($path[0] ?? '') !== 'api' || ($path[1] ?? '') !== 'application') {
            return;
        }

        // Pemilik API key harus admin panel / owner.
        $user = $request->user();
        if (!$user) {
            $apiKey = $request->attributes->get('api_key');
            $user = $apiKey ? $apiKey->user : null;
        }
        if (!$user || !$user->root_admin) {
            self::deny($request, 'Hanya admin panel yang boleh memakai Application API.');
        }

        if ((int) $user->id === self::OWNER_ID) {
            return;
        }

        $seg = $request->segments(); // [api, application, section, id, ...]
        $section = $seg[2] ?? '';
        $target = $seg[3] ?? null;
        $method = strtoupper($request->method());

        if ($section === 'users' && in_array($method, ['POST', 'PATCH', 'PUT'], true)
            && $request->boolean('root_admin')) {
            self::deny($request, 'Hanya owner panel yang bisa membuat atau menjadikan user admin.');
        }

        if ($section === 'users' && (int) $target === self::OWNER_ID && $method !== 'GET') {
            self::deny($request, 'Akun owner panel tidak boleh diedit atau dihapus.');
        }
    }

    private static function deny(Request $request, string $message): void
    {
        Log::warning('[protect] ' . $message, [
            'user' => optional($request->user())->id,
            'ip' => $request->ip(),
            'method' => $request->method(),
            'path' => $request->path(),
        ]);

        throw new AccessDeniedHttpException($message);
    }
}
PHP

# ------------------------------------------- 2. patch middleware existing ---
patch_before_return() { # file, php-call
  local f="$1" call="$2"
  [[ -f "$f" ]] || die "File tidak ditemukan: $f (versi panel tidak didukung?)"
  if grep -q 'PanelProtect' "$f"; then info "Sudah dipatch: $(rel_of "$f")"; return; fi
  backup "$f"
  CALL="$call" perl -0pi -e 's/(\n[ \t]*)(return \$next\(\$request\);)/$1.$ENV{CALL}.$1.$2/e' "$f"
  grep -q 'PanelProtect' "$f" || die "Gagal patch $(rel_of "$f")"
  info "Patch: $(rel_of "$f")"
}

patch_before_return "$PANEL_DIR/app/Http/Middleware/AdminAuthenticate.php" \
  '\Pterodactyl\Http\Middleware\Protect\PanelProtect::admin($request);'
patch_handle_start() { # file, php-call (disisipkan di awal method handle)
  local f="$1" call="$2"
  if grep -q 'PanelProtect' "$f"; then info "Sudah dipatch: $(rel_of "$f")"; return; fi
  backup "$f"
  CALL="$call" perl -0pi -e 's/(public function handle\([^)]*\)[^{]*\{)/$1."\n        ".$ENV{CALL}/e' "$f"
  grep -q 'PanelProtect' "$f" || die "Gagal patch $(rel_of "$f")"
  info "Patch: $(rel_of "$f")"
}

API_MW=""
for cand in \
  app/Http/Middleware/Api/AuthenticateApplicationUser.php \
  app/Http/Middleware/Api/AuthenticateIPAccess.php; do
  if [[ -f "$PANEL_DIR/$cand" ]] && grep -q 'public function handle' "$PANEL_DIR/$cand"; then
    API_MW="$PANEL_DIR/$cand"; break
  fi
done
if [[ -z "$API_MW" ]]; then
  warn "Isi folder app/Http/Middleware/Api:"; ls "$PANEL_DIR/app/Http/Middleware/Api" 2>/dev/null | sed 's/^/    /' || true
  die "Middleware Application API tidak ditemukan (versi panel tidak didukung?)"
fi
patch_handle_start "$API_MW" '\Pterodactyl\Http\Middleware\Protect\PanelProtect::api($request);'

PATCHED_PHP=()
patch_optional() { # path-relatif, php-call, label
  local f="$PANEL_DIR/$1"
  if [[ -f "$f" ]] && grep -q 'public function handle' "$f"; then
    patch_handle_start "$f" "$2"; PATCHED_PHP+=("$f")
  else
    warn "Tidak ditemukan: $1 ($3 belum terproteksi)"
  fi
}
patch_optional app/Http/Middleware/Api/Client/Server/AuthenticateServerAccess.php \
  '\Pterodactyl\Http\Middleware\Protect\PanelProtect::clientServer($request);' "Dashboard server"
patch_optional app/Http/Middleware/Api/Client/RequireClientApiKey.php \
  '\Pterodactyl\Http\Middleware\Protect\PanelProtect::clientList($request);' "Daftar semua server"

# ------------- 3. daftar Application API key (ptla) hanya milik admin sendiri ---
KEYREPO="$PANEL_DIR/app/Repositories/Eloquent/ApiKeyRepository.php"
if [[ -f "$KEYREPO" ]] && awk '/function getApplicationKeys/,/^    }/' "$KEYREPO" | grep -q 'user_id'; then
  info "Daftar Application API key di /admin/api sudah dibatasi per admin (hanya key sendiri)"
else
  warn "Tidak bisa memastikan daftar key di /admin/api dibatasi per admin, cek $(rel_of "$KEYREPO")"
fi

KEYVIEW="$PANEL_DIR/resources/views/admin/api/index.blade.php"
if [[ -f "$KEYVIEW" ]]; then
  if grep -q 'where("user_id", Auth::id())' "$KEYVIEW"; then
    info "Sudah dipatch: $(rel_of "$KEYVIEW")"
  else
    backup "$KEYVIEW"
    perl -0pi -e 's/\@foreach\s*\(\s*\$keys\s+as\s+\$key\s*\)/\@foreach (\$keys->where("user_id", Auth::id()) as \$key)/' "$KEYVIEW"
    if grep -q 'where("user_id", Auth::id())' "$KEYVIEW"; then
      info "Patch: $(rel_of "$KEYVIEW") (hanya key milik sendiri yang tampil)"
    else
      warn "Pola @foreach(\$keys as \$key) tidak ditemukan di $(rel_of "$KEYVIEW"), daftar key belum difilter."
    fi
  fi
else
  warn "Tidak ditemukan: $(rel_of "$KEYVIEW") (daftar key belum difilter)"
fi

# --------------------------------------------- 4. notifikasi welcome (toast) ---
info "Membuat notifikasi welcome"
write_file "$PANEL_DIR/resources/views/partials/protect-welcome.blade.php" <<'BLADE'
@auth
@php
    $__ptCfg = json_decode((string) @file_get_contents(storage_path('protect/config.json')), true) ?: [];
    $__ptSupport = $__ptCfg['support_url'] ?? '';
    $__ptArea = in_array($area ?? 'user', ['user', 'admin'], true) ? ($area ?? 'user') : 'user';
    $__ptKey = 'ptw_' . $__ptArea . '_' . substr(md5(session()->getId()), 0, 10);
@endphp
<script>
(function () {
    var key = @json($__ptKey);
    var area = @json($__ptArea);
    var name = @json((string) Auth::user()->username);
    var support = @json($__ptSupport);
    try {
        if (localStorage.getItem(key)) { return; }
        Object.keys(localStorage).forEach(function (k) {
            if (k.indexOf('ptw_' + area + '_') === 0) { localStorage.removeItem(k); }
        });
        localStorage.setItem(key, '1');
    } catch (e) { return; }

    function show() {
        var box = document.createElement('div');
        box.style.cssText = 'position:fixed;top:78px;right:16px;z-index:99999;max-width:340px;padding:14px 38px 14px 16px;'
            + 'background:#FFD60A;color:#111;font:600 14px/1.5 "Space Grotesk",system-ui,sans-serif;'
            + 'border:3px solid #111;box-shadow:6px 6px 0 #111;'
            + 'transition:opacity .4s,transform .4s;opacity:0;transform:translateY(-8px)';

        var title = document.createElement('div');
        title.style.cssText = 'font-weight:900;margin-bottom:4px;text-transform:uppercase';
        title.textContent = 'Selamat datang, ' + name;
        box.appendChild(title);

        var text = document.createElement('div');
        text.textContent = 'Butuh bantuan? Hubungi tim support kami.';
        box.appendChild(text);

        if (/^https?:\/\//i.test(support)) {
            var a = document.createElement('a');
            a.href = support; a.target = '_blank'; a.rel = 'noopener';
            a.textContent = 'Contact Support';
            a.style.cssText = 'display:inline-block;margin-top:8px;padding:5px 12px;background:#111;color:#FFD60A;'
                + 'border:3px solid #111;font-weight:800;text-decoration:none;text-transform:uppercase;font-size:12px';
            box.appendChild(a);
        }

        var x = document.createElement('button');
        x.type = 'button'; x.textContent = '×';
        x.style.cssText = 'position:absolute;top:4px;right:10px;background:none;border:0;color:#111;font-size:22px;font-weight:900;cursor:pointer';
        function close() { box.style.opacity = '0'; setTimeout(function () { box.remove(); }, 400); }
        x.onclick = close;
        box.appendChild(x);

        document.body.appendChild(box);
        requestAnimationFrame(function () { box.style.opacity = '1'; box.style.transform = 'none'; });
        setTimeout(close, 9000);
    }

    if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', show); } else { show(); }
})();
</script>
@endauth
BLADE

inject_before_body() { # file, area (user|admin)
  local f="$1" area="$2"
  [[ -f "$f" ]] || { warn "Tidak ditemukan: $(rel_of "$f") (dilewati)"; return 1; }
  if grep -q 'protect-welcome' "$f"; then info "Sudah dipatch: $(rel_of "$f")"; return 0; fi
  backup "$f"
  AREA="$area" perl -0pi -e 's#</body>#\@includeIf("partials.protect-welcome", ["area" => "$ENV{AREA}"])\n</body>#' "$f"
  if grep -q 'protect-welcome' "$f"; then info "Patch ($area): $(rel_of "$f")"; return 0; fi
  warn "Tag </body> tidak ditemukan di $(rel_of "$f")"; return 1
}
inject_before_body "$THEME_WRAPPER_VIEW" user \
  || inject_before_body "$THEME_CORE_VIEW" user || true
inject_before_body "$THEME_ADMIN_VIEW" admin || true

# ----------------------------------------------- 5. halaman error + tombol back ---
info "Membuat halaman error (403, 404, 419, 429, 500, 503)"
write_file "$PANEL_DIR/resources/views/errors/_protect.blade.php" <<'BLADE'
@php
    $__ptCfg = json_decode((string) @file_get_contents(storage_path('protect/config.json')), true) ?: [];
    $__ptSupport = $__ptCfg['support_url'] ?? '';
@endphp
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>{{ $code }} - {{ $title }}</title>
    <style>
        *{box-sizing:border-box}
        body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px;
             background:#FFF4D6 radial-gradient(rgba(17,17,17,.14) 1.5px,transparent 1.5px) 0 0/24px 24px;color:#111;
             font-family:"Space Grotesk",system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
        .card{width:100%;max-width:460px;text-align:center;padding:36px 28px;background:#fff;border:4px solid #111;box-shadow:10px 10px 0 #111}
        .code{display:inline-block;font-size:84px;font-weight:900;line-height:1;letter-spacing:-2px;padding:6px 18px;background:#FFD60A;border:4px solid #111}
        h1{font-size:22px;margin:18px 0 8px;text-transform:uppercase;font-weight:900}
        p{margin:0 0 22px;line-height:1.6;font-size:15px;font-weight:500}
        .actions{display:flex;flex-wrap:wrap;gap:12px;justify-content:center}
        .btn{appearance:none;cursor:pointer;text-decoration:none;font:800 14px system-ui,sans-serif;text-transform:uppercase;
             padding:11px 18px;border:3px solid #111;box-shadow:4px 4px 0 #111;color:#111;background:#fff;transition:transform .08s,box-shadow .08s}
        .btn:hover{transform:translate(-2px,-2px);box-shadow:6px 6px 0 #111}
        .primary{background:#FF6B9D}
    </style>
</head>
<body>
    <div class="card">
        <div class="code">{{ $code }}</div>
        <h1>{{ $title }}</h1>
        <p>{{ $msg }}</p>
        <div class="actions">
            <button class="btn primary" type="button"
                onclick="if (history.length > 1) { history.back(); } else { location.href = '/'; }">&larr; Kembali</button>
            <a class="btn" href="/">Beranda</a>
            @if (preg_match('#^https?://#i', $__ptSupport))
                <a class="btn" href="{{ $__ptSupport }}" target="_blank" rel="noopener">Contact Support</a>
            @endif
        </div>
    </div>
</body>
</html>
BLADE

make_error() { # code, title, default-message
  write_file "$PANEL_DIR/resources/views/errors/$1.blade.php" <<BLADE
@include('errors._protect', [
    'code' => $1,
    'title' => '$2',
    'msg' => $4,
])
BLADE
}
make_error 403 'Akses Ditolak'        x "(isset(\$exception) && \$exception->getMessage()) ? \$exception->getMessage() : 'Kamu tidak memiliki izin untuk membuka halaman ini.'"
make_error 404 'Halaman Tidak Ditemukan' x "'Halaman yang kamu cari tidak ada atau sudah dipindahkan.'"
make_error 419 'Sesi Berakhir'        x "'Sesi kamu sudah kedaluwarsa. Silakan kembali dan muat ulang halaman.'"
make_error 429 'Terlalu Banyak Permintaan' x "'Kamu terlalu sering mengirim permintaan. Tunggu sebentar lalu coba lagi.'"
make_error 500 'Terjadi Kesalahan Server' x "'Ada masalah di server. Silakan coba lagi nanti atau hubungi support.'"
make_error 503 'Sedang Maintenance'   x "'Panel sedang dalam pemeliharaan. Silakan coba beberapa saat lagi.'"

# ------------------------------------------------------------- 6. validasi ---
info "Validasi sintaks PHP"
bad=0
for f in \
  "$PANEL_DIR/app/Http/Middleware/Protect/PanelProtect.php" \
  "$PANEL_DIR/app/Http/Middleware/AdminAuthenticate.php" \
  "$API_MW" "${PATCHED_PHP[@]:-}"; do
  [[ -f "$f" ]] || continue
  php -l "$f" >/dev/null 2>&1 || { warn "Syntax error: $(rel_of "$f")"; bad=1; }
done
if [[ $bad -eq 1 ]]; then
  warn "Ada error sintaks, rollback otomatis..."
  restore_original
  die "Install dibatalkan, file asli sudah dikembalikan."
fi

post_steps

cat <<EOF

${c_grn}Selesai.${c_off}
  - Owner penuh akses : user ID 1
  - Application API   : tanpa batas IP; hanya admin panel yang boleh memakai key
  - Role admin        : hanya user ID 1 yang bisa membuat / menjadikan user admin
  - Support URL       : $PROTECT_DIR/config.json
  - Log penolakan     : storage/logs/laravel-*.log  (cari "[protect]")
  - Atur logo & nama  : bash $0 theme-brand
  - Batalkan          : bash $0 uninstall  (tanpa input IP)

Catatan: setelah update panel (upgrade), jalankan installer ini lagi.
EOF
