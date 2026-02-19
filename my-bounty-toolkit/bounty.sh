#!/bin/bash
# =============================================================================
# bounty.sh — Orquestador principal del Toolkit de Bug Bounty
# Uso: ./bounty.sh -d objetivo.com [-m quick|standard|deep] [-o dir_salida]
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar funciones comunes y configuración
source "$SCRIPT_DIR/core/lib/common.sh"
source "$SCRIPT_DIR/config/config.conf"

# ── Variables por defecto ─────────────────────────────────────────────────────
MODO="standard"
OUTPUT_BASE="$SCRIPT_DIR/output"
DOMINIO=""
WEB_UI_PID=""

# ── Función de ayuda ──────────────────────────────────────────────────────────
show_help() {
    cat << EOF
${BOLD}${BLUE}╔══════════════════════════════════════════════╗
║        Bug Bounty Toolkit — Ayuda           ║
╚══════════════════════════════════════════════╝${NC}

Uso: $0 -d DOMINIO [-m MODO] [-o DIR]

  ${BOLD}-d DOMINIO${NC}   Dominio objetivo (ej. ejemplo.com)
  ${BOLD}-m MODO${NC}      quick | standard | deep  (defecto: standard)
  ${BOLD}-o DIR${NC}       Carpeta de salida         (defecto: ./output)
  ${BOLD}-h${NC}           Mostrar esta ayuda

Ejemplos:
  $0 -d example.com
  $0 -d example.com -m quick
  $0 -d example.com -m deep -o ~/escaneos
EOF
}

# ── Parsear argumentos ────────────────────────────────────────────────────────
while getopts "d:m:o:h" opt; do
    case $opt in
        d) DOMINIO="$OPTARG" ;;
        m) MODO="$OPTARG" ;;
        o) OUTPUT_BASE="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# ── Validaciones ──────────────────────────────────────────────────────────────
if [ -z "$DOMINIO" ]; then
    log_error "Debes especificar un dominio con -d"
    show_help
    exit 1
fi

if [[ ! "$MODO" =~ ^(quick|standard|deep)$ ]]; then
    log_error "Modo '$MODO' no válido. Usa: quick, standard o deep"
    exit 1
fi

# ── Crear estructura del escaneo ──────────────────────────────────────────────
FECHA_HORA=$(date +"%Y%m%d_%H%M%S")
SCAN_NAME="${DOMINIO}_${FECHA_HORA}_${MODO}"
SCAN_DIR="$OUTPUT_BASE/$SCAN_NAME"
mkdir -p "$SCAN_DIR"/{recon,content,js,vulns,logs}

# Exportar variables para módulos hijo
export SCAN_DIR DOMINIO MODO SCAN_NAME
export RED GREEN YELLOW BLUE CYAN BOLD NC

# ── Función para emitir evento al WEB UI (opcional) ───────────────────────────
emit_event() {
    local phase="$1"
    local message="$2"
    local status="${3:-info}"
    local ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")

    # Escribir en el fichero de eventos que el servidor web monitoriza
    local events_file="$SCAN_DIR/logs/events.jsonl"
    printf '{"ts":"%s","phase":"%s","message":"%s","status":"%s"}\n' \
        "$ts" "$phase" "$message" "$status" >> "$events_file"
}

# ── Banner ────────────────────────────────────────────────────────────────────
log_phase "Bug Bounty Toolkit — Iniciando"
log_info  "Dominio   : $DOMINIO"
log_info  "Modo      : $MODO"
log_info  "Resultados: $SCAN_DIR"
emit_event "init" "Escaneo iniciado contra $DOMINIO en modo $MODO" "info"

# ── Fase 1: Reconocimiento ────────────────────────────────────────────────────
log_phase "Fase 1: Reconocimiento de Subdominios"
emit_event "recon" "Iniciando enumeración de subdominios" "running"
bash "$SCRIPT_DIR/modules/recon/subdomain_enum.sh" \
    -d "$DOMINIO" -o "$SCAN_DIR" -m "$MODO"
emit_event "recon" "Subdominios completados" "done"

# ── Fase 2: Hosts vivos ───────────────────────────────────────────────────────
log_phase "Fase 2: Verificación de Hosts Vivos y Puertos"
emit_event "hosts" "Verificando hosts vivos con httpx y puertos con naabu" "running"
bash "$SCRIPT_DIR/modules/recon/host_alive.sh" \
    -i "$SCAN_DIR/recon/subdomains_final.txt" -o "$SCAN_DIR" -m "$MODO"
emit_event "hosts" "Verificación de hosts completada" "done"

# ── Fase 3: Descubrimiento de URLs ────────────────────────────────────────────
log_phase "Fase 3: Descubrimiento de URLs y Crawling"
emit_event "urls" "Iniciando crawling con katana y gau" "running"
bash "$SCRIPT_DIR/modules/content/url_discovery.sh" \
    -i "$SCAN_DIR/recon/urls_live.txt" -o "$SCAN_DIR" -m "$MODO"
emit_event "urls" "Descubrimiento de URLs completado" "done"

# ── Fase 4: Análisis JavaScript ───────────────────────────────────────────────
log_phase "Fase 4: Análisis de JavaScript"
emit_event "js" "Extrayendo y analizando ficheros JS" "running"
bash "$SCRIPT_DIR/modules/js/js_analysis.sh" \
    -i "$SCAN_DIR/content/urls_all.txt" -o "$SCAN_DIR" -m "$MODO"
emit_event "js" "Análisis JS completado" "done"

# ── Fase 5: Escaneo de Vulnerabilidades ──────────────────────────────────────
log_phase "Fase 5: Escaneo de Vulnerabilidades"
emit_event "vulns" "Iniciando nuclei, dalfox y subzy" "running"
bash "$SCRIPT_DIR/modules/scan/vuln_scan.sh" \
    -i "$SCAN_DIR/recon/subdomains_final.txt" -o "$SCAN_DIR" -m "$MODO"
emit_event "vulns" "Escaneo de vulnerabilidades completado" "done"

# ── Fase 6: Reporte ───────────────────────────────────────────────────────────
log_phase "Fase 6: Generación de Reporte HTML"
emit_event "report" "Generando reporte HTML" "running"
bash "$SCRIPT_DIR/modules/report/generate_report.sh" \
    -i "$SCAN_DIR" -d "$DOMINIO" -m "$MODO"
emit_event "report" "Reporte generado en $SCAN_DIR/report.html" "done"

# ── Fin ───────────────────────────────────────────────────────────────────────
emit_event "finish" "Escaneo completado contra $DOMINIO" "success"
log_phase "Escaneo Completado"
log_success "Reporte disponible en: $SCAN_DIR/report.html"
