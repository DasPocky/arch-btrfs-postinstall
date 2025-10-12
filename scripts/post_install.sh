#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Arch Linux Post-Install (BTRFS + Timeshift, Quotas aktiviert)
# -----------------------------------------------------------------------------
# Ziel:
# - Basispakete: openssh, nano, timeshift, cronie (+ Basis-Tools)
# - Dienste idempotent aktivieren (sshd, cronie, grub-btrfsd wenn vorhanden)
# - Root-FS erkennen (BTRFS bevorzugt, fallback: RSYNC)
# - Timeshift (BTRFS) sauber konfigurieren, @home einschließen
# - BTRFS-Quotas aktivieren (für bessere Speicherabrerechnung)
# - Ersten Snapshot nur anlegen, wenn noch keiner existiert
# - Robust gegen Mehrfachausführung (keine Endlosschleifen / Rückfragen)
#
# Hinweise:
# - Skript kann mit normalem Nutzer via sudo aufgerufen werden.
# - Keine interaktiven Pacman-Abfragen (–noconfirm).
# -----------------------------------------------------------------------------

set -Eeuo pipefail

# --- Root-Rechte sicherstellen ------------------------------------------------
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo -p "[sudo] Passwort für %u: " bash "$0" "$@"
fi

# --- Hilfsfunktionen ----------------------------------------------------------
log()  { printf "\e[1;32m== %s ==\e[0m\n" "$*"; }
warn() { printf "\e[1;33m[WARN] %s\e[0m\n" "$*"; }
err()  { printf "\e[1;31m[FEHLER] %s\e[0m\n" "$*"; }

# Sichere tmp-Verzeichnisse
WORK_MNT="/run/_svchk"
trap 'umount -q "${WORK_MNT}" 2>/dev/null || true' EXIT

# --- Paketbasis ---------------------------------------------------------------
log "Paketgrundlage prüfen/installieren"
pacman -Sy --needed --noconfirm \
  openssh nano timeshift cronie \
  pciutils usbutils smartmontools lm_sensors >/dev/null

# grub-btrfs (nur wenn GRUB genutzt oder Paket verfügbar ist)
if pacman -Qq grub >/dev/null 2>&1; then
  pacman -Sy --needed --noconfirm grub-btrfs inotify-tools >/dev/null || true
fi

# --- Dienste idempotent aktivieren -------------------------------------------
log "Dienste (idempotent) aktivieren"
systemctl enable --now sshd.service   >/dev/null 2>&1 || true
systemctl enable --now cronie.service >/dev/null 2>&1 || true
# grub-btrfsd nur aktivieren, wenn vorhanden
if systemctl list-unit-files | grep -q '^grub-btrfsd\.service'; then
  systemctl enable --now grub-btrfsd.service >/dev/null 2>&1 || true
fi

# --- Root-Dateisystem erkennen ------------------------------------------------
log "Root-Dateisystem erkennen"
ROOT_SRC="$(findmnt -no SOURCE /)"
ROOT_FSTYPE="$(findmnt -no FSTYPE /)"
ROOT_DEV="${ROOT_SRC%%[*}"                                  # /dev/nvme0n1p2
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_DEV" || true)"   # FS-UUID
printf "Root-FS:  FSTYPE=%s\nRoot-Src: SOURCE=%s\nBlockdev: %s\nUUID:     %s\n" \
  "$ROOT_FSTYPE" "$ROOT_SRC" "$ROOT_DEV" "${ROOT_UUID:-unbekannt}"

# --- Timeshift-Modus bestimmen -----------------------------------------------
TS_MODE="rsync"
if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
  TS_MODE="btrfs"
  log "Timeshift-Modus: BTRFS"
else
  log "Timeshift-Modus: RSYNC (Root ist kein BTRFS)"
fi

# --- Timeshift-Konfiguration schreiben ---------------------------------------
log "Timeshift-Konfiguration schreiben"
install -d -m 755 /etc/timeshift
TSCFG="/etc/timeshift/timeshift.json"

