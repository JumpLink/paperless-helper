# WebDAV zu Paperless Synchronisation

Script zum rekursiven Kopieren von PDF-Dateien aus einem WebDAV-Verzeichnis (z.B. gemountete Nextcloud) in das Paperless-ngx Consume-Verzeichnis.

## 📋 Übersicht

Dieses Script findet alle PDF-Dateien rekursiv in einem Quellverzeichnis (z.B. einem gemounteten Nextcloud WebDAV-Verzeichnis) und kopiert sie in das Paperless-ngx Consume-Verzeichnis zur automatischen Verarbeitung.

## 🚀 Schnellstart

### 1. Abhängigkeiten installieren

```bash
# davfs2 für WebDAV-Mount installieren
sudo apt-get install davfs2  # Debian/Ubuntu
# oder
sudo dnf install davfs2      # Fedora/RHEL

# Benutzer zur davfs2-Gruppe hinzufügen
sudo usermod -aG davfs2 $USER
# Danach neu einloggen oder: newgrp davfs2
```

### 2. Konfiguration

```bash
cd paperless
cp .env.example .env
nano .env
```

Bearbeite die `.env` Datei und setze:
- `WEBDAV_URL`: WebDAV-URL (z.B. `https://box.mailfreun.de/cloud/remote.php/webdav/`)
- `WEBDAV_MOUNT_POINT`: Mount-Punkt (z.B. `/mnt/nextcloud`)
- `WEBDAV_USER`: Benutzername (oder leer lassen für interaktive Eingabe)
- `WEBDAV_PASS`: Passwort (oder leer lassen für interaktive Eingabe)
- `WEBDAV_SOURCE_DIR`: Pfad zum gemounteten WebDAV-Verzeichnis (z.B. `/mnt/nextcloud/documents`)
- `PAPERLESS_CONSUME_DIR`: Paperless Consume-Verzeichnis (Standard: `/data/paperless/consume`)
- `PAPERLESS_PRESERVE_STRUCTURE`: `true` um Verzeichnisstruktur beizubehalten, `false` für flache Struktur

### 3. WebDAV mounten

```bash
# Script ausführbar machen
chmod +x mount-webdav.sh

# WebDAV mounten
./mount-webdav.sh mount

# Status prüfen
./mount-webdav.sh status
```

### 4. Synchronisation ausführen

```bash
# Normale Ausführung
./sync-webdav-to-paperless.sh

# Dry-Run (Test ohne Kopieren)
./sync-webdav-to-paperless.sh --dry-run --verbose

# Mit Kommandozeilen-Optionen
./sync-webdav-to-paperless.sh -s /mnt/nextcloud -t /data/paperless/consume
```

## 📖 Verwendung

### WebDAV Mount-Script

```bash
# WebDAV mounten
./mount-webdav.sh mount

# WebDAV unmounten
./mount-webdav.sh unmount

# Status prüfen
./mount-webdav.sh status

# Mit ausführlicher Ausgabe
./mount-webdav.sh mount --verbose
```

**Wichtige Hinweise:**
- Das Script benötigt `sudo`-Rechte für mount/umount
- Zugangsdaten werden in `.env` gespeichert
- Falls keine Zugangsdaten in `.env` konfiguriert sind, fragt das Script interaktiv danach

### Synchronisations-Script

#### Kommandozeilen-Optionen

```bash
./sync-webdav-to-paperless.sh [OPTIONS]

Optionen:
  -s, --source DIR      Quellverzeichnis (WebDAV-Mount)
  -t, --target DIR      Zielverzeichnis (Paperless Consume)
  -d, --dry-run         Nur anzeigen, keine Dateien kopieren
  -v, --verbose         Ausführliche Ausgabe
  -h, --help            Hilfe anzeigen
```

### Umgebungsvariablen (.env)

| Variable | Beschreibung | Standard |
|----------|--------------|----------|
| `WEBDAV_URL` | WebDAV-URL (z.B. `https://box.mailfreun.de/cloud/remote.php/webdav/`) | - |
| `WEBDAV_MOUNT_POINT` | Mount-Punkt für WebDAV (z.B. `/mnt/nextcloud`) | - |
| `WEBDAV_USER` | WebDAV-Benutzername (oder leer für interaktive Eingabe) | - |
| `WEBDAV_PASS` | WebDAV-Passwort (oder leer für interaktive Eingabe) | - |
| `WEBDAV_SOURCE_DIR` | Quellverzeichnis (WebDAV-Mount) | - |
| `PAPERLESS_CONSUME_DIR` | Zielverzeichnis (Paperless Consume) | `/data/paperless/consume` |
| `PAPERLESS_PRESERVE_STRUCTURE` | Struktur beibehalten (`true`/`false`) | `false` |

## 🔧 Konfiguration

### Struktur beibehalten

Wenn `PAPERLESS_PRESERVE_STRUCTURE=true` gesetzt ist, wird die Verzeichnisstruktur beibehalten:

```
Quelle: /mnt/nextcloud/documents/
├── 2025/
│   └── rechnung.pdf
└── buchhaltung/
    └── eingang.pdf

Ziel: /data/paperless/consume/
├── 2025/
│   └── rechnung.pdf
└── buchhaltung/
    └── eingang.pdf
```

