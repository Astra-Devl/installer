#!/bin/bash
# =====================================================================
#  Installer: Whitelist IP otomatis untuk API key ptla (Pterodactyl)
#  Support: IPv4, IPv4:port (port diabaikan), [IPv6], [IPv6]:port, CIDR
#
#  Pakai:
#    bash installer.sh                          -> tampilkan MENU (install/uninstall/status)
#    bash installer.sh install                  -> install, IPv4/IPv6 dideteksi otomatis
#    bash installer.sh install 1.2.3.4:8080 2001:db8::1 -> install dengan IP manual
#    bash installer.sh uninstall                -> uninstall protect (kembalikan file asli)
#    bash installer.sh status                   -> cek status protect
#
#  Opsional: PANEL_DIR=/path/panel bash installer.sh
# =====================================================================

PANEL="${PANEL_DIR:-/var/www/pterodactyl}"
CTRL="$PANEL/app/Http/Controllers/Admin/ApiController.php"
VIEW="$PANEL/resources/views/admin/api/new.blade.php"
MWDIR="$PANEL/app/Http/Middleware/Api"
MW="$MWDIR/PtlaIpWhitelist.php"
KERNEL="$PANEL/app/Http/Kernel.php"
ENVF="$PANEL/.env"
BACKUP_ROOT="$PANEL/backup-ptla"

if [ "$(id -u)" -ne 0 ]; then
  echo "[!] Jalankan sebagai root (sudo bash installer.sh)"
  exit 1
fi

if [ ! -f "$PANEL/artisan" ]; then
  echo "[!] Panel tidak ditemukan di $PANEL"
  echo "    Pakai: PANEL_DIR=/path/panel bash installer.sh"
  exit 1
fi

clear_cache() {
  cd "$PANEL" || exit 1
  php artisan config:clear >/dev/null 2>&1
  php artisan cache:clear >/dev/null 2>&1
  php artisan view:clear >/dev/null 2>&1
}

fix_owner() {
  OWNER="www-data:www-data"
  id nginx >/dev/null 2>&1 && OWNER="nginx:nginx"
  chown "$OWNER" "$CTRL" "$VIEW" "$KERNEL" "$MW" 2>/dev/null
}

# ---------------------------- STATUS ---------------------------------
do_status() {
  echo "---------------- STATUS PROTECT ----------------"
  [ -f "$MW" ] && echo "[v] Middleware PtlaIpWhitelist : ada" || echo "[x] Middleware PtlaIpWhitelist : tidak ada"
  grep -q "PtlaIpWhitelist" "$KERNEL" 2>/dev/null && echo "[v] Terdaftar di Kernel.php     : ya" || echo "[x] Terdaftar di Kernel.php     : tidak"
  grep -q "PtlaIpWhitelist" "$CTRL" 2>/dev/null && echo "[v] ApiController (whitelist)  : terpasang" || echo "[x] ApiController (whitelist)  : belum"
  grep -q "PtlaIpWhitelist" "$VIEW" 2>/dev/null && echo "[v] new.blade.php (field IP)   : terpasang" || echo "[x] new.blade.php (field IP)   : belum"
  CUR=$(grep "^PTLA_VPS_IPS=" "$ENVF" 2>/dev/null | cut -d= -f2-)
  echo "[i] PTLA_VPS_IPS di .env       : ${CUR:-(kosong)}"
  echo "------------------------------------------------"
}

