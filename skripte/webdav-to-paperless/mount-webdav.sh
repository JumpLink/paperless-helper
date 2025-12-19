#!/bin/bash
#
# Script zum Mounten/Unmounten eines WebDAV-Verzeichnisses (Nextcloud)
#
# Verwendung:
#   ./mount-webdav.sh mount      # WebDAV mounten
#   ./mount-webdav.sh unmount    # WebDAV unmounten
#   ./mount-webdav.sh status     # Status prüfen
#
# Optionen:
#   -v, --verbose         Ausführliche Ausgabe
#   -h, --help            Diese Hilfe anzeigen

set -euo pipefail

# Farben für Ausgabe
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Standardwerte
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAPERLESS_ROOT="$(cd "$(dirname "$(dirname "$SCRIPT_DIR")")" && pwd)"
ENV_FILE="${PAPERLESS_ROOT}/.env"
VERBOSE=false

# WebDAV-Konfiguration (aus .env oder Standardwerte)
WEBDAV_URL=""
WEBDAV_MOUNT_POINT=""
WEBDAV_USER=""
WEBDAV_PASS=""

# Funktionen
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    cat << EOF
WebDAV Mount-Script für Nextcloud

Verwendung:
    $0 <command> [OPTIONS]

Commands:
    mount              WebDAV-Verzeichnis mounten
    unmount            WebDAV-Verzeichnis unmounten
    status             Status des Mounts prüfen

Optionen:
    -v, --verbose      Ausführliche Ausgabe
    -h, --help         Diese Hilfe anzeigen

Konfiguration (.env):
    WEBDAV_URL              WebDAV-URL (z.B. https://box.mailfreun.de/cloud/remote.php/webdav/)
    WEBDAV_MOUNT_POINT      Mount-Punkt (z.B. /mnt/nextcloud)
    WEBDAV_USER             Benutzername
    WEBDAV_PASS             Passwort (oder leer lassen für interaktive Eingabe)

Beispiele:
    # Mounten
    $0 mount

    # Unmounten
    $0 unmount

    # Status prüfen
    $0 status
EOF
}

# .env Datei laden
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log_info "Lade Konfiguration aus ${ENV_FILE}"
        fi
        # Shellcheck: source ist hier absichtlich
        # shellcheck source=/dev/null
        source "$ENV_FILE"
    else
        log_warning "Keine .env Datei gefunden in ${ENV_FILE}"
    fi
}

# Argumente parsen
parse_args() {
    local command=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            mount|unmount|status)
                command="$1"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unbekannte Option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -z "$command" ]]; then
        log_error "Kein Command angegeben (mount/unmount/status)"
        show_help
        exit 1
    fi

    echo "$command"
}

# Prüfe ob davfs2 installiert ist
check_davfs2() {
    if ! command -v mount.davfs &> /dev/null; then
        log_error "davfs2 ist nicht installiert!"
        log_info "Installiere mit: sudo apt-get install davfs2"
        log_info "oder: sudo dnf install davfs2"
        exit 1
    fi

    # Prüfe ob Benutzer in davfs2-Gruppe ist
    if ! groups | grep -q davfs2; then
        log_warning "Benutzer ist nicht in der davfs2-Gruppe."
        log_info "Füge Benutzer hinzu mit: sudo usermod -aG davfs2 \$USER"
        log_info "Danach neu einloggen oder: newgrp davfs2"
    fi
}

# Konfiguration validieren
validate_config() {
    # WebDAV URL
    if [[ -z "${WEBDAV_URL:-}" ]]; then
        log_error "WEBDAV_URL nicht gesetzt. Bitte in .env konfigurieren."
        exit 1
    fi

    # Mount-Punkt
    if [[ -z "${WEBDAV_MOUNT_POINT:-}" ]]; then
        log_error "WEBDAV_MOUNT_POINT nicht gesetzt. Bitte in .env konfigurieren."
        exit 1
    fi

    # Benutzername
    if [[ -z "${WEBDAV_USER:-}" ]]; then
        log_warning "WEBDAV_USER nicht gesetzt. Versuche interaktive Eingabe..."
        read -rp "WebDAV Benutzername: " WEBDAV_USER
        if [[ -z "$WEBDAV_USER" ]]; then
            log_error "Benutzername ist erforderlich."
            exit 1
        fi
    fi

    # Passwort
    if [[ -z "${WEBDAV_PASS:-}" ]]; then
        log_warning "WEBDAV_PASS nicht gesetzt. Versuche interaktive Eingabe..."
        read -rsp "WebDAV Passwort: " WEBDAV_PASS
        echo ""
        if [[ -z "$WEBDAV_PASS" ]]; then
            log_error "Passwort ist erforderlich."
            exit 1
        fi
    fi
}

