#!/usr/bin/env bash
# Uninstall tema NeoBrutalism untuk Pterodactyl (mandiri, tidak butuh skrip menu lain).
# Mengembalikan panel dari backup panel-backup-*.tar.gz yang dibuat installer.
#
# Pemakaian:  bash uninstall-neobrutalism.sh [PANEL_DIR] [FOLDER_BACKUP]
#   PANEL_DIR      default /var/www/pterodactyl
#   FOLDER_BACKUP  default $HOME (tempat panel-backup-*.tar.gz berada)

PANEL_DIR="${1:-/var/www/pterodactyl}"
USER_HOME="${2:-$HOME}"

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

info_msg() { echo -e "\e[34m[INFO]\e[0m $1"; }
ok_msg()   { echo -e "\e[32m[OK]\e[0m $1"; }
err_msg()  { echo -e "\e[31m[ERROR]\e[0m $1"; }
banner()   { echo -e "\n\e[1m=== $1 ===\e[0m\n"; }

banner "UNINSTALL THEME NEOBRUTALISM"
PANEL_PARENT="$(dirname "$PANEL_DIR")"
PANEL_BASE="$(basename "$PANEL_DIR")"
RESTORE_TMP="$USER_HOME/neo-restore-tmp"

neo_un_fail() {
  err_msg "$1"
  $SUDO rm -rf "$RESTORE_TMP"
  :
}

if [ ! -f "$PANEL_DIR/artisan" ]; then
  neo_un_fail "Pterodactyl Panel tidak ditemukan di $PANEL_DIR."
  exit 1
fi