# ---------------------------- UNINSTALL ------------------------------
do_uninstall() {
  # Backup paling lama = file asli sebelum protect dipasang
  ORIG=$(ls -1dt "$BACKUP_ROOT"/*/ 2>/dev/null | tail -n1)
  if [ -z "$ORIG" ] || [ ! -f "$ORIG/ApiController.php" ] || [ ! -f "$ORIG/new.blade.php" ]; then
    echo "[!] Backup file asli tidak ditemukan di $BACKUP_ROOT"
    echo "    Uninstall dibatalkan supaya panel tidak rusak."
    return 1
  fi
  if grep -q "PtlaIpWhitelist" "$ORIG/ApiController.php" "$ORIG/new.blade.php"; then
    echo "[!] Backup terdeteksi sudah berisi protect (bukan file asli)."
    echo "    Uninstall dibatalkan. Kembalikan file asli manual dari panel resmi."
    return 1
  fi

  echo "[*] Mengembalikan file asli dari $ORIG"
  cp "$ORIG/ApiController.php" "$CTRL" && echo "[+] ApiController dikembalikan"
  cp "$ORIG/new.blade.php" "$VIEW" && echo "[+] new.blade.php dikembalikan"

  if grep -q "PtlaIpWhitelist" "$KERNEL"; then
    cp "$KERNEL" "$KERNEL.bak-ptla"
    sed -i '/PtlaIpWhitelist/d' "$KERNEL"
    if php -l "$KERNEL" >/dev/null 2>&1; then
      rm -f "$KERNEL.bak-ptla"
      echo "[+] Baris middleware dihapus dari Kernel.php"
    else
      cp "$KERNEL.bak-ptla" "$KERNEL"
      echo "[!] Gagal membersihkan Kernel.php, dikembalikan. Hapus baris PtlaIpWhitelist manual."
    fi
  fi

  rm -f "$MW" && echo "[+] Middleware PtlaIpWhitelist dihapus"
  sed -i '/^PTLA_VPS_IPS=/d' "$ENVF" && echo "[+] PTLA_VPS_IPS dihapus dari .env"

  if [ -t 0 ]; then
    read -rp "Hapus juga whitelist IP dari semua key ptla yang sudah ada? [y/N]: " ans </dev/tty
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      (cd "$PANEL" && php artisan tinker --execute="\Pterodactyl\Models\ApiKey::where('key_type', 2)->update(['allowed_ips' => null]); echo 'ok';" >/dev/null 2>&1) \
        && echo "[+] Whitelist IP di key ptla dihapus" \
        || echo "[!] Gagal update key ptla (bisa diabaikan)"
    fi
  fi

  fix_owner
  clear_cache
  echo "[OK] Uninstall protect selesai."
}

# ---------------------------- HELPER IP ------------------------------
# Hapus port & kurung: 1.2.3.4:8080 -> 1.2.3.4 | [2001:db8::1]:443 -> 2001:db8::1
normalize_ip() {
  local v="${1//[[:space:]]/}"
  local re6='^\[([^]]+)\](:[0-9]+)?(/[0-9]+)?$'
  local re4='^([0-9]{1,3}(\.[0-9]{1,3}){3}):[0-9]+(/[0-9]+)?$'
  if [[ "$v" =~ $re6 ]]; then
    echo "${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
  elif [[ "$v" =~ $re4 ]]; then
    echo "${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
  else
    echo "$v"
  fi
}

valid_ip() {
  local base="${1%%/*}"
  [ -n "$base" ] && php -r 'exit(filter_var($argv[1], FILTER_VALIDATE_IP) ? 0 : 1);' "$base"
}

# ---------------------------- INSTALL --------------------------------
do_install() {
RAW=()
if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    IFS=',' read -ra PARTS <<< "$arg"
    for p in "${PARTS[@]}"; do RAW+=("$p"); done
  done
else
  V4=$(curl -4 -s --max-time 8 ifconfig.me)
  V6=$(curl -6 -s --max-time 8 ifconfig.me)
  [ -n "$V4" ] && RAW+=("$V4")
  [ -n "$V6" ] && RAW+=("$V6")
fi

IPS=()
for r in "${RAW[@]}"; do
  n=$(normalize_ip "$r")
  if valid_ip "$n"; then
    IPS+=("$n")
  else
    echo "[!] IP dilewati (tidak valid): $r"
  fi
done

if [ "${#IPS[@]}" -eq 0 ]; then
  echo "[!] Tidak ada IP valid. Jalankan: bash installer.sh install IP_VPS_KAMU"
  return 1
fi

IP_CSV=$(IFS=','; echo "${IPS[*]}")
echo "[*] IP yang di-whitelist: $IP_CSV"

# ---------------------------- BACKUP ---------------------------------
if grep -q "PtlaIpWhitelist" "$CTRL" 2>/dev/null; then
  # Sudah pernah di-install: jangan timpa backup file asli
  BK=$(ls -1dt "$BACKUP_ROOT"/*/ 2>/dev/null | tail -n1)
  echo "[=] Protect sudah terpasang sebelumnya, backup asli dipertahankan (${BK:-tidak ada})"
else
  BK="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BK"
  cp "$CTRL" "$BK/ApiController.php"
  cp "$VIEW" "$BK/new.blade.php"
  cp "$KERNEL" "$BK/Kernel.php"
  echo "[+] Backup file asli tersimpan di $BK"
fi

# ---------------------------- MIDDLEWARE -----------------------------
mkdir -p "$MWDIR"
cat > "$MW" <<'PHPEOF'
<?php

namespace Pterodactyl\Http\Middleware\Api;

use Closure;
use Illuminate\Http\Request;
use Pterodactyl\Models\ApiKey;
use Symfony\Component\HttpFoundation\IpUtils;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

/**
 * Whitelist IP otomatis untuk API key Application (ptla_).
 *
 * - Port source (acak) tidak berpengaruh: yang dicek hanya alamat IP.
 * - Mendukung IPv4, IPv6, CIDR, serta input berformat ip:port / [ipv6]:port.
 */
class PtlaIpWhitelist
{
    public function handle(Request $request, Closure $next)
    {
        $key = $request->attributes->get('api_key');

        // Hanya berlaku untuk key Application (ptla_)
        if (!$key instanceof ApiKey || (int) $key->key_type !== ApiKey::TYPE_APPLICATION) {
            return $next($request);
        }

        $client = self::normalize((string) $request->ip());
        $allowed = self::serverIps();

        foreach ((array) $key->allowed_ips as $ip) {
            $n = self::normalize((string) $ip);
            if ($n !== null) {
                $allowed[] = $n;
            }
        }

        if ($client !== null && IpUtils::checkIp($client, array_values(array_unique($allowed)))) {
            return $next($request);
        }

        throw new AccessDeniedHttpException('API key ini hanya bisa digunakan dari IP VPS panel. IP kamu (' . $request->ip() . ') ditolak.');
    }

    /**
     * IP yang selalu diizinkan: loopback + IP server + isi PTLA_VPS_IPS di .env.
     */
    public static function serverIps(): array
    {
        $list = ['127.0.0.1', '::1'];

        if (!empty($_SERVER['SERVER_ADDR'])) {
            $list[] = $_SERVER['SERVER_ADDR'];
        }

        foreach (explode(',', (string) env('PTLA_VPS_IPS', '')) as $item) {
            $list[] = $item;
        }

        $out = [];
        foreach ($list as $item) {
            $n = self::normalize((string) $item);
            if ($n !== null) {
                $out[] = $n;
            }
        }

        return array_values(array_unique($out));
    }

    /**
     * Rapikan input IP: buang port, kurung, zone id; ubah ::ffff:1.2.3.4 jadi IPv4.
     * Return null jika tidak valid.
     */
    public static function normalize(string $value): ?string
    {
        $v = trim($value);
        if ($v === '') {
            return null;
        }

        $mask = null;
        if (strpos($v, '/') !== false) {
            [$v, $mask] = explode('/', $v, 2);
        }

        if (preg_match('/^\[([^\]]+)\](?::\d+)?$/', $v, $m)) {
            $v = $m[1];
        } elseif (preg_match('/^(\d{1,3}(?:\.\d{1,3}){3}):\d+$/', $v, $m)) {
            $v = $m[1];
        }

        $v = preg_replace('/%.+$/', '', $v);

        if (preg_match('/^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i', $v, $m)) {
            $v = $m[1];
        }

        if (!filter_var($v, FILTER_VALIDATE_IP)) {
            return null;
        }

        if ($mask !== null) {
            $max = filter_var($v, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) ? 32 : 128;
            if (!ctype_digit($mask) || (int) $mask > $max) {
                return null;
            }

            return $v . '/' . $mask;
        }

        return $v;
    }
}
PHPEOF
echo "[+] Middleware PtlaIpWhitelist terpasang"

# ---------------------------- Kernel.php -----------------------------
if grep -q "PtlaIpWhitelist" "$KERNEL"; then
  echo "[=] Kernel.php sudah terdaftar, dilewati"
else
  TMPK=$(mktemp)
  awk '
    /application-api/ { inapp=1 }
    { print }
    inapp && /AuthenticateApplicationUser::class,/ {
      print "            \\Pterodactyl\\Http\\Middleware\\Api\\PtlaIpWhitelist::class,"
      inapp=0
    }
  ' "$KERNEL" > "$TMPK"

  if grep -q "PtlaIpWhitelist" "$TMPK" && php -l "$TMPK" >/dev/null 2>&1; then
    cp "$TMPK" "$KERNEL"
    echo "[+] Middleware didaftarkan di grup application-api (Kernel.php)"
  else
    echo "[!] Gagal mendaftarkan otomatis di Kernel.php (struktur berbeda)."
    echo "    Tambahkan manual di grup 'application-api' pada $KERNEL:"
    echo "        \\Pterodactyl\\Http\\Middleware\\Api\\PtlaIpWhitelist::class,"
  fi
  rm -f "$TMPK"
fi

# ---------------------------- ApiController --------------------------
cat > "$CTRL" <<'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Pterodactyl\Models\ApiKey;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Services\Acl\Api\AdminAcl;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Api\KeyCreationService;
use Pterodactyl\Http\Requests\Admin\Api\StoreApplicationApiKeyRequest;

class ApiController extends Controller
{
    /**
     * ApiController constructor.
     */
    public function __construct(
        private AlertsMessageBag $alert,
        private KeyCreationService $keyCreationService,
    ) {
    }

    /**
     * Render view showing all of a user's application API keys.
     */
    public function index(Request $request): View
    {
        return view('admin.api.index', [
            'keys' => ApiKey::query()->where('key_type', ApiKey::TYPE_APPLICATION)->get(),
        ]);
    }

    /**
     * Render view allowing an admin to create a new application API key.
     *
     * @throws \ReflectionException
     */
    public function create(): View
    {
        $resources = AdminAcl::getResourceList();
        sort($resources);

        return view('admin.api.new', [
            'resources' => $resources,
            'permissions' => [
                'r' => AdminAcl::READ,
                'rw' => AdminAcl::READ | AdminAcl::WRITE,
                'n' => AdminAcl::NONE,
            ],
        ]);
    }

    /**
     * Store the new key and redirect the user back to the application key listing.
     * Whitelist IP VPS (IPv4/IPv6) otomatis ditambahkan ke setiap key ptla yang dibuat.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     */
    public function store(StoreApplicationApiKeyRequest $request): RedirectResponse
    {
        $this->keyCreationService->setKeyType(ApiKey::TYPE_APPLICATION)->handle([
            'memo' => $request->input('memo'),
            'user_id' => $request->user()->id,
            'allowed_ips' => \Pterodactyl\Http\Middleware\Api\PtlaIpWhitelist::serverIps(),
        ], $request->getKeyPermissions());

        $this->alert->success('A new application API key has been generated for your account.')->flash();

        return redirect()->route('admin.api.index');
    }

    /**
     * Delete an application API key from the database.
     */
    public function delete(Request $request, string $identifier): Response
    {
        ApiKey::query()
            ->where('key_type', ApiKey::TYPE_APPLICATION)
            ->where('identifier', $identifier)
            ->delete();

        return response('', 204);
    }
}
PHPEOF
echo "[+] ApiController.php terpasang"

# ---------------------------- new.blade.php --------------------------
cat > "$VIEW" <<'BLADEEOF'
@extends('layouts.admin')

@section('title')
    Application API
@endsection

@section('content-header')
    <h1>Application API<small>Create a new application API key.</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li><a href="{{ route('admin.api.index') }}">Application API</a></li>
        <li class="active">New Credentials</li>
    </ol>
@endsection

@section('content')
    <div class="row">
        <form method="POST" action="{{ route('admin.api.new') }}">
            <div class="col-sm-8 col-xs-12">
                <div class="box box-primary">
                    <div class="box-header with-border">
                        <h3 class="box-title">Select Permissions</h3>
                        <div class="box-tools">
                            <div class="btn-group">
                                <button type="button" class="btn btn-sm btn-default" id="btn-bulk-read">Read All</button>
                                <button type="button" class="btn btn-sm btn-default" id="btn-bulk-rw">Read &amp; Write All</button>
                                <button type="button" class="btn btn-sm btn-default" id="btn-bulk-none">None All</button>
                            </div>
                        </div>
                    </div>
                    <div class="box-body table-responsive no-padding">
                        <table class="table table-hover" style="min-width: 650px;">
                            @foreach($resources as $resource)
                                <tr>
                                    <td class="strong" style="vertical-align: middle; padding-left: 15px;">
                                        {{ str_replace('_', ' ', title_case($resource)) }}
                                    </td>

                                    <td class="text-center" style="vertical-align: middle;">
                                        <div class="radio radio-primary" style="margin: 0;">
                                            <input type="radio" id="r_{{ $resource }}" name="r_{{ $resource }}" value="{{ $permissions['r'] }}">
                                            <label for="r_{{ $resource }}">Read</label>
                                        </div>
                                    </td>

                                    <td class="text-center" style="vertical-align: middle;">
                                        <div class="radio radio-primary" style="margin: 0;">
                                            <input type="radio" id="rw_{{ $resource }}" name="r_{{ $resource }}" value="{{ $permissions['rw'] }}">
                                            <label for="rw_{{ $resource }}">Read &amp; Write</label>
                                        </div>
                                    </td>

                                    <td class="text-center" style="vertical-align: middle;">
                                        <div class="radio" style="margin: 0;">
                                            <input type="radio" id="n_{{ $resource }}" name="r_{{ $resource }}" value="{{ $permissions['n'] }}" checked>
                                            <label for="n_{{ $resource }}">None</label>
                                        </div>
                                    </td>
                                </tr>
                            @endforeach
                        </table>
                    </div>
                </div>
            </div>
            <div class="col-sm-4 col-xs-12">
                <div class="box box-primary">
                    <div class="box-body">
                        <div class="form-group">
                            <label class="control-label" for="memoField">Description <span class="field-required"></span></label>
                            <input id="memoField" type="text" name="memo" class="form-control">
                        </div>
                        <div class="form-group">
                            <label class="control-label" for="whitelistIpField">Whitelist IP (otomatis IP VPS)</label>
                            <input id="whitelistIpField" type="text" class="form-control" value="{{ implode(', ', \Pterodactyl\Http\Middleware\Api\PtlaIpWhitelist::serverIps()) }}" readonly>
                            <p class="text-muted small" style="margin-top: 5px;">Key ini hanya bisa dipakai dari IP VPS di atas (IPv4/IPv6). Port tidak berpengaruh. Request dari IP lain otomatis ditolak.</p>
                        </div>
                        <p class="text-muted">Once you have assigned permissions and created this set of credentials you will be unable to come back and edit it. If you need to make changes down the road you will need to create a new set of credentials.</p>
                    </div>
                    <div class="box-footer">
                        {{ csrf_field() }}
                        <button type="submit" class="btn btn-success btn-sm pull-right">Create Credentials</button>
                    </div>
                </div>
            </div>
        </form>
    </div>
@endsection


@section('footer-scripts')
    @parent
    <script>
        $(document).ready(function() {

            function setButtonActive(activeButton) {
                $('#btn-bulk-read, #btn-bulk-rw, #btn-bulk-none')
                    .removeClass('btn-primary')
                    .addClass('btn-default');
                $(activeButton)
                    .removeClass('btn-default')
                    .addClass('btn-primary');
            }


            setButtonActive('#btn-bulk-none');

            $('#btn-bulk-read').click(function(e) {
                e.preventDefault();
                $('input[id^="r_"]').prop('checked', true);
                setButtonActive(this);
            });

            $('#btn-bulk-rw').click(function(e) {
                e.preventDefault();
                $('input[id^="rw_"]').prop('checked', true);
                setButtonActive(this);
            });

            $('#btn-bulk-none').click(function(e) {
                e.preventDefault();
                $('input[id^="n_"]').prop('checked', true);
                setButtonActive(this);
            });


            $('input[type="radio"]').change(function() {
                $('#btn-bulk-read, #btn-bulk-rw, #btn-bulk-none')
                    .removeClass('btn-primary')
                    .addClass('btn-default');
            });
        });
    </script>
@endsection
BLADEEOF
echo "[+] new.blade.php terpasang"

# ---------------------------- .env -----------------------------------
if grep -q "^PTLA_VPS_IPS=" "$ENVF"; then
  sed -i "s|^PTLA_VPS_IPS=.*|PTLA_VPS_IPS=$IP_CSV|" "$ENVF"
else
  printf "\nPTLA_VPS_IPS=%s\n" "$IP_CSV" >> "$ENVF"
fi
echo "[+] .env diisi PTLA_VPS_IPS=$IP_CSV"

# ---------------------------- selesai --------------------------------
fix_owner
clear_cache
echo ""
echo "[OK] Instalasi selesai."
echo "     Whitelist ptla : $IP_CSV (+ 127.0.0.1, ::1, IP server)"
echo "     Backup         : $BK"
echo "     Uninstall      : bash installer.sh uninstall"
echo "     Catatan        : jangan jalankan 'php artisan config:cache' (.env harus terbaca)"
}

