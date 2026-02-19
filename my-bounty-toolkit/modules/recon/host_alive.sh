#!/bin/bash
# =============================================================================
# host_alive.sh — Fase 2: Verificación de hosts vivos y escaneo de puertos
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/lib/common.sh"
source "$SCRIPT_DIR/config/config.conf"

while getopts "i:o:m:" opt; do
    case $opt in
        i) INPUT_FILE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
    esac
done

RECON_DIR="$OUTPUT_DIR/recon"
LOG="$OUTPUT_DIR/logs/hosts.log"

if ! require_input "$INPUT_FILE"; then
    log_warn "Fichero de subdominios vacío, creando placeholder..."
    touch "$RECON_DIR/urls_live.txt"
    exit 0
fi

# ── Construir flags personalizados de cabeceras ───────────────────────────────
HEADER_FLAG=""
if [ -n "${CUSTOM_HEADER:-}" ]; then
    HEADER_FLAG="-H \"$CUSTOM_HEADER\""
fi

# ── httpx: detectar hosts vivos ───────────────────────────────────────────────
if check_tool httpx; then
    log_info "httpx: probando hosts vivos (status, título, tecnologías)..."
    # shellcheck disable=SC2086
    httpx -l "$INPUT_FILE" \
        -silent \
        -status-code \
        -title \
        -tech-detect \
        -timeout "$TIMEOUT" \
        -rate-limit "$RATE_LIMIT" \
        ${HEADER_FLAG} \
        -o "$RECON_DIR/httpx_all.txt" \
        >> "$LOG" 2>&1 \
        && log_success "httpx: $(count_lines "$RECON_DIR/httpx_all.txt") hosts respondieron" \
        || log_warn "httpx terminó con advertencias"

    # Extraer solo las URLs (primera columna)
    awk '{print $1}' "$RECON_DIR/httpx_all.txt" 2>/dev/null \
        | grep -E '^https?://' \
        | sort -u \
        > "$RECON_DIR/urls_live.txt"
else
    log_warn "httpx no instalado. Generando lista sin verificar..."
    sed 's|^|http://|' "$INPUT_FILE" > "$RECON_DIR/urls_live.txt"
fi

LIVE=$(count_lines "$RECON_DIR/urls_live.txt")
log_success "URLs vivas: $LIVE"

# ── naabu: escaneo de puertos extra (standard y deep) ────────────────────────
if [ "${MODE}" != "quick" ] && check_tool naabu; then
    log_info "naabu: escaneando puertos adicionales (top-1000)..."
    naabu -l "$INPUT_FILE" \
        -silent \
        -top-ports 1000 \
        -rate "$RATE_LIMIT" \
        -o "$RECON_DIR/naabu_ports.txt" \
        >> "$LOG" 2>&1 \
        && log_success "naabu: $(count_lines "$RECON_DIR/naabu_ports.txt") host:puerto combinaciones" \
        || log_warn "naabu terminó con advertencias"
fi

# ── subzy: subdomain takeover ─────────────────────────────────────────────────
if check_tool subzy; then
    log_info "subzy: comprobando subdomain takeover..."
    subzy run \
        --targets "$INPUT_FILE" \
        --verify \
        --output "$RECON_DIR/subzy_takeover.txt" \
        >> "$LOG" 2>&1 \
        || log_warn "subzy terminó con advertencias"
fi

log_success "Fase 2 completada — hosts vivos en $RECON_DIR/urls_live.txt"