# Daftar file milik tema NeoBrutalism (semua file di dalam NeoBrutalism.zip).
NEO_FILES="
  app/Http/Controllers/Admin/LocationController.php
  app/Http/Controllers/Admin/Nests/NestController.php
  app/Http/Controllers/Admin/NodesController.php
  app/Http/Controllers/Admin/Settings/IndexController.php
  app/Http/Controllers/Admin/Theme/AlertController.php
  app/Http/Controllers/Admin/Theme/ButtonController.php
  app/Http/Controllers/Admin/Theme/ColorController.php
  app/Http/Controllers/Admin/Theme/ContactController.php
  app/Http/Controllers/Admin/Theme/ElementController.php
  app/Http/Controllers/Admin/Theme/MetaController.php
  app/Http/Controllers/Admin/Theme/PresetController.php
  app/Http/Controllers/Admin/Theme/ProtectionController.php
  app/Http/Controllers/Admin/Theme/SocialController.php
  app/Http/Controllers/Admin/Theme/ThemeController.php
  app/Http/Controllers/Admin/UserController.php
  app/Http/Middleware/Admin/NeoProtection.php
  app/Services/Servers/ServerDeletionService.php
  app/Services/Theme/ThemePresets.php
  app/Services/Theme/ThemeSettings.php
  database/migrations/2021_12_06_134416_create_theme_table.php
  database/migrations/2022_07_27_134330_add_collum_to_theme_table.php
  database/migrations/2026_10_14_000001_neobrutalism_theme_settings.php
  resources/scripts/api/getThemeData.ts
  resources/scripts/api/themeConfig.ts
  resources/scripts/assets/css/GlobalStylesheet.ts
  resources/scripts/components/NavigationBar.tsx
  resources/scripts/components/NavigationBarServer.tsx
  resources/scripts/components/auth/ContactOwner.tsx
  resources/scripts/components/auth/ForgotPasswordContainer.tsx
  resources/scripts/components/auth/LoginCheckpointContainer.tsx
  resources/scripts/components/auth/LoginContainer.tsx
  resources/scripts/components/auth/LoginFormContainer.tsx
  resources/scripts/components/auth/ResetPasswordContainer.tsx
  resources/scripts/components/dashboard/AccountApiContainer.tsx
  resources/scripts/components/dashboard/AccountOverviewContainer.tsx
  resources/scripts/components/dashboard/ApiKeyModal.tsx
  resources/scripts/components/dashboard/DashboardContainer.tsx
  resources/scripts/components/dashboard/ServerCard.tsx
  resources/scripts/components/dashboard/ServerRow.tsx
  resources/scripts/components/dashboard/activity/ActivityLogContainer.tsx
  resources/scripts/components/dashboard/forms/ConfigureTwoFactorForm.tsx
  resources/scripts/components/dashboard/forms/CreateApiKeyForm.tsx
  resources/scripts/components/dashboard/forms/DisableTOTPDialog.tsx
  resources/scripts/components/dashboard/forms/RecoveryTokensDialog.tsx
  resources/scripts/components/dashboard/forms/SetupTOTPDialog.tsx
  resources/scripts/components/dashboard/forms/UpdateEmailAddressForm.tsx
  resources/scripts/components/dashboard/forms/UpdatePasswordForm.tsx
  resources/scripts/components/dashboard/search/SearchContainer.tsx
  resources/scripts/components/dashboard/search/SearchModal.tsx
  resources/scripts/components/dashboard/ssh/AccountSSHContainer.tsx
  resources/scripts/components/dashboard/ssh/CreateSSHKeyForm.tsx
  resources/scripts/components/dashboard/ssh/DeleteSSHKeyButton.tsx
  resources/scripts/components/elements/AuthenticatedRoute.tsx
  resources/scripts/components/elements/Button.tsx
  resources/scripts/components/elements/Can.tsx
  resources/scripts/components/elements/Checkbox.tsx
  resources/scripts/components/elements/Code.tsx
  resources/scripts/components/elements/CodemirrorEditor.tsx
  resources/scripts/components/elements/ConfirmationModal.tsx
  resources/scripts/components/elements/ContentBox.tsx
  resources/scripts/components/elements/ContentContainer.tsx
  resources/scripts/components/elements/CopyOnClick.tsx
  resources/scripts/components/elements/DropdownMenu.tsx
  resources/scripts/components/elements/ErrorBoundary.tsx
  resources/scripts/components/elements/Fade.tsx
  resources/scripts/components/elements/Field.tsx
  resources/scripts/components/elements/FormikFieldWrapper.tsx
  resources/scripts/components/elements/FormikSwitch.tsx
  resources/scripts/components/elements/GreyRowBox.tsx
  resources/scripts/components/elements/Icon.tsx
  resources/scripts/components/elements/Input.tsx
  resources/scripts/components/elements/InputError.tsx
  resources/scripts/components/elements/InputSpinner.tsx
  resources/scripts/components/elements/Label.tsx
  resources/scripts/components/elements/Modal.tsx
  resources/scripts/components/elements/PageContentBlock.tsx
  resources/scripts/components/elements/Pagination.tsx
  resources/scripts/components/elements/PermissionRoute.tsx
  resources/scripts/components/elements/Portal.tsx
  resources/scripts/components/elements/ProgressBar.tsx
  resources/scripts/components/elements/ScreenBlock.tsx
  resources/scripts/components/elements/Select.tsx
  resources/scripts/components/elements/ServerContentBlock.tsx
  resources/scripts/components/elements/Spinner.tsx
  resources/scripts/components/elements/SpinnerOverlay.tsx
  resources/scripts/components/elements/SubNavigation.tsx
  resources/scripts/components/elements/Switch.tsx
  resources/scripts/components/elements/TitledGreyBox.tsx
  resources/scripts/components/elements/Translate.tsx
  resources/scripts/components/elements/activity/ActivityLogEntry.tsx
  resources/scripts/components/elements/activity/ActivityLogMetaButton.tsx
  resources/scripts/components/elements/activity/style.module.css
  resources/scripts/components/elements/alert/Alert.tsx
  resources/scripts/components/elements/alert/index.ts
  resources/scripts/components/elements/button/Button.tsx
  resources/scripts/components/elements/button/index.ts
  resources/scripts/components/elements/button/style.module.css
  resources/scripts/components/elements/button/types.ts
  resources/scripts/components/elements/custom/Alert.tsx
  resources/scripts/components/elements/custom/AlertDescription.tsx
  resources/scripts/components/elements/custom/CollapseBtn.tsx
  resources/scripts/components/elements/custom/DarkModeToggler.tsx
  resources/scripts/components/elements/custom/NavigationBar.tsx
  resources/scripts/components/elements/custom/SocialButtons.tsx
  resources/scripts/components/elements/custom/social/Billing.tsx
  resources/scripts/components/elements/custom/social/Discord.tsx
  resources/scripts/components/elements/custom/social/Knowledgebase.tsx
  resources/scripts/components/elements/custom/social/Status.tsx
  resources/scripts/components/elements/custom/social/Website.tsx
  resources/scripts/components/elements/dialog/ConfirmationDialog.tsx
  resources/scripts/components/elements/dialog/Dialog.tsx
  resources/scripts/components/elements/dialog/DialogFooter.tsx
  resources/scripts/components/elements/dialog/DialogIcon.tsx
  resources/scripts/components/elements/dialog/context.ts
  resources/scripts/components/elements/dialog/index.ts
  resources/scripts/components/elements/dialog/style.module.css
  resources/scripts/components/elements/dialog/types.d.ts
  resources/scripts/components/elements/dropdown/Dropdown.tsx
  resources/scripts/components/elements/dropdown/DropdownButton.tsx
  resources/scripts/components/elements/dropdown/DropdownItem.tsx
  resources/scripts/components/elements/dropdown/index.ts
  resources/scripts/components/elements/dropdown/style.module.css
  resources/scripts/components/elements/inputs/Checkbox.tsx
  resources/scripts/components/elements/inputs/InputField.tsx
  resources/scripts/components/elements/inputs/index.ts
  resources/scripts/components/elements/inputs/styles.module.css
  resources/scripts/components/elements/neo/Meter.tsx
  resources/scripts/components/elements/neo/StatusPill.tsx
  resources/scripts/components/elements/neo/status.ts
  resources/scripts/components/elements/table/PaginationFooter.tsx
  resources/scripts/components/elements/tooltip/Tooltip.tsx
  resources/scripts/components/elements/transitions/FadeTransition.tsx
  resources/scripts/components/elements/transitions/index.ts
  resources/scripts/components/server/ConflictStateRenderer.tsx
  resources/scripts/components/server/InstallListener.tsx
  resources/scripts/components/server/ServerActivityLogContainer.tsx
  resources/scripts/components/server/TransferListener.tsx
  resources/scripts/components/server/UptimeDuration.tsx
  resources/scripts/components/server/WebsocketHandler.tsx
  resources/scripts/components/server/backups/BackupContainer.tsx
  resources/scripts/components/server/backups/BackupContextMenu.tsx
  resources/scripts/components/server/backups/BackupRow.tsx
  resources/scripts/components/server/backups/CreateBackupButton.tsx
  resources/scripts/components/server/console/ChartBlock.tsx
  resources/scripts/components/server/console/Console.tsx
  resources/scripts/components/server/console/PowerButtons.tsx
  resources/scripts/components/server/console/ServerConsoleContainer.tsx
  resources/scripts/components/server/console/ServerDetailsBlock.tsx
  resources/scripts/components/server/console/SideGraph.tsx
  resources/scripts/components/server/console/StatBlock.tsx
  resources/scripts/components/server/console/StatGraphs.tsx
  resources/scripts/components/server/console/TopElement.tsx
  resources/scripts/components/server/console/chart.ts
  resources/scripts/components/server/console/graphs/CPUGraph.tsx
  resources/scripts/components/server/console/graphs/RamGraph.tsx
  resources/scripts/components/server/console/graphs/chart.ts
  resources/scripts/components/server/console/style.module.css
  resources/scripts/components/server/databases/CreateDatabaseButton.tsx
  resources/scripts/components/server/databases/DatabaseRow.tsx
  resources/scripts/components/server/databases/DatabasesContainer.tsx
  resources/scripts/components/server/databases/RotatePasswordButton.tsx
  resources/scripts/components/server/events.ts
  resources/scripts/components/server/features/Features.tsx
  resources/scripts/components/server/features/GSLTokenModalFeature.tsx
  resources/scripts/components/server/features/JavaVersionModalFeature.tsx
  resources/scripts/components/server/features/PIDLimitModalFeature.tsx
  resources/scripts/components/server/features/SteamDiskSpaceFeature.tsx
  resources/scripts/components/server/features/eula/EulaModalFeature.tsx
  resources/scripts/components/server/features/index.ts
  resources/scripts/components/server/files/ChmodFileModal.tsx
  resources/scripts/components/server/files/FileDropdownMenu.tsx
  resources/scripts/components/server/files/FileEditContainer.tsx
  resources/scripts/components/server/files/FileManagerBreadcrumbs.tsx
  resources/scripts/components/server/files/FileManagerContainer.tsx
  resources/scripts/components/server/files/FileManagerStatus.tsx
  resources/scripts/components/server/files/FileNameModal.tsx
  resources/scripts/components/server/files/FileObjectRow.tsx
  resources/scripts/components/server/files/MassActionsBar.tsx
  resources/scripts/components/server/files/NewDirectoryButton.tsx
  resources/scripts/components/server/files/RenameFileModal.tsx
  resources/scripts/components/server/files/SelectFileCheckbox.tsx
  resources/scripts/components/server/files/UploadButton.tsx
  resources/scripts/components/server/files/style.module.css
  resources/scripts/components/server/network/AllocationRow.tsx
  resources/scripts/components/server/network/DeleteAllocationButton.tsx
  resources/scripts/components/server/network/NetworkContainer.tsx
  resources/scripts/components/server/schedules/DeleteScheduleButton.tsx
  resources/scripts/components/server/schedules/EditScheduleModal.tsx
  resources/scripts/components/server/schedules/NewTaskButton.tsx
  resources/scripts/components/server/schedules/RunScheduleButton.tsx
  resources/scripts/components/server/schedules/ScheduleCheatsheetCards.tsx
  resources/scripts/components/server/schedules/ScheduleContainer.tsx
  resources/scripts/components/server/schedules/ScheduleCronRow.tsx
  resources/scripts/components/server/schedules/ScheduleEditContainer.tsx
  resources/scripts/components/server/schedules/ScheduleRow.tsx
  resources/scripts/components/server/schedules/ScheduleTaskRow.tsx
  resources/scripts/components/server/schedules/TaskDetailsModal.tsx
  resources/scripts/components/server/settings/ReinstallServerBox.tsx
  resources/scripts/components/server/settings/RenameServerBox.tsx
  resources/scripts/components/server/settings/SettingsContainer.tsx
  resources/scripts/components/server/startup/StartupContainer.tsx
  resources/scripts/components/server/startup/VariableBox.tsx
  resources/scripts/components/server/users/AddSubuserButton.tsx
  resources/scripts/components/server/users/EditSubuserModal.tsx
  resources/scripts/components/server/users/PermissionRow.tsx
  resources/scripts/components/server/users/PermissionTitleBox.tsx
  resources/scripts/components/server/users/RemoveSubuserButton.tsx
  resources/scripts/components/server/users/UserRow.tsx
  resources/scripts/components/server/users/UsersContainer.tsx
  resources/scripts/lang.tsx
  resources/scripts/lib/neoColors.ts
  resources/scripts/routers/AuthenticationRouter.tsx
  resources/scripts/routers/DashboardRouter.tsx
  resources/scripts/routers/ServerElements.tsx
  resources/scripts/routers/ServerRouter.tsx
  resources/scripts/routers/SideBarElements.tsx
  resources/scripts/routers/routes.ts
  resources/views/admin/theme/alert.blade.php
  resources/views/admin/theme/button.blade.php
  resources/views/admin/theme/color.blade.php
  resources/views/admin/theme/contact.blade.php
  resources/views/admin/theme/element.blade.php
  resources/views/admin/theme/index.blade.php
  resources/views/admin/theme/meta.blade.php
  resources/views/admin/theme/protection.blade.php
  resources/views/admin/theme/social.blade.php
  resources/views/layouts/admin.blade.php
  resources/views/partials/admin/neo-style.blade.php
  resources/views/partials/admin/theme/nav.blade.php
  resources/views/partials/admin/theme/presets.blade.php
  resources/views/partials/admin/theme/preview.blade.php
  resources/views/partials/neo-toast-ajax.blade.php
  resources/views/partials/neo-toast.blade.php
  resources/views/partials/theme-variables.blade.php
  resources/views/templates/wrapper.blade.php
  routes/theme-admin.php
  tailwind.config.js