# ---------------------------- MENU -----------------------------------
show_menu() {
  while true; do
    echo ""
    echo "=========== PTLA IP PROTECT ==========="
    echo "  1) Install protect"
    echo "  2) Uninstall protect"
    echo "  3) Cek status"
    echo "  0) Keluar"
    echo "======================================="
    read -rp "Pilih [0-3]: " choice </dev/tty
    case "$choice" in
      1)
        read -rp "IP VPS (pisah spasi/koma, boleh ip:port / IPv6, kosong = deteksi otomatis): " ips </dev/tty
        ips="${ips//,/ }"
        # shellcheck disable=SC2086
        do_install $ips
        ;;
      2)
        read -rp "Yakin uninstall protect? [y/N]: " yn </dev/tty
        [[ "$yn" =~ ^[Yy]$ ]] && do_uninstall || echo "Dibatalkan."
        ;;
      3) do_status ;;
      0) echo "Keluar."; exit 0 ;;
      *) echo "Pilihan tidak valid." ;;
    esac
  done
}

# ---------------------------- DISPATCH -------------------------------
case "$1" in
  "")                  show_menu ;;
  install)             shift; do_install "$@" ;;
  uninstall|--restore) do_uninstall ;;
  status)              do_status ;;
  *)                   do_install "$@" ;;   # kompatibel: bash installer.sh 1.2.3.4
esac
