#!/bin/bash
#
# Script zum rekursiven Kopieren von PDF-Dateien aus einem WebDAV-Verzeichnis
# (z.B. gemountete Nextcloud) in das Paperless-ngx Consume-Verzeichnis
#
# Verwendung:
#   ./sync-webdav-to-paperless.sh [OPTIONS]
#
# Optionen:
#   -s, --source DIR      Quellverzeichnis (WebDAV-Mount) [Standard: aus .env]
#   -t, --target DIR      Zielverzeichnis (Paperless Consume) [Standard: aus .env]
#   -d, --dry-run         Nur anzeigen, keine Dateien kopieren
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
WEBDAV_SOURCE_DIR=""
PAPERLESS_CONSUME_DIR=""
DRY_RUN=false
VERBOSE=false

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
Rekursives Kopieren von PDF-Dateien aus WebDAV nach Paperless-ngx

Verwendung:
    $0 [OPTIONS]

Optionen:
    -s, --source DIR      Quellverzeichnis (WebDAV-Mount)
    -t, --target DIR      Zielverzeichnis (Paperless Consume)
    -d, --dry-run         Nur anzeigen, keine Dateien kopieren
    -v, --verbose         Ausführliche Ausgabe
    -h, --help            Diese Hilfe anzeigen

Umgebungsvariablen (.env):
    WEBDAV_SOURCE_DIR            Quellverzeichnis (WebDAV-Mount)
    PAPERLESS_CONSUME_DIR        Zielverzeichnis (Paperless Consume)
    PAPERLESS_PRESERVE_STRUCTURE Struktur beibehalten (true/false, Standard: false)

Beispiele:
    # Mit .env Datei
    $0

    # Mit Kommandozeilen-Optionen
    $0 -s /mnt/nextcloud -t /data/paperless/consume

    # Dry-Run (Test)
    $0 -d -v
EOF
}

# .env Datei laden, falls vorhanden
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        log_info "Lade Konfiguration aus ${ENV_FILE}"
        # Shellcheck: source ist hier absichtlich
        # shellcheck source=/dev/null
        source "$ENV_FILE"
    else
        log_warning "Keine .env Datei gefunden in ${ENV_FILE}"
        log_warning "Verwende Standardwerte oder Kommandozeilen-Optionen."
    fi
}

# Argumente parsen
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--source)
                WEBDAV_SOURCE_DIR="$2"
                shift 2
                ;;
            -t|--target)
                PAPERLESS_CONSUME_DIR="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
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
}

# Validierung
validate_paths() {
    # Source-Verzeichnis prüfen
    if [[ -z "$WEBDAV_SOURCE_DIR" ]]; then
        log_error "Quellverzeichnis nicht angegeben. Verwende -s/--source oder setze WEBDAV_SOURCE_DIR in .env"
        exit 1
    fi

    if [[ ! -d "$WEBDAV_SOURCE_DIR" ]]; then
        log_error "Quellverzeichnis existiert nicht: $WEBDAV_SOURCE_DIR"
        exit 1
    fi

    if [[ ! -r "$WEBDAV_SOURCE_DIR" ]]; then
        log_error "Keine Leserechte für Quellverzeichnis: $WEBDAV_SOURCE_DIR"
        exit 1
    fi

    # Target-Verzeichnis prüfen
    if [[ -z "$PAPERLESS_CONSUME_DIR" ]]; then
        log_error "Zielverzeichnis nicht angegeben. Verwende -t/--target oder setze PAPERLESS_CONSUME_DIR in .env"
        exit 1
    fi

    if [[ ! -d "$PAPERLESS_CONSUME_DIR" ]]; then
        log_warning "Zielverzeichnis existiert nicht, erstelle es: $PAPERLESS_CONSUME_DIR"
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$PAPERLESS_CONSUME_DIR"
            log_success "Zielverzeichnis erstellt"
        fi
    fi

    if [[ ! -w "$PAPERLESS_CONSUME_DIR" ]]; then
        log_error "Keine Schreibrechte für Zielverzeichnis: $PAPERLESS_CONSUME_DIR"
        exit 1
    fi
}

# PDF-Dateien finden und kopieren
sync_pdfs() {
    local source="$1"
    local target="$2"
    local preserve_structure="${PAPERLESS_PRESERVE_STRUCTURE:-false}"
    local count=0
    local skipped=0
    local errors=0

    log_info "Suche PDF-Dateien in: $source"
    log_info "Zielverzeichnis: $target"
    [[ "$DRY_RUN" == true ]] && log_warning "DRY-RUN Modus: Keine Dateien werden kopiert"

    # Finde alle PDF-Dateien rekursiv
    while IFS= read -r -d '' pdf_file; do
        # Relativer Pfad zum Source-Verzeichnis
        local rel_path="${pdf_file#$source/}"
        local target_file

        if [[ "$preserve_structure" == "true" ]]; then
            # Struktur beibehalten
            target_file="${target}/${rel_path}"
            local target_dir
            target_dir="$(dirname "$target_file")"
            
            if [[ "$DRY_RUN" == false ]]; then
                mkdir -p "$target_dir"
            fi
        else
            # Alle PDFs direkt ins Zielverzeichnis
            local filename
            filename="$(basename "$pdf_file")"
            target_file="${target}/${filename}"
        fi

        # Prüfe ob Datei bereits existiert
        if [[ -f "$target_file" ]]; then
            if [[ "$VERBOSE" == true ]]; then
                log_warning "Überspringe (bereits vorhanden): $rel_path"
            fi
            ((skipped++))
            continue
        fi

        # Kopiere Datei
        if [[ "$VERBOSE" == true ]]; then
            log_info "Kopiere: $rel_path -> $target_file"
        fi

        if [[ "$DRY_RUN" == false ]]; then
            if cp "$pdf_file" "$target_file"; then
                log_success "Kopiert: $rel_path"
                ((count++))
            else
                log_error "Fehler beim Kopieren: $rel_path"
                ((errors++))
            fi
        else
            log_info "[DRY-RUN] Würde kopieren: $rel_path -> $target_file"
            ((count++))
        fi
    done < <(find "$source" -type f -iname "*.pdf" -print0)

    # Zusammenfassung
    echo ""
    log_info "=== Zusammenfassung ==="
    log_success "Kopiert: $count"
    [[ $skipped -gt 0 ]] && log_warning "Übersprungen (bereits vorhanden): $skipped"
    [[ $errors -gt 0 ]] && log_error "Fehler: $errors"
}

# Hauptfunktion
main() {
    load_env
    parse_args "$@"
    validate_paths

    log_info "Starte Synchronisation..."
    log_info "Quelle: $WEBDAV_SOURCE_DIR"
    log_info "Ziel: $PAPERLESS_CONSUME_DIR"
    echo ""

    sync_pdfs "$WEBDAV_SOURCE_DIR" "$PAPERLESS_CONSUME_DIR"

    log_success "Synchronisation abgeschlossen!"
}

# Script ausführen
main "$@"