"

# ---------- Cari backup SEBELUM tema dipasang ----------
# Backup yang sudah berisi neo-style.blade.php dibuat saat install ulang, jadi dilewati.
BACKUP_FILE=""
for CANDIDATE in $(ls -t "$USER_HOME"/panel-backup-*.tar.gz 2>/dev/null); do
  if ! $SUDO tar -tzf "$CANDIDATE" 2>/dev/null | grep -q "resources/views/partials/admin/neo-style.blade.php"; then
    BACKUP_FILE="$CANDIDATE"
    break
  fi
done

if [ -z "$BACKUP_FILE" ]; then
  neo_un_fail "Tidak ada backup panel-backup-*.tar.gz yang dibuat sebelum tema dipasang di $USER_HOME."
  exit 1
fi

info_msg "Backup yang dipakai: $BACKUP_FILE"
read -r -p "Kembalikan panel ke kondisi backup ini? (y/N): " NEO_CONFIRM
if [ "$NEO_CONFIRM" != "y" ] && [ "$NEO_CONFIRM" != "Y" ]; then
  neo_un_fail "Dibatalkan."
  exit 1
fi

$SUDO rm -rf "$RESTORE_TMP"
mkdir -p "$RESTORE_TMP"
info_msg "Mengekstrak backup..."
if ! $SUDO tar -xzf "$BACKUP_FILE" -C "$RESTORE_TMP"; then
  neo_un_fail "Gagal mengekstrak backup."
  exit 1
