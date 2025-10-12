#!/usr/bin/env bash
# shellcheck disable=SC2312
set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------
# Arch Post-Install (BTRFS + Timeshift + Quotas + Basics)
# - idempotent
# - defensiv (prüft Root-FS, Subvols)
# - legt initialen Snapshot an (Root+Home)
# ------------------------------------------------------------

# Farben/Logging
log() { printf "\e[1;32m== %s ==\e[0m\n" "$*"; }
warn() { printf "\e[1;33m[WARN] %s\e[0m\n" "$*"; }
err() { printf "\e[1;31m[FEHLER] %s\e[0m\n" "$*"; }

# Root erzwingen (oder sauber abbrechen)
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  err "Bitte als root ausführen (sudo)."
  exit 1
fi

# Sichere tmp-Verzeichnisse
WORK_MNT="/run/_svchk"
mkdir -p "$WORK_MNT"
cleanup() {
  if mountpoint -q "$WORK_MNT"; then
    umount "$WORK_MNT" || true
  fi
  rmdir "$WORK_MNT" 2> /dev/null || true
}
trap cleanup EXIT

# ------------------------------------------------------------
# Paketgrundlage
# ------------------------------------------------------------
log "Paketgrundlage prüfen/installieren"
pacman -Sy --needed --noconfirm \
  openssh nano timeshift cronie \
  pciutils usbutils smartmontools lm_sensors > /dev/null

# grub-btrfs (nur wenn GRUB vorhanden)
if pacman -Qq grub > /dev/null 2>&1; then
  pacman -Sy --needed --noconfirm grub-btrfs inotify-tools > /dev/null || true
fi

# ------------------------------------------------------------
# Dienste idempotent aktivieren
# ------------------------------------------------------------
log "Dienste (idempotent) aktivieren"
systemctl enable --now sshd.service > /dev/null 2>&1 || true
systemctl enable --now cronie.service > /dev/null 2>&1 || true
# timesyncd ist unter Arch in systemd enthalten – optional aktivieren:
if systemctl list-unit-files | grep -q '^systemd-timesyncd\.service'; then
  systemctl enable --now systemd-timesyncd.service > /dev/null 2>&1 || true
fi
# grub-btrfsd nur aktivieren, wenn vorhanden
if systemctl list-unit-files | grep -q '^grub-btrfsd\.service'; then
  systemctl enable --now grub-btrfsd.service > /dev/null 2>&1 || true
fi

# ------------------------------------------------------------
# Root-Dateisystem erkennen
# ------------------------------------------------------------
log "Root-Dateisystem erkennen"
ROOT_SRC="$(findmnt -no SOURCE /)"
ROOT_FSTYPE="$(findmnt -no FSTYPE /)"
ROOT_DEV="${ROOT_SRC%%[*}"                                # /dev/nvme0n1pX (wenn subvol)
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_DEV" || true)" # FS-UUID

printf "Root-FS:  FSTYPE=%s\nRoot-Src: SOURCE=%s\nBlockdev: %s\nUUID:     %s\n" \
  "$ROOT_FSTYPE" "$ROOT_SRC" "$ROOT_DEV" "${ROOT_UUID:-unbekannt}"

if [[ "$ROOT_FSTYPE" != "btrfs" ]]; then
  err "Root ist kein BTRFS. Dieses Skript ist für BTRFS-Root konzipiert."
  exit 1
fi

# ------------------------------------------------------------
# Timeshift-Modus & Konfiguration
# ------------------------------------------------------------
TS_MODE="btrfs"
TSCFG="/etc/timeshift/timeshift.json"

log "Timeshift konfigurieren (Modus: $TS_MODE)"
# Mit @home sichern und wiederherstellen, Standard-Aufbewahrung
# Werte als Strings (Timeshift-Format)
cat > "$TSCFG" <<EOF
{
  "backup_device_uuid" : "${ROOT_UUID:-}",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup" : "true",
  "include_btrfs_home_for_restore" : "true",
  "schedule_monthly" : "true",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "count_monthly" : "3",
  "count_weekly" : "4",
  "count_daily" : "7",
  "snapshot_size_estimate" : "false",
  "stop_cron_emails" : "true",
  "skip_grub_update" : "false"
}
EOF