if [[ "$TS_MODE" == "btrfs" ]]; then
  cat >"$TSCFG" <<EOF
{
  "backup_device_uuid" : "${ROOT_UUID:-}",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup"  : "true",
  "include_btrfs_home_for_restore" : "true",
  "schedule_monthly" : "true",
  "schedule_weekly"  : "true",
  "schedule_daily"   : "true",
  "schedule_hourly"  : "false",
  "schedule_boot"    : "false",
  "count_monthly" : "3",
  "count_weekly"  : "4",
  "count_daily"   : "7",
  "count_hourly"  : "0",
  "count_boot"    : "0"
}
EOF
else
  cat >"$TSCFG" <<'EOF'
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "false",
  "include_btrfs_home_for_backup"  : "false",
  "include_btrfs_home_for_restore" : "false",
  "schedule_monthly" : "true",
  "schedule_weekly"  : "true",
  "schedule_daily"   : "true",
  "schedule_hourly"  : "false",
  "schedule_boot"    : "false",
  "count_monthly" : "3",
  "count_weekly"  : "4",
  "count_daily"   : "7",
  "count_hourly"  : "0",
  "count_boot"    : "0"
}
EOF
fi
cp -f "$TSCFG" /etc/timeshift.json >/dev/null 2>&1 || true  # alternativer Pfad

# --- BTRFS: Subvolumes kurz prüfen (ohne Abbruch) ----------------------------
if [[ "$TS_MODE" == "btrfs" ]]; then
  log "Subvolume-Prüfung (@, @home, @log, @pkg)"
  mkdir -p "$WORK_MNT"
  if mount -o subvolid=0 "$ROOT_DEV" "$WORK_MNT" 2>/dev/null; then
    for SV in "@" "@home" "@log" "@pkg"; do
      [[ -d "$WORK_MNT/$SV" ]] && echo " - gefunden: $SV" || warn " - fehlt: $SV (nicht kritisch)"
    done
    umount "$WORK_MNT" || true
  else
    warn "Top-Level (subvolid=0) konnte nicht eingehängt werden (Überspringe Check)."
  fi
fi

# --- BTRFS: Quotas aktivieren -------------------------------------------------
if [[ "$TS_MODE" == "btrfs" ]]; then
  log "BTRFS-Quotas aktivieren (falls noch nicht aktiv)"
  if btrfs quota status -c / 2>/dev/null | grep -q "not enabled"; then
    if btrfs quota enable / 2>/dev/null; then
      echo " - Quotas aktiviert."
    else
      warn " - Konnte Quotas nicht aktivieren (weiter ohne Quotas)."
    fi
  else
    echo " - Quotas sind bereits aktiv."
  fi
fi

# --- Timeshift: Snapshot-Liste (vorher) --------------------------------------
log "Snapshot-Liste (vorher)"
timeshift --list || true

# --- Timeshift: Ersten Snapshot nur bei Bedarf anlegen -----------------------
log "Initial-Backup (einmalig, falls nicht vorhanden)"
HAS_SNAP="0"
if timeshift --list 2>/dev/null | grep -qE '^[[:space:]]*[0-9]+[[:space:]]+>'; then
  HAS_SNAP="1"
fi
if [[ "$HAS_SNAP" == "0" ]]; then
  DESC="Basiszustand (Post-Install, Root+Home)"
  if timeshift --create --comments "$DESC"; then
    echo " - Initialer Snapshot erstellt."
  else
    warn " - Snapshot-Erstellung fehlgeschlagen (Timeshift prüft beim nächsten Lauf erneut)."
  fi
else
  echo " - Bereits mindestens ein Snapshot vorhanden – überspringe."
fi

# --- Timeshift: Snapshot-Liste (nachher) -------------------------------------
log "Snapshot-Liste (nachher)"
timeshift --list || true

# --- Zusammenfassung ----------------------------------------------------------
log "FERTIG"
echo "System ist betriebsbereit. Timeshift konfiguriert (Modus: $TS_MODE)."
if [[ "$TS_MODE" == "btrfs" ]]; then
  btrfs quota status -c / 2>/dev/null | sed 's/^/Quota-Status: /' || true
fi