# WebDAV mounten
mount_webdav() {
    local url="$1"
    local mount_point="$2"
    local user="$3"
    local pass="$4"

    # Prüfe ob bereits gemountet
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_warning "Mount-Punkt ist bereits gemountet: $mount_point"
        return 0
    fi

    # Erstelle Mount-Punkt falls nicht vorhanden
    if [[ ! -d "$mount_point" ]]; then
        log_info "Erstelle Mount-Punkt: $mount_point"
        sudo mkdir -p "$mount_point"
        sudo chown "$USER:$USER" "$mount_point"
    fi

    # Prüfe Berechtigungen
    if [[ ! -w "$mount_point" ]]; then
        log_error "Keine Schreibrechte für Mount-Punkt: $mount_point"
        exit 1
    fi

    log_info "Mounte WebDAV..."
    log_info "URL: $url"
    log_info "Mount-Punkt: $mount_point"

    # Erstelle temporäre Credentials-Datei
    local temp_creds
    temp_creds="$(mktemp)"
    echo "$url $user $pass" > "$temp_creds"
    chmod 600 "$temp_creds"

    # Mounte mit davfs2
    if mount.davfs -o uid="$(id -u)",gid="$(id -g)",file_mode=0664,dir_mode=0775 "$url" "$mount_point" < "$temp_creds"; then
        log_success "WebDAV erfolgreich gemountet: $mount_point"
        rm -f "$temp_creds"
        return 0
    else
        log_error "Fehler beim Mounten von WebDAV"
        rm -f "$temp_creds"
        exit 1
    fi
}

# WebDAV unmounten
unmount_webdav() {
    local mount_point="$1"

    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        log_warning "Mount-Punkt ist nicht gemountet: $mount_point"
        return 0
    fi

    log_info "Unmounte WebDAV: $mount_point"

    if sudo umount "$mount_point"; then
        log_success "WebDAV erfolgreich unmounted: $mount_point"
        return 0
    else
        log_error "Fehler beim Unmounten von WebDAV"
        exit 1
    fi
}

# Status prüfen
check_status() {
    local mount_point="$1"

    echo ""
    log_info "=== WebDAV Mount Status ==="
    echo ""

    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_success "Mount-Punkt ist gemountet: $mount_point"
        echo ""
        log_info "Mount-Details:"
        mount | grep "$mount_point" || true
        echo ""
        log_info "Verfügbarer Speicherplatz:"
        df -h "$mount_point" | tail -n 1
    else
        log_warning "Mount-Punkt ist nicht gemountet: $mount_point"
    fi

    echo ""
}

# Hauptfunktion
main() {
    local command
    command=$(parse_args "$@")

    load_env
    check_davfs2

    case "$command" in
        mount)
            validate_config
            mount_webdav "$WEBDAV_URL" "$WEBDAV_MOUNT_POINT" "$WEBDAV_USER" "$WEBDAV_PASS"
            ;;
        unmount)
            if [[ -z "${WEBDAV_MOUNT_POINT:-}" ]]; then
                log_error "WEBDAV_MOUNT_POINT nicht gesetzt. Bitte in .env konfigurieren."
                exit 1
            fi
            unmount_webdav "$WEBDAV_MOUNT_POINT"
            ;;
        status)
            if [[ -z "${WEBDAV_MOUNT_POINT:-}" ]]; then
                log_error "WEBDAV_MOUNT_POINT nicht gesetzt. Bitte in .env konfigurieren."
                exit 1
            fi
            check_status "$WEBDAV_MOUNT_POINT"
            ;;
        *)
            log_error "Unbekanntes Command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Script ausführen
main "$@"

