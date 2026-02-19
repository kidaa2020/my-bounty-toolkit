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
mkdir -p "$RECON_DIR"

if ! require_input "$INPUT_FILE"; then
    log_warn "Fichero de subdominios vacío, creando placeholder..."
    touch "$RECON_DIR/urls_live.txt"
    exit 0
fi

# ── Construir argumentos para httpx ──────────────────────────────────────────
log_info "httpx: probando hosts vivos (threads: 100, timeout: ${TIMEOUT}s)..."

# Usamos un array para manejar argumentos de forma segura
HTTPX_ARGS=(
    "-l" "$INPUT_FILE"
    "-silent"
    "-status-code"
    "-title"
    "-tech-detect"
    "-threads" "100"
    "-timeout" "$TIMEOUT"
    "-rate-limit" "$RATE_LIMIT"
    "-o" "$RECON_DIR/httpx_all.txt"
)

# Añadir cabecera si existe
if [ -n "${CUSTOM_HEADER:-}" ]; then
    HTTPX_ARGS+=("-H" "$CUSTOM_HEADER")
fi

# Ejecutar httpx
httpx "${HTTPX_ARGS[@]}" >> "$LOG" 2>&1

# Extraer solo las URLs (primera columna)
if [ -f "$RECON_DIR/httpx_all.txt" ]; then
    awk '{print $1}' "$RECON_DIR/httpx_all.txt" \
        | grep -E '^https?://' \
        | sort -u \
        > "$RECON_DIR/urls_live.txt"
    log_success "httpx: $(count_lines "$RECON_DIR/urls_live.txt") hosts respondieron"
else
    log_warn "httpx no generó resultados vivos."
    touch "$RECON_DIR/urls_live.txt"
fi

LIVE=$(count_lines "$RECON_DIR/urls_live.txt")
log_success "Total URLs vivas: $LIVE"

# ── naabu: escaneo de puertos extra (standard y deep) ────────────────────────
if [ "${MODE}" != "quick" ] && check_tool naabu; then
    log_info "naabu: escaneando puertos adicionales (top-1000)..."
    naabu -l "$INPUT_FILE" \
        -silent \
        -top-ports 1000 \
        -rate "$RATE_LIMIT" \
        -o "$RECON_DIR/naabu_ports.txt" \
        >> "$LOG" 2>&1 \
        && log_success "naabu: $(count_lines "$RECON_DIR/naabu_ports.txt") combinaciones encontradas" \
        || log_warn "naabu terminó con advertencias o no encontró puertos"
fi

# ── subzy: subdomain takeover ─────────────────────────────────────────────────
if check_tool subzy; then
    log_info "subzy: comprobando subdomain takeover..."
    # subzy necesita targets desde archivo
    subzy run \
        --targets "$INPUT_FILE" \
        --verify \
        --output "$RECON_DIR/subzy_takeover.txt" \
        >> "$LOG" 2>&1 \
        || log_warn "subzy encontró posibles vulnerabilidades o terminó con advertencias"
fi

log_success "Fase 2 completada."
