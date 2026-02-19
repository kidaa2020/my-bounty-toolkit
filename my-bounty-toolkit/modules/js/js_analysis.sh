#!/bin/bash
# =============================================================================
# js_analysis.sh — Fase 4: Análisis de JavaScript
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

JS_DIR="$OUTPUT_DIR/js"
LOG="$OUTPUT_DIR/logs/js.log"
mkdir -p "$JS_DIR"

if ! require_input "$INPUT_FILE"; then
    log_warn "No hay URLs para analizar JS."
    touch "$JS_DIR/js_files.txt"
    exit 0
fi

# ── getJS: extraer rutas de archivos JS ───────────────────────────────────────
if check_tool getJS; then
    log_info "getJS: extrayendo URLs de ficheros JavaScript..."
    cat "$INPUT_FILE" | getJS \
        --complete \
        --nocolors \
        2>>"$LOG" \
        | grep -E '\.js(\?|$)' \
        | sort -u \
        > "$JS_DIR/js_files.txt" \
        && log_success "getJS: $(count_lines "$JS_DIR/js_files.txt") ficheros JS encontrados" \
        || log_warn "getJS terminó con advertencias"
else
    log_warn "getJS no instalado. Extrayendo .js desde URL list con grep..."
    grep -E '\.js(\?|$)' "$INPUT_FILE" | sort -u > "$JS_DIR/js_files.txt" || true
fi

JS_COUNT=$(count_lines "$JS_DIR/js_files.txt")
log_info "Analizando $JS_COUNT ficheros JS en busca de secretos..."

# ── mantra: buscar secretos/API keys en JS ────────────────────────────────────
if [ "$JS_COUNT" -gt 0 ] && check_tool mantra; then
    log_info "mantra: buscando secretos en ficheros JavaScript..."
    cat "$JS_DIR/js_files.txt" | mantra \
        2>>"$LOG" \
        > "$JS_DIR/secrets_found.txt" \
        && log_success "mantra: $(count_lines "$JS_DIR/secrets_found.txt") posibles secretos encontrados" \
        || log_warn "mantra terminó con advertencias"
else
    log_warn "mantra no disponible o lista de JS vacía. Omitiendo búsqueda de secretos."
    touch "$JS_DIR/secrets_found.txt"
fi

# ── Búsqueda manual de patrones sensibles en JS (modo deep) ──────────────────
if [ "${MODE}" == "deep" ] && [ "$JS_COUNT" -gt 0 ]; then
    log_info "Descargando y analizando JS files con grep de patrones sensibles..."
    mkdir -p "$JS_DIR/raw"
    PATTERNS='(api[_-]?key|apikey|secret|token|password|passwd|auth|bearer|private[_-]?key|access[_-]?key|aws|s3|bucket)'
    while read -r js_url; do
        curl -sk --max-time 10 "$js_url" 2>/dev/null \
            | grep -oiE "$PATTERNS[^\"' ]*" \
            >> "$JS_DIR/grep_patterns.txt" \
            || true
    done < "$JS_DIR/js_files.txt"
    sort -u "$JS_DIR/grep_patterns.txt" -o "$JS_DIR/grep_patterns.txt"
    log_success "grep patrones: $(count_lines "$JS_DIR/grep_patterns.txt") coincidencias"
fi

SECRETS=$(count_lines "$JS_DIR/secrets_found.txt")
log_success "Fase 4 completada — $SECRETS posibles secretos en $JS_DIR/secrets_found.txt"