**Wichtig:** Für diese Funktion muss in Paperless-ngx `PAPERLESS_CONSUMER_RECURSIVE=true` aktiviert sein (siehe [Paperless-ngx README](../../../docs/services/paperless-ngx/README.md)).

Wenn `PAPERLESS_PRESERVE_STRUCTURE=false` (Standard), werden alle PDFs direkt ins Consume-Verzeichnis kopiert:

```
Quelle: /mnt/nextcloud/documents/2025/rechnung.pdf
Ziel: /data/paperless/consume/rechnung.pdf
```

### Duplikate

Das Script überspringt automatisch Dateien, die bereits im Zielverzeichnis existieren (basierend auf dem Dateinamen).

## 🔄 Automatisierung

### Vollständiger Workflow (Mount + Sync)

Für einen vollständigen automatisierten Workflow, der zuerst das WebDAV mountet und dann synchronisiert:

```bash
#!/bin/bash
# /path/to/webdav-paperless-workflow.sh

SCRIPT_DIR="/path/to/paperless/skripte/webdav-to-paperless"
cd "$SCRIPT_DIR"

# WebDAV mounten
./mount-webdav.sh mount

# Synchronisieren
./sync-webdav-to-paperless.sh

# Optional: WebDAV unmounten (wenn nicht dauerhaft gemountet bleiben soll)
# ./mount-webdav.sh unmount
```

### Cron-Job einrichten

Für regelmäßige Synchronisation kann ein Cron-Job eingerichtet werden:

```bash
# Crontab bearbeiten
crontab -e

# Beispiel: Täglich um 2 Uhr morgens (mit Mount)
0 2 * * * /path/to/webdav-paperless-workflow.sh >> /var/log/webdav-paperless-sync.log 2>&1

# Oder nur Synchronisation (wenn WebDAV dauerhaft gemountet ist)
0 2 * * * /path/to/paperless/skripte/webdav-to-paperless/sync-webdav-to-paperless.sh >> /var/log/webdav-paperless-sync.log 2>&1
```

### Systemd Timer (Alternative)

Erstelle eine Systemd-Service-Datei für bessere Integration:

```ini
# /etc/systemd/system/webdav-paperless-sync.service
[Unit]
Description=Sync WebDAV to Paperless-ngx
After=network-online.target

[Service]
Type=oneshot
User=paperless
WorkingDirectory=/path/to/paperless
ExecStart=/path/to/paperless/skripte/webdav-to-paperless/sync-webdav-to-paperless.sh
EnvironmentFile=/path/to/paperless/.env

[Install]
WantedBy=multi-user.target
```

```ini
# /etc/systemd/system/webdav-paperless-sync.timer
[Unit]
Description=Daily sync WebDAV to Paperless-ngx
Requires=webdav-paperless-sync.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

Aktivieren:
```bash
sudo systemctl enable webdav-paperless-sync.timer
sudo systemctl start webdav-paperless-sync.timer
```

## 📝 Logging

Das Script gibt Statusinformationen auf der Konsole aus:
- `[INFO]`: Allgemeine Informationen
- `[OK]`: Erfolgreiche Operationen
- `[WARN]`: Warnungen (z.B. übersprungene Dateien)
- `[ERROR]`: Fehler

Mit `--verbose` werden zusätzliche Details ausgegeben.

## ⚠️ Wichtige Hinweise

1. **davfs2 Installation**: Das Mount-Script benötigt `davfs2`. Installiere es mit `sudo apt-get install davfs2` oder `sudo dnf install davfs2`.

2. **Benutzer-Gruppe**: Der Benutzer muss in der `davfs2`-Gruppe sein: `sudo usermod -aG davfs2 $USER` (danach neu einloggen).

3. **Berechtigungen**: Das Sync-Script benötigt Leserechte für das Quellverzeichnis und Schreibrechte für das Zielverzeichnis.

4. **Mount-Point**: Stelle sicher, dass das WebDAV-Verzeichnis korrekt gemountet ist, bevor das Sync-Script ausgeführt wird.

5. **Zugangsdaten**: WebDAV-Zugangsdaten werden in `.env` im `paperless/` Root-Verzeichnis gespeichert. Die `.env` Datei sollte nicht in Git committed werden (bereits in `.gitignore`).

6. **Paperless Konfiguration**: Wenn `PAPERLESS_PRESERVE_STRUCTURE=true` verwendet wird, muss in Paperless-ngx `PAPERLESS_CONSUMER_RECURSIVE=true` aktiviert sein.

7. **Dateinamen**: Duplikate werden basierend auf dem Dateinamen erkannt. Dateien mit identischem Namen werden übersprungen.

## 🔗 Verwandte Dokumentation

- [Paperless-ngx Service Dokumentation](../../../docs/services/paperless-ngx/README.md)
- [Paperless Konfiguration](../../../projects/buchhaltung/paperless/konfiguration.md)

## 📄 Lizenz

Siehe [LICENSE](../../../LICENSE) im Hauptverzeichnis.

