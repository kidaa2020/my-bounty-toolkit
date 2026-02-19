#!/bin/bash
# =============================================================================
# vuln_scan.sh — Fase 5: Escaneo de Vulnerabilidades
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

VULN_DIR="$OUTPUT_DIR/vulns"
LIVE_URLS="$OUTPUT_DIR/recon/urls_live.txt"
LOG="$OUTPUT_DIR/logs/vulns.log"
mkdir -p "$VULN_DIR"

if ! require_input "${LIVE_URLS}"; then
    log_warn "No hay URLs vivas para escanear."
    exit 0
fi

# ── Configurar severidad según el modo ────────────────────────────────────────
case "$MODE" in
    quick)    SEVERITY="critical,high" ;;
    standard) SEVERITY="critical,high,medium" ;;
    deep)     SEVERITY="critical,high,medium,low,info" ;;
esac

HEADER_FLAG=""
if [ -n "${CUSTOM_HEADER:-}" ]; then
    HEADER_FLAG="-H '$CUSTOM_HEADER'"
fi

# ── Nuclei: escaneo de plantillas YAML ───────────────────────────────────────
if check_tool nuclei; then
    log_info "nuclei: escaneando con severidad [$SEVERITY]..."

    NUCLEI_EXTRA_FLAGS=""
    if [ -n "${NUCLEI_CUSTOM_TEMPLATES:-}" ] && [ -d "${NUCLEI_CUSTOM_TEMPLATES}" ]; then
        NUCLEI_EXTRA_FLAGS="-t $NUCLEI_CUSTOM_TEMPLATES"
    fi

    # shellcheck disable=SC2086
    nuclei -l "$LIVE_URLS" \
        -severity "$SEVERITY" \
        -silent \
        -json-export "$VULN_DIR/nuclei_results.json" \
        -o "$VULN_DIR/nuclei_results.txt" \
        -rate-limit "$RATE_LIMIT" \
        -timeout "$TIMEOUT" \
        -stats \
        ${HEADER_FLAG} \
        ${NUCLEI_EXTRA_FLAGS} \
        >> "$LOG" 2>&1 \
        && log_success "nuclei: escaneo completado" \
        || log_warn "nuclei terminó con advertencias"

    # Contar hallazgos por severidad
    if [ -f "$VULN_DIR/nuclei_results.json" ]; then
        CRIT=$(jq -r 'select(.info.severity=="critical")' "$VULN_DIR/nuclei_results.json" 2>/dev/null | grep -c '"severity"' || echo 0)
        HIGH=$(jq -r 'select(.info.severity=="high")'     "$VULN_DIR/nuclei_results.json" 2>/dev/null | grep -c '"severity"' || echo 0)
        MED=$(jq -r  'select(.info.severity=="medium")'   "$VULN_DIR/nuclei_results.json" 2>/dev/null | grep -c '"severity"' || echo 0)
        LOW=$(jq -r  'select(.info.severity=="low")'      "$VULN_DIR/nuclei_results.json" 2>/dev/null | grep -c '"severity"' || echo 0)
        log_success "nuclei hallazgos → Críticos:$CRIT  Altos:$HIGH  Medios:$MED  Bajos:$LOW"
    fi
else
    log_warn "nuclei no instalado."
fi

# ── Dalfox: escaneo XSS (standard y deep) ────────────────────────────────────
if [ "${MODE}" != "quick" ] && check_tool dalfox; then
    log_info "dalfox: buscando vulnerabilidades XSS..."
    # Filtrar URLs con parámetros de query
    grep '?' "$LIVE_URLS" 2>/dev/null | head -50 > "$VULN_DIR/urls_with_params.txt" || true

    if [ -s "$VULN_DIR/urls_with_params.txt" ]; then
        # shellcheck disable=SC2086
        dalfox file "$VULN_DIR/urls_with_params.txt" \
            --skip-bav \
            --no-color \
            --format json \
            --output "$VULN_DIR/dalfox_results.json" \
            ${HEADER_FLAG} \
            >> "$LOG" 2>&1 \
            && log_success "dalfox: $(count_lines "$VULN_DIR/dalfox_results.json") posibles XSS" \
            || log_warn "dalfox terminó con advertencias"
    else
        log_info "No hay URLs con parámetros para dalfox."
    fi
fi

# ── SQLMap: detección de SQLi (solo deep) ────────────────────────────────────
if [ "${MODE}" == "deep" ] && check_tool sqlmap; then
    log_info "sqlmap: detección de SQL Injection (modo seguro, nivel 1)..."
    grep '?' "$LIVE_URLS" 2>/dev/null | head -5 > "$VULN_DIR/sqli_targets.txt" || true

    if [ -s "$VULN_DIR/sqli_targets.txt" ]; then
        while read -r target_url; do
            SAFE_NAME=$(echo "$target_url" | md5sum | awk '{print $1}')
            sqlmap -u "$target_url" \
                --batch \
                --level 1 \
                --risk 1 \
                --output-dir "$VULN_DIR/sqlmap/$SAFE_NAME" \
                --quiet \
                >> "$LOG" 2>&1 || true
        done < "$VULN_DIR/sqli_targets.txt"
        log_success "sqlmap: resultados en $VULN_DIR/sqlmap/"
    fi
fi

log_success "Fase 5 completada — resultados en $VULN_DIR/"
