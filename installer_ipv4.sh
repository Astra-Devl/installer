#!/usr/bin/env bash
# =============================================================================
#  Pterodactyl Panel Protect Installer
#  Pemakaian:
#     bash protect-pterodactyl.sh              -> menu (Install / Uninstall Protect)
#     bash protect-pterodactyl.sh install      -> langsung install / update
#     bash protect-pterodactyl.sh uninstall    -> langsung uninstall (wajib isi IP VPS)
#  Format IP: IPv4, IPv6, atau IPv4:port / [IPv6]:port (port acak diabaikan)
#  Opsional (env): PANEL_DIR=/var/www/pterodactyl SUPPORT_URL=https://t.me/xxx
#                  ALLOWED_IPS="IP_TAMBAHAN"(opsional)  UNINSTALL_IP="1.2.3.4"
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

# Normalisasi input IP: IPv4, IPv6, ipv4:port, [ipv6]:port -> IP saja (port dibuang)
normalize_ip() {
  local v="${1//[[:space:]]/}" ip
  v="${v,,}"
  if [[ "$v" =~ ^\[([0-9a-f:.]+)\](:[0-9]{1,5})?$ ]]; then
    ip="${BASH_REMATCH[1]}"
  elif [[ "$v" =~ ^([0-9]{1,3}(\.[0-9]{1,3}){3})(:[0-9]{1,5})?$ ]]; then
    ip="${BASH_REMATCH[1]}"
    local o part; IFS=. read -r -a part <<< "$ip"
    for o in "${part[@]}"; do (( 10#$o <= 255 )) || return 1; done
  elif [[ "$v" =~ ^[0-9a-f:]+$ && "$v" == *:*:* ]]; then
    ip="$v"
  else
    return 1
  fi
  echo "$ip"
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
  post_steps
}

# Uninstall: wajib isi IP VPS (IP panel atau IP whitelist) sebagai konfirmasi
uninstall_protect() {
  [[ -d "$BK" ]] || die "Protect belum terpasang (backup tidak ditemukan)."
  local known input="${UNINSTALL_IP:-}" ip tries=0
  known="$(cat "$PROTECT_DIR/panel_ips.txt" "$PROTECT_DIR/allowed_ips.txt" 2>/dev/null | tr 'A-F' 'a-f' | sort -u || true)"
  while (( tries < 3 )); do
    if [[ -z "$input" ]]; then
      read -r -p "Masukkan IP VPS (IPv4/IPv6, boleh ipv4:port): " input || true
    fi
    if ip="$(normalize_ip "$input")" && grep -qxF "$ip" <<< "$known"; then
      restore_original
      info "Proteksi dihapus, file asli dikembalikan."
      exit 0
    fi
    tries=$((tries + 1))
    warn "IP tidak valid atau tidak cocok ($tries/3)."
    input=""
  done
  die "Verifikasi IP gagal. Uninstall dibatalkan."
}

# ------------------------------------------------------------------- menu ---
if [[ "$ACTION" == "menu" ]]; then
  echo "========== Pterodactyl Protect =========="
  echo " 1) Install Protect"
  echo " 2) Uninstall Protect"
  echo " 0) Keluar"
  read -r -p "Pilih [0-2]: " choice || true
  case "${choice:-0}" in
    1) ACTION="install" ;;
    2) ACTION="uninstall" ;;
    *) exit 0 ;;
  esac
fi
case "$ACTION" in
  install|1)   ACTION="install" ;;
  uninstall|2) ACTION="uninstall" ;;
  *) die "Pilihan tidak dikenal: $ACTION (pakai: install | uninstall)" ;;
esac
[[ "$ACTION" == "uninstall" ]] && uninstall_protect

# ------------------------------------------------------------- input config ---
SUPPORT_URL="${SUPPORT_URL:-}"
if [[ -z "$SUPPORT_URL" ]]; then
  read -r -p "Link contact support (https://t.me/username, kosongkan jika tidak ada): " SUPPORT_URL || true
fi
url_re='^https?://[A-Za-z0-9._~:/?#@!&()*+,;=%-]+$'
if [[ -n "$SUPPORT_URL" && ! "$SUPPORT_URL" =~ $url_re ]]; then
  die "Link support tidak valid (harus diawali http:// atau https://)."
fi