fi
OLD="$RESTORE_TMP/$PANEL_BASE"

# ---------- Pulihkan / hapus file tema ----------
info_msg "Memulihkan file bawaan dan menghapus file tema..."
for NEO_F in $NEO_FILES; do
  if [ -f "$OLD/$NEO_F" ]; then
    $SUDO mkdir -p "$(dirname "$PANEL_DIR/$NEO_F")"
    $SUDO cp -p "$OLD/$NEO_F" "$PANEL_DIR/$NEO_F"
  else
    $SUDO rm -f "$PANEL_DIR/$NEO_F"
  fi
done

# File lain yang diubah installer: route, dependency, webpack, dan hasil build frontend lama
for NEO_F in routes/admin.php package.json yarn.lock webpack.config.js; do
  [ -f "$OLD/$NEO_F" ] && $SUDO cp -p "$OLD/$NEO_F" "$PANEL_DIR/$NEO_F"
done
if [ -d "$OLD/public/assets" ]; then
  $SUDO rm -rf "$PANEL_DIR/public/assets"
  $SUDO cp -a "$OLD/public/assets" "$PANEL_DIR/public/assets"
fi

# Pastikan tidak ada sisa baris require theme-admin
$SUDO sed -i "/theme-admin\.php/d" "$PANEL_DIR/routes/admin.php"

# Bersihkan folder kosong yang tertinggal
$SUDO find "$PANEL_DIR/app/Services/Theme" "$PANEL_DIR/app/Http/Controllers/Admin/Theme" \
  "$PANEL_DIR/resources/views/admin/theme" "$PANEL_DIR/resources/views/partials/admin/theme" \
  "$PANEL_DIR/resources/scripts/components/elements/neo" -type d -empty -delete 2>/dev/null || true

cd "$PANEL_DIR" || exit 1
info_msg "Membersihkan cache Laravel..."
$SUDO php artisan view:clear
$SUDO php artisan config:clear
$SUDO php artisan route:clear
$SUDO php artisan cache:clear

info_msg "Mengatur permission..."
$SUDO chown -R www-data:www-data "$PANEL_DIR"
$SUDO php artisan queue:restart || true

$SUDO rm -rf "$RESTORE_TMP"

ok_msg "UNINSTALL SUCCESS"
echo "Panel dikembalikan dari : $BACKUP_FILE"
echo "Database                : tidak diubah (kolom tabel theme tetap ada, tidak berbahaya)"
echo "Catatan                 : tekan Ctrl+F5 di browser agar tampilan lama termuat."
exit 0
