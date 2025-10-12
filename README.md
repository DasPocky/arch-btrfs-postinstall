# arch-btrfs-postinstall

![CI](https://github.com/DasPocky/arch-btrfs-postinstall/actions/workflows/lint.yml/badge.svg)

Ein schlankes **Post-Install-Skript** für **Arch Linux** mit **Btrfs**-Root. Es richtet eine solide Basis ein (Pakete, Dienste), aktiviert **Btrfs-Quotas**, konfiguriert **Timeshift** (inkl. Btrfs-Snapshots) und nimmt ein paar sinnvolle Sanity-Checks vor. Das Skript ist **idempotent** und kann gefahrlos mehrfach ausgeführt werden.

> **Hinweis:** Optionale Features werden später ergänzt. Quotas sind bereits aktivierbar und werden automatisch berücksichtigt.

---

## Inhalt

* [Voraussetzungen](#voraussetzungen)
* [Schnellstart (Einzeiler)](#schnellstart-einzeiler)
* [Empfohlene, prüfbare Ausführung](#empfohlene-prüfbare-ausführung)
* [Was das Skript tut](#was-das-skript-tut)
* [Sicherheit & Idempotenz](#sicherheit--idempotenz)
* [Kompatibilität](#kompatibilität)
* [Fehlerbehebung](#fehlerbehebung)
* [Version-Pinning](#version-pinning)
* [Entwicklung & Tests](#entwicklung--tests)
* [Beitragende (Contributing)](#beitragende-contributing)
* [Lizenz](#lizenz)

---

## Voraussetzungen

* Ein laufendes **Arch Linux**-System (bare metal oder VM)
* **Root-Rechte** (via `sudo`)
* **Internetverbindung** (zum Paketinstallieren und Herunterladen des Skripts)
* **Btrfs** als Root-Dateisystem empfohlen (für Quotas & Timeshift-Btrfs-Snapshots). Fällt automatisch auf rsync-Mode zurück, wenn kein Btrfs erkannt wird.

## Schnellstart (Einzeiler)

**Einfachste Variante** – führt das Skript direkt aus dem `main`-Branch aus:

```bash
curl -fsSL https://raw.githubusercontent.com/DasPocky/arch-btrfs-postinstall/main/scripts/post_install.sh | sudo bash -s --
```

> Diese Form ist am kürzesten. Wer den Inhalt vorher prüfen möchte, nutzt die empfohlene Variante unten.

## Empfohlene, prüfbare Ausführung

Downloade, prüfe und führe bewusst aus:

```bash
curl -fsSLo post_install.sh https://raw.githubusercontent.com/DasPocky/arch-btrfs-postinstall/main/scripts/post_install.sh
less post_install.sh   # Inhalt querlesen
chmod +x post_install.sh
sudo ./post_install.sh
```

## Was das Skript tut

* **Basis-Pakete installieren**: `openssh`, `nano`, `timeshift`, `cronie`, `pciutils`, `usbutils`, `smartmontools`, `lm_sensors` u.a.
* **Dienste idempotent aktivieren**: `sshd.service`, `cronie.service`
* **GRUB-Integration (falls GRUB installiert ist)**: `grub-btrfs` + optional `grub-btrfsd.service`
* **Root-FS erkennen**: Typ (Btrfs oder anderes), Quelle/UUID
* **Timeshift konfigurieren**:

  * Bei **Btrfs**: Snapshot-Setup inkl. Standardaufbewahrung (z. B. daily/weekly/monthly)
  * Bei **nicht-Btrfs**: rsync-Modus
  * Ersten Snapshot **nur anlegen, wenn keiner existiert**
* **Btrfs-Quotas**: automatisch **aktivieren**, falls noch nicht aktiv
* **Subvolume-Checks** (z. B. `@`, `@home`, `@log`, `@pkg`), ohne Abbruch
* **Abschließende Statusausgabe** (u. a. Quota-Status)

## Sicherheit & Idempotenz

* Skript läuft mit `set -euo pipefail` und bricht bei Fehlern ab.
* Wiederholte Ausführung ist unkritisch: Paketinstallationen mit `--needed`, `systemctl enable --now` ist idempotent, Quotas werden nur bei Bedarf aktiviert.
* Kein destruktives Repartitionieren/Formatieren. Änderungen sind nachvollziehbar protokolliert.

## Kompatibilität

* **Getestet für Arch Linux**. Andere Distributionen sind nicht vorgesehen.
* **Bootloader**: Zusätzliche Features für **GRUB** (automatische Integration mit `grub-btrfs`). Bei systemd-boot wird dieser Teil übersprungen.
* **Dateisystem**: Btrfs empfohlen; ohne Btrfs fällt Timeshift auf rsync zurück.

## Fehlerbehebung

* **Timeshift meldet kein Btrfs**: Prüfen, ob Root wirklich Btrfs ist (`findmnt -no FSTYPE /`).
* **Quotas lassen sich nicht aktivieren**: Ausgabe von `btrfs quota status -c /` ansehen; ggf. laufende Balances/Scrubs abwarten.
* **GRUB-Menü aktualisiert sich nicht**: Prüfen, ob `grub-btrfs` und `grub-btrfsd.service` installiert/aktiv sind; `sudo systemctl status grub-btrfsd`.
* **CI lint schlägt fehl**: Lokal `shellcheck` und `shfmt` ausführen (siehe Abschnitt unten).

## Version-Pinning

Standardmäßig nutzt der Einzeiler `main`. Für reproduzierbare Setups kannst du auf **Tag** oder **Commit** pinnen:

**Tag pinnen** (Beispiel `v0.1.0`):

```bash
curl -fsSL https://raw.githubusercontent.com/DasPocky/arch-btrfs-postinstall/v0.1.0/scripts/post_install.sh | sudo bash -s --
```

**Commit pinnen** (Beispiel `<COMMIT_SHA>`):

```bash
curl -fsSL https://raw.githubusercontent.com/DasPocky/arch-btrfs-postinstall/<COMMIT_SHA>/scripts/post_install.sh | sudo bash -s --
```

## Entwicklung & Tests

Dieses Repo nutzt **ShellCheck** + **shfmt** in CI (Workflow: `lint.yml`). Lokal prüfen:

```bash
# ShellCheck
shellcheck scripts/post_install.sh

# shfmt (nur Diff anzeigen)
shfmt -d -i 2 -ci -sr scripts/post_install.sh

# shfmt (Datei überschreiben/formatieren)
shfmt -w -i 2 -ci -sr scripts/post_install.sh
```

> CI-Status: ![CI](https://github.com/DasPocky/arch-btrfs-postinstall/actions/workflows/lint.yml/badge.svg)

## Beitragende (Contributing)

1. Forken & Branch erstellen (`feat/…`, `fix/…`).
2. Änderungen vornehmen und lokal mit ShellCheck/shfmt prüfen.
3. Sinnvolle Commits (kleine, thematisch fokussierte Schritte).
4. Pull Request eröffnen – gern mit kurzer Beschreibung **was** und **warum**.

## Lizenz

Wird noch festgelegt. Vorschlag: **MIT** oder **BSD-2-Clause** für maximale Wiederverwendbarkeit.

---

**Kurzlink zum Einzeiler (main):**

```bash
curl -fsSL https://raw.githubusercontent.com/DasPocky/arch-btrfs-postinstall/main/scripts/post_install.sh | sudo bash -s --
```
