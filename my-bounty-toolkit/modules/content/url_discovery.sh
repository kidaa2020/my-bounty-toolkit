#!/bin/bash
# =============================================================================
# url_discovery.sh — Fase 3: Descubrimiento de URLs y Crawling
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

CONTENT_DIR="$OUTPUT_DIR/content"
LOG="$OUTPUT_DIR/logs/content.log"
mkdir -p "$CONTENT_DIR"

if ! require_input "$INPUT_FILE"; then
    log_warn "No hay URLs vivas para procesar."
    touch "$CONTENT_DIR/urls_all.txt"
    exit 0
fi

# ── Configurar profundidad según modo ─────────────────────────────────────────
case "$MODE" in
    quick)    KATANA_DEPTH=2 ;;
    standard) KATANA_DEPTH=3 ;;
    deep)     KATANA_DEPTH=5 ;;
esac

HEADER_FLAG=""
if [ -n "${CUSTOM_HEADER:-}" ]; then
    HEADER_FLAG="-H '$CUSTOM_HEADER'"
fi

# ── gau: URLs históricas ──────────────────────────────────────────────────────
if check_tool gau; then
    log_info "gau: obteniendo URLs históricas (Wayback, Common Crawl)..."
    # gau acepta dominios, no URLs completas
    DOMAIN_BARE=$(head -1 "$INPUT_FILE" | sed 's|https\?://||' | cut -d/ -f1)
    cat "$INPUT_FILE" | sed 's|https\?://||' | cut -d/ -f1 | sort -u | while read -r domain; do
        gau --subs "$domain" \
            --threads 5 \
            --timeout "$TIMEOUT" \
            2>>"$LOG"
    done | sort -u > "$CONTENT_DIR/gau_urls.txt" \
        && log_success "gau: $(count_lines "$CONTENT_DIR/gau_urls.txt") URLs históricas" \
        || log_warn "gau con advertencias"
fi

# ── katana: crawling activo ───────────────────────────────────────────────────
if check_tool katana; then
    log_info "katana: crawling activo (profundidad: $KATANA_DEPTH)..."
    # shellcheck disable=SC2086
    katana -l "$INPUT_FILE" \
        -silent \
        -depth "$KATANA_DEPTH" \
        -jc \
        -kf all \
        -timeout "$TIMEOUT" \
        -rate-limit "$RATE_LIMIT" \
        ${HEADER_FLAG} \
        -o "$CONTENT_DIR/katana_urls.txt" \
        >> "$LOG" 2>&1 \
        && log_success "katana: $(count_lines "$CONTENT_DIR/katana_urls.txt") endpoints descubiertos" \
        || log_warn "katana con advertencias"
fi

# ── ffuf: fuzzing de directorios (solo standard y deep) ──────────────────────
if [ "${MODE}" != "quick" ] && check_tool ffuf; then
    WORDLIST="$SCRIPT_DIR/wordlists/directories.txt"
    if [ -f "$WORDLIST" ]; then
        log_info "ffuf: fuzzing de directorios en hosts vivos..."
        mkdir -p "$CONTENT_DIR/ffuf"
        head -10 "$INPUT_FILE" | while read -r url; do
            SAFE_NAME=$(echo "$url" | sed 's|[:/]|_|g')
            ffuf -u "${url}/FUZZ" \
                -w "$WORDLIST" \
                -mc 200,201,204,301,302,403 \
                -t 40 \
                -timeout "$TIMEOUT" \
                -o "$CONTENT_DIR/ffuf/${SAFE_NAME}.json" \
                -of json \
                -s \
                >> "$LOG" 2>&1 || true
        done
        log_success "ffuf: resultados en $CONTENT_DIR/ffuf/"
    else
        log_warn "Wordlist de directorios no encontrada en $WORDLIST"
    fi
fi

# ── Combinar todas las URLs ───────────────────────────────────────────────────
log_info "Combinando URLs de todas las fuentes..."
cat "$CONTENT_DIR"/gau_urls.txt \
    "$CONTENT_DIR"/katana_urls.txt \
    2>/dev/null \
    | sort -u \
    | grep -E '^https?://' \
    > "$CONTENT_DIR/urls_all.txt"

log_success "Fase 3 completada — $(count_lines "$CONTENT_DIR/urls_all.txt") URLs únicas totales"
