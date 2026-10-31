#!/bin/bash
# =====================================================================
#  Installer: Whitelist IP otomatis untuk API key ptla (Pterodactyl)
#
#  Pakai:
#    bash installer.sh                 -> IP VPS dideteksi otomatis
#    bash installer.sh 1.2.3.4         -> pakai IP manual
#    bash installer.sh --restore       -> kembalikan file dari backup terakhir
#
#  Opsional: PANEL_DIR=/path/panel bash installer.sh
# =====================================================================

PANEL="${PANEL_DIR:-/var/www/pterodactyl}"
CTRL="$PANEL/app/Http/Controllers/Admin/ApiController.php"
VIEW="$PANEL/resources/views/admin/api/new.blade.php"
MW="$PANEL/app/Http/Middleware/Api/AuthenticateIPAccess.php"
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
  chown "$OWNER" "$CTRL" "$VIEW" 2>/dev/null
}

# ---------------------------- RESTORE --------------------------------
if [ "$1" = "--restore" ]; then
  LAST=$(ls -1dt "$BACKUP_ROOT"/*/ 2>/dev/null | head -n1)
  if [ -z "$LAST" ]; then
    echo "[!] Tidak ada backup di $BACKUP_ROOT"
    exit 1
  fi
  cp "$LAST/ApiController.php" "$CTRL" 2>/dev/null && echo "[+] ApiController dikembalikan"
  cp "$LAST/new.blade.php" "$VIEW" 2>/dev/null && echo "[+] new.blade.php dikembalikan"
  [ -f "$LAST/AuthenticateIPAccess.php" ] && cp "$LAST/AuthenticateIPAccess.php" "$MW" && echo "[+] Middleware dikembalikan"
  fix_owner
  clear_cache
  echo "[OK] Restore selesai dari $LAST"
  exit 0
fi

# ---------------------------- DETEKSI IP -----------------------------
IP="$1"
if [ -z "$IP" ]; then
  IP=$(curl -4 -s --max-time 8 ifconfig.me)
fi
if ! echo "$IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "[!] IPv4 tidak valid / gagal terdeteksi: '$IP'"
  echo "    Jalankan: bash installer.sh IP_VPS_KAMU"
  exit 1
fi
echo "[*] IP VPS yang di-whitelist: $IP"

# ---------------------------- BACKUP ---------------------------------
BK="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
cp "$CTRL" "$BK/ApiController.php"
cp "$VIEW" "$BK/new.blade.php"
[ -f "$MW" ] && cp "$MW" "$BK/AuthenticateIPAccess.php"
echo "[+] Backup tersimpan di $BK"

# ---------------------------- MIDDLEWARE -----------------------------
# Kalau sebelumnya memasang middleware custom, kembalikan ke bawaan
if [ -f "$MW" ] && grep -q "PTLA_VPS_IPS" "$MW"; then
  ORIG=$(ls -1t "$PANEL"/app/Http/Middleware/Api/AuthenticateIPAccess.php.bak* 2>/dev/null | head -n1)
  if [ -n "$ORIG" ]; then
    cp "$ORIG" "$MW"
    echo "[+] Middleware custom dikembalikan dari $ORIG"
  else
    echo "[!] Middleware custom terdeteksi tapi backup asli tidak ditemukan."
    echo "    Kembalikan manual / jalankan: cd $PANEL && php artisan p:upgrade"
  fi
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
     * Whitelist IP VPS otomatis ditambahkan ke setiap key ptla yang dibuat.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     */
    public function store(StoreApplicationApiKeyRequest $request): RedirectResponse
    {
        $ips = array_values(array_unique(array_filter(array_merge(
            ['127.0.0.1', '::1', $_SERVER['SERVER_ADDR'] ?? null],
            array_map('trim', explode(',', (string) env('PTLA_VPS_IPS', '')))
        ))));

        $this->keyCreationService->setKeyType(ApiKey::TYPE_APPLICATION)->handle([
            'memo' => $request->input('memo'),
            'user_id' => $request->user()->id,
            'allowed_ips' => $ips,
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
                            <input id="whitelistIpField" type="text" class="form-control" value="{{ env('PTLA_VPS_IPS', $_SERVER['SERVER_ADDR'] ?? '') }}" readonly>
                            <p class="text-muted small" style="margin-top: 5px;">Key ini hanya bisa dipakai dari IP VPS di atas. Request dari IP lain otomatis ditolak.</p>
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
ENVF="$PANEL/.env"
if grep -q "^PTLA_VPS_IPS=" "$ENVF"; then
  sed -i "s|^PTLA_VPS_IPS=.*|PTLA_VPS_IPS=$IP|" "$ENVF"
else
  printf "\nPTLA_VPS_IPS=%s\n" "$IP" >> "$ENVF"
fi
echo "[+] .env diisi PTLA_VPS_IPS=$IP"

# ---------------------------- key ptla lama --------------------------
cd "$PANEL" || exit 1
clear_cache
php artisan tinker --execute="\Pterodactyl\Models\ApiKey::where('key_type', 2)->update(['allowed_ips' => ['127.0.0.1', '::1', '$IP']]); echo 'ok';" >/dev/null 2>&1 \
  && echo "[+] Semua key ptla lama sudah di-whitelist" \
  || echo "[!] Gagal update key lama otomatis (tidak masalah, key baru tetap ter-whitelist)"

# ---------------------------- selesai --------------------------------
fix_owner
clear_cache
echo ""
echo "[OK] Instalasi selesai."
echo "     Whitelist IP ptla : 127.0.0.1, ::1, $IP"
echo "     Backup            : $BK"
echo "     Kembalikan        : bash installer.sh --restore"
