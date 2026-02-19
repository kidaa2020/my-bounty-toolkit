#!/bin/bash
# =============================================================================
# subdomain_enum.sh — Fase 1: Enumeración de Subdominios
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/lib/common.sh"
source "$SCRIPT_DIR/config/config.conf"

while getopts "d:o:m:" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
    esac
done

RECON_DIR="$OUTPUT_DIR/recon"
LOG="$OUTPUT_DIR/logs/recon.log"
mkdir -p "$RECON_DIR"

# ── Subfinder ─────────────────────────────────────────────────────────────────
if check_tool subfinder; then
    log_info "subfinder: enumerando subdominios pasivos..."
    subfinder -d "$DOMAIN" -silent \
        -t 50 \
        -o "$RECON_DIR/subfinder.txt" \
        >> "$LOG" 2>&1 \
        && log_success "subfinder: $(count_lines "$RECON_DIR/subfinder.txt") subdominios" \
        || log_warn "subfinder terminó con errores"
else
    log_warn "subfinder no instalado, esta fase se omitirá."
fi

# ── Amass (solo deep) ─────────────────────────────────────────────────────────
if [ "${MODE}" == "deep" ] && check_tool amass; then
    log_info "amass: enumeración profunda (puede tardar varios minutos)..."
    amass enum -passive -d "$DOMAIN" \
        -o "$RECON_DIR/amass.txt" \
        >> "$LOG" 2>&1 \
        && log_success "amass: $(count_lines "$RECON_DIR/amass.txt") subdominios" \
        || log_warn "amass terminó con errores"
fi

# ── Combinar resultados ───────────────────────────────────────────────────────
log_info "Combinando y deduplicando resultados..."
cat "$RECON_DIR"/subfinder.txt \
    "$RECON_DIR"/amass.txt \
    2>/dev/null \
    | sort -u \
    > "$RECON_DIR/subdomains_all.txt"

TOTAL=$(count_lines "$RECON_DIR/subdomains_all.txt")
log_info "Total de subdominios únicos antes de resolución: $TOTAL"

# ── Resolución DNS con dnsx ───────────────────────────────────────────────────
if check_tool dnsx && [ "$TOTAL" -gt 0 ]; then
    log_info "dnsx: resolviendo subdominios vivos..."
    dnsx -l "$RECON_DIR/subdomains_all.txt" \
        -silent \
        -a -resp-only \
        -r "$DNS_RESOLVERS" \
        -t 100 \
        2>>"$LOG" \
        | sort -u \
        > "$RECON_DIR/subdomains_resolved.txt"
else
    log_warn "dnsx no disponible o lista vacía, copiando lista sin resolver..."
    cp "$RECON_DIR/subdomains_all.txt" "$RECON_DIR/subdomains_resolved.txt" 2>/dev/null || true
fi

# ── Resultado final ───────────────────────────────────────────────────────────
cp "$RECON_DIR/subdomains_resolved.txt" "$RECON_DIR/subdomains_final.txt" 2>/dev/null || \
    touch "$RECON_DIR/subdomains_final.txt"

FINAL=$(count_lines "$RECON_DIR/subdomains_final.txt")
log_success "Fase 1 completada — $FINAL subdominios resueltos en $RECON_DIR/subdomains_final.txt"