# IP milik VPS panel (tidak boleh akses Application API)
detect_panel_ips() {
  {
    hostname -I 2>/dev/null | tr ' ' '\n' || true
    curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true
    echo
    local host=""
    if [[ -f "$PANEL_DIR/.env" ]]; then
      host="$(grep -E '^APP_URL=' "$PANEL_DIR/.env" | head -1 | cut -d= -f2- | tr -d "\"'" | sed -E 's#^https?://##; s#[/:].*$##' || true)"
    fi
    [[ -n "$host" ]] && { getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' || true; }
  } | grep -E '^[0-9a-fA-F:.]+$' | sort -u || true
}
PANEL_IPS="$(detect_panel_ips)"
info "IP panel terdeteksi (satu-satunya IP yang boleh akses Application API):"
echo "${PANEL_IPS:-  (tidak terdeteksi)}" | sed 's/^/    /'

if [[ -z "$PANEL_IPS" ]]; then
  warn "IP panel tidak terdeteksi otomatis."
  read -r -p "Masukkan IP VPS panel (IPv4/IPv6, boleh ipv4:port): " manual_ip || true
  PANEL_IPS="$(normalize_ip "${manual_ip:-}")" || die "IP tidak valid. Tanpa IP panel, Application API akan terkunci."
fi

# IP tambahan (opsional, TIDAK ditanyakan): ALLOWED_IPS="1.2.3.4,5.6.7.8:5555"
CLEAN_IPS=()
IFS=', ' read -r -a _ips <<< "${ALLOWED_IPS:-}"
for raw in "${_ips[@]:-}"; do
  [[ -z "$raw" ]] && continue
  nip="$(normalize_ip "$raw")" || { warn "IP '$raw' tidak valid, dilewati."; continue; }
  grep -qxF "$nip" <<< "$PANEL_IPS" && continue
  CLEAN_IPS+=("$nip")
done