# alternativer historischer Pfad, falls Timeshift ihn erwartet
cp -f "$TSCFG" /etc/timeshift.json > /dev/null 2>&1 || true

# ------------------------------------------------------------
# BTRFS: Subvolumes kurz prüfen (ohne Abbruch)
# ------------------------------------------------------------
log "Subvolume-Prüfung (@, @home, @log, @pkg)"
if mount -o subvolid=0 "$ROOT_DEV" "$WORK_MNT" 2> /dev/null; then
  for SV in "@" "@home" "@log" "@pkg"; do
    if [[ -d "$WORK_MNT/$SV" ]]; then
      echo " - gefunden: $SV"
    else
      warn " - fehlt: $SV (nicht kritisch)"
    fi
  done
  umount "$WORK_MNT" || true
else
  warn "Konnte Top-Level (subvolid=0) nicht mounten – Subvol-Prüfung übersprungen."
fi

# ------------------------------------------------------------
# BTRFS: Quotas aktivieren
# ------------------------------------------------------------
log "BTRFS-Quotas aktivieren (falls noch nicht aktiv)"
if btrfs quota status -c / 2> /dev/null | grep -q "not enabled"; then
  if btrfs quota enable / 2> /dev/null; then
    echo " - Quotas aktiviert."
  else
    warn " - Konnte Quotas nicht aktivieren (weiter ohne Quotas)."
  fi
else
  echo " - Quotas bereits aktiv."
fi

# ------------------------------------------------------------
# Initial-Backup (einmalig, falls nicht vorhanden)
# ------------------------------------------------------------
log "Initial-Backup (einmalig, falls nicht vorhanden)"
HAS_SNAP="0"
if timeshift --list 2> /dev/null | grep -qE '^[[:space:]]*[0-9]+[[:space:]]+>'; then
  HAS_SNAP="1"
fi

if [[ "$HAS_SNAP" == "0" ]]; then
  if timeshift --create --comments "Basiszustand (Post-Install, Root+Home)" --tags D 2> /dev/null; then
    echo " - Initialer Snapshot erstellt."
  else
    warn " - Konnte keinen initialen Snapshot erstellen (Timeshift-CLI meldete Fehler)."
  fi
else
  echo " - Snapshot(s) bereits vorhanden – kein Initial-Snapshot nötig."
fi

# ------------------------------------------------------------
# kurzer Systemreport für den Operator
# ------------------------------------------------------------
DATE_TAG="$(date +%F_%H%M%S)"
REPORT="/root/arch-system-report_${DATE_TAG}.txt"
{
  echo "=== Arch Post-Install Report ($DATE_TAG) ==="
  echo
  echo "[Root-FS]"
  printf "FSTYPE=%s SOURCE=%s DEV=%s UUID=%s\n\n" "$ROOT_FSTYPE" "$ROOT_SRC" "$ROOT_DEV" "${ROOT_UUID:-unbekannt}"
  echo "[LSBLK]"
  lsblk -f
  echo
  echo "[BTRFS Subvols - /]"
  btrfs subvolume list -p / 2> /dev/null || true
  echo
  echo "[Quota-Status]"
  btrfs quota status -c / 2> /dev/null || true
  echo
  echo "[Timeshift --list]"
  timeshift --list 2> /dev/null || true
} > "$REPORT"

# zusätzlich dem SUDO_USER (falls vorhanden) eine Kopie ins $HOME legen
if [[ -n "${SUDO_USER:-}" ]]; then
  USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)"
  if [[ -n "$USER_HOME" && -d "$USER_HOME" ]]; then
    cp -f "$REPORT" "$USER_HOME"/ 2> /dev/null || true
    chown "$SUDO_USER":"$SUDO_USER" "$USER_HOME/$(basename "$REPORT")" 2> /dev/null || true
  fi
fi

# ------------------------------------------------------------
# DONE
# ------------------------------------------------------------
log "FERTIG"
echo "System ist betriebsbereit. Timeshift konfiguriert (Modus: $TS_MODE)."
btrfs quota status -c / 2> /dev/null | sed 's/^/Quota-Status: /' || true
