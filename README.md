# arch-bootstrap-btrfs

Minimales Post-Install-Skript für saubere Arch-Installationen mit **Btrfs**, **Timeshift** (inkl. `@home`), **Quotas** und Grunddiensten. Ziel: Ein neuer Host ist in wenigen Minuten reproduzierbar konfiguriert **und** sofort per Snapshot gesichert.

> **Status:** Minimalstart. Nach und nach kommen optionale Module (Firewall, SSH-Härtung, GRUB/UKI, Scrub/Balance-Timer, Remote-Backups, AUR-Builder, Desktop etc.) als separate Commits/Ordner dazu.

---

## Inhalte

* `post_install.sh` – idempotentes Basis-Skript (Btrfs-Setup, Timeshift, Quotas, initialer Snapshot, Basispakete & Dienste)
* `LICENSE` – MIT
* `.editorconfig` – einheitlicher Stil
* `.gitattributes` – LF-Enforcement für Shell
* `.github/` – später: CI, Issue-Templates, PR-Checks

---

## Quickstart (Einzeiler)

> Führe diesen Einzeiler **auf einem frisch installierten Arch** als `root` oder mit `sudo` aus. Er zieht die aktuelle Version direkt von GitHub, macht sie ausführbar und startet sie. Ersetzt `<BRANCH_OR_TAG>` durch einen Tag wie `v0.1.0` oder nutzt `main`.

```bash
bash -c "set -euo pipefail; tmpdir=$(mktemp -d); trap 'rm -rf \"$tmpdir\"' EXIT; cd \"$tmpdir\"; curl -fsSL https://raw.githubusercontent.com/<DEIN-USER>/arch-bootstrap-btrfs/<BRANCH_OR_TAG>/post_install.sh -o post_install.sh; chmod +x post_install.sh; sudo ./post_install.sh"
```

**Hinweis:** Das Skript ist defensiv und stoppt, wenn erkennbare Risiken bestehen (z.B. falscher Root-FS-Typ). Es ist weitgehend idempotent, d.h. wiederholte Ausführung ist möglich, ohne kaputte Zustände zu erzeugen.

---

## Was macht das Skript?

* **Btrfs-Root erkennen** (`/` auf Btrfs, Subvols `@`, `@home`, `@log`, `@pkg` validieren)
* **Btrfs-Quotas aktivieren** (für korrekte Platz-/Snapshot-Abrechnung)
* **Timeshift konfigurieren** (Btrfs-Modus, `@home` *Backup+Restore*)
* **Initialen Snapshot** anlegen ("Basiszustand (Post-Install, Root+Home)")
* **Basispakete** installieren: `openssh`, `nano`, `timeshift`, `cronie`, `pciutils`, `usbutils`, `smartmontools`, `lm_sensors`
* **Basisdienste** idempotent aktivieren: `sshd`, `cronie`, `systemd-timesyncd`
* **Cron-Policy** für Timeshift: tägliche/wöchentliche/monatliche Aufbewahrung
* **Systemreport** erzeugen (Hardware/FS/Netz/Boot/Timeshift) in `$HOME/arch-system-report_*.txt`

---

## Sicherheitsnetz & Wiederherstellung

* Timeshift-Snapshots (Btrfs) sind **subvol-basiert**. Ein Rollback auf den letzten guten Stand ist im Notfall per Timeshift-GUI, `timeshift --restore` oder manuell via Subvol-Umhängung möglich.
* Das Skript prüft vor Änderungen den Root-FS-Typ, UUIDs und Mounts.

---

## Voraussetzungen

* Frische Arch-Installation mit Btrfs-Layout und Subvolumes `@`, `@home`, `@log`, `@pkg`
* Internetzugang für Paketinstallationen

Optional hilfreich:

* SSH-Zugang (z.B. Headless-Setups)

---

## Lizenz

MIT License – siehe `LICENSE`.

---

Verbesserungsvorschläge & PRs willkommen 🙂