mkdir -p "$PROTECT_DIR" "$BK"
printf '%s\n' "${CLEAN_IPS[@]:-}" | sed '/^$/d' | sort -u > "$PROTECT_DIR/allowed_ips.txt"
printf '%s\n' "$PANEL_IPS"                         > "$PROTECT_DIR/panel_ips.txt"
printf '{"support_url":"%s"}\n' "$SUPPORT_URL"      > "$PROTECT_DIR/config.json"

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

        // Daftar semua server (milik user) ditolak untuk admin selain owner.
        if ($section === 'servers' && count($seg) === 2) {
            self::deny($request, 'Daftar server milik user hanya bisa dilihat oleh owner panel.');
        }

        // Server orang lain: tidak boleh dibuka / diubah / dihapus.
        if ($section === 'servers' && ($seg[2] ?? '') === 'view' && isset($seg[3]) && ctype_digit($seg[3])) {
            $server = Server::query()->find((int) $seg[3]);
            if ($server && (int) $server->owner_id !== (int) $user->id) {
                self::deny($request, 'Kamu tidak boleh membuka atau mengubah server milik orang lain.');
            }
        }

        // Admin utama (id 1): tidak boleh diedit / dihapus.
        if ($section === 'users' && ($seg[2] ?? '') === 'view'
            && (int) ($seg[3] ?? 0) === self::OWNER_ID && $method !== 'GET') {
            self::deny($request, 'Akun owner panel tidak boleh diedit atau dihapus.');
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

    /** Dipanggil dari AuthenticateApplicationUser (semua /api/application). */
    public static function api(Request $request): void
    {
        // Middleware ini bisa ikut jalan di Client API; proteksi hanya untuk /api/application.
        $path = $request->segments();
        if (($path[0] ?? '') !== 'api' || ($path[1] ?? '') !== 'application') {
            return;
        }

        $ip = strtolower((string) $request->ip());

        // Application API hanya boleh dipanggil dari VPS panel sendiri
        // (+ IP tambahan opsional di allowed_ips.txt). IP lain ditolak.
        $allowed = array_merge(
            self::lines('panel_ips.txt'),
            self::lines('allowed_ips.txt'),
            ['127.0.0.1', '::1']
        );
        if (!in_array($ip, $allowed, true)) {
            self::deny($request, 'Application API hanya bisa diakses dari server panel.');
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

        // Admin biasa: semua endpoint API tetap terbuka (users, servers, nodes, include=servers, dll).
        // Satu-satunya batasan: akun owner (id 1) tidak boleh diedit / dihapus.
        $seg = $request->segments(); // [api, application, section, id, ...]
        $section = $seg[2] ?? '';
        $target = $seg[3] ?? null;
        $method = strtoupper($request->method());

        if ($section === 'users' && (int) $target === self::OWNER_ID && $method !== 'GET') {
            self::deny($request, 'Akun owner panel tidak boleh diedit atau dihapus.');
        }
    }

    private static function lines(string $file): array
    {
        $path = storage_path('protect/' . $file);
        if (!is_readable($path)) {
            return [];
        }
        $rows = file($path, FILE_IGNORE_NEW_LINES) ?: [];

        return array_values(array_filter(array_map(fn ($l) => strtolower(trim($l)), $rows), fn ($l) => $l !== '' && $l[0] !== '#'));
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

# ------------- 3. daftar Application API key (ptla) hanya milik admin sendiri ---
KEYREPO="$PANEL_DIR/app/Repositories/Eloquent/ApiKeyRepository.php"
if [[ -f "$KEYREPO" ]] && awk '/function getApplicationKeys/,/^    }/' "$KEYREPO" | grep -q 'user_id'; then
  info "Daftar Application API key di /admin/api sudah dibatasi per admin (hanya key sendiri)"
else
  warn "Tidak bisa memastikan daftar key di /admin/api dibatasi per admin, cek $(rel_of "$KEYREPO")"
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
        box.style.cssText = 'position:fixed;top:16px;right:16px;z-index:99999;max-width:340px;padding:14px 38px 14px 16px;'
            + 'border-radius:12px;background:#1f2937;color:#f9fafb;font:14px/1.5 system-ui,sans-serif;'
            + 'box-shadow:0 10px 30px rgba(0,0,0,.35);border-left:4px solid #38bdf8;'
            + 'transition:opacity .4s,transform .4s;opacity:0;transform:translateY(-8px)';

        var title = document.createElement('div');
        title.style.cssText = 'font-weight:600;margin-bottom:4px';
        title.textContent = 'Selamat datang 👋 ' + name;
        box.appendChild(title);

        var text = document.createElement('div');
        text.style.opacity = '.85';
        text.textContent = 'Butuh bantuan? Hubungi tim support kami.';
        box.appendChild(text);

        if (/^https?:\/\//i.test(support)) {
            var a = document.createElement('a');
            a.href = support; a.target = '_blank'; a.rel = 'noopener';
            a.textContent = 'Contact Support';
            a.style.cssText = 'display:inline-block;margin-top:8px;padding:5px 12px;border-radius:8px;'
                + 'background:#38bdf8;color:#0b1220;font-weight:600;text-decoration:none';
            box.appendChild(a);
        }

        var x = document.createElement('button');
        x.type = 'button'; x.textContent = '×';
        x.style.cssText = 'position:absolute;top:6px;right:10px;background:none;border:0;color:#9ca3af;font-size:20px;cursor:pointer';
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
# Dashboard user (React app) -> fallback ke wrapper kalau core tidak punya </body>
inject_before_body "$PANEL_DIR/resources/views/templates/base/core.blade.php" user \
  || inject_before_body "$PANEL_DIR/resources/views/templates/wrapper.blade.php" user || true
# Area admin
inject_before_body "$PANEL_DIR/resources/views/layouts/admin.blade.php" admin || true

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
             background:radial-gradient(circle at 20% 20%,#1e293b,#0b1220 70%);color:#e5e7eb;
             font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
        .card{width:100%;max-width:460px;text-align:center;padding:36px 28px;border-radius:20px;
              background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);
              box-shadow:0 20px 60px rgba(0,0,0,.45)}
        .code{font-size:84px;font-weight:800;line-height:1;letter-spacing:-2px;
              background:linear-gradient(135deg,#38bdf8,#a78bfa);-webkit-background-clip:text;background-clip:text;color:transparent}
        h1{font-size:22px;margin:14px 0 8px}
        p{margin:0 0 22px;color:#9ca3af;line-height:1.6;font-size:15px}
        .actions{display:flex;flex-wrap:wrap;gap:10px;justify-content:center}
        .btn{appearance:none;border:0;cursor:pointer;text-decoration:none;font:600 14px system-ui,sans-serif;
             padding:11px 18px;border-radius:12px;transition:transform .15s,opacity .15s}
        .btn:hover{transform:translateY(-1px);opacity:.92}
        .primary{background:linear-gradient(135deg,#38bdf8,#818cf8);color:#0b1220}
        .ghost{background:rgba(255,255,255,.08);color:#e5e7eb}
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
            <a class="btn ghost" href="/">Beranda</a>
            @if (preg_match('#^https?://#i', $__ptSupport))
                <a class="btn ghost" href="{{ $__ptSupport }}" target="_blank" rel="noopener">Contact Support</a>
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
  "$API_MW"; do
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
  - Application API   : hanya dari IP VPS panel ($PROTECT_DIR/panel_ips.txt)
  - IP tambahan       : $PROTECT_DIR/allowed_ips.txt  (opsional, satu IP per baris)
  - Support URL       : $PROTECT_DIR/config.json
  - Log penolakan     : storage/logs/laravel-*.log  (cari "[protect]")
  - Batalkan          : bash $0 uninstall  (wajib isi IP VPS)

Catatan: setelah update panel (upgrade), jalankan installer ini lagi.
EOF
