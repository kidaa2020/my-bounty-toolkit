#!/bin/bash
# =============================================================================
# generate_report.sh — Fase 6: Generación de Reporte HTML
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/lib/common.sh"

while getopts "i:d:m:" opt; do
    case $opt in
        i) SCAN_DIR="$OPTARG" ;;
        d) DOMAIN="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
    esac
done

REPORT_FILE="$SCAN_DIR/report.html"
VULN_JSON="$SCAN_DIR/vulns/nuclei_results.json"

# ── Recopilar estadísticas ────────────────────────────────────────────────────
SUBDOMAINS=$(count_lines "$SCAN_DIR/recon/subdomains_final.txt" 2>/dev/null)
LIVE_URLS=$(count_lines "$SCAN_DIR/recon/urls_live.txt" 2>/dev/null)
TOTAL_URLS=$(count_lines "$SCAN_DIR/content/urls_all.txt" 2>/dev/null)
JS_FILES=$(count_lines "$SCAN_DIR/js/js_files.txt" 2>/dev/null)
SECRETS=$(count_lines "$SCAN_DIR/js/secrets_found.txt" 2>/dev/null)
TAKEOVER=$(count_lines "$SCAN_DIR/recon/subzy_takeover.txt" 2>/dev/null)

# Contar por severidad desde Nuclei JSON
CRIT=0; HIGH=0; MED=0; LOW=0
if [ -f "$VULN_JSON" ] && command -v jq &>/dev/null; then
    CRIT=$(jq -r 'select(.info.severity=="critical") | .info.severity' "$VULN_JSON" 2>/dev/null | wc -l || echo 0)
    HIGH=$(jq -r 'select(.info.severity=="high")     | .info.severity' "$VULN_JSON" 2>/dev/null | wc -l || echo 0)
    MED=$(jq -r  'select(.info.severity=="medium")   | .info.severity' "$VULN_JSON" 2>/dev/null | wc -l || echo 0)
    LOW=$(jq -r  'select(.info.severity=="low")      | .info.severity' "$VULN_JSON" 2>/dev/null | wc -l || echo 0)
fi

SCAN_DATE=$(date +'%Y-%m-%d %H:%M:%S')

# ── Generar tabla de hallazgos nuclei ─────────────────────────────────────────
NUCLEI_ROWS=""
if [ -f "$VULN_JSON" ] && command -v jq &>/dev/null; then
    while IFS= read -r finding; do
        SEV=$(echo "$finding"  | jq -r '.info.severity // "info"')
        NAME=$(echo "$finding" | jq -r '.info.name     // "N/A"')
        URL=$(echo "$finding"  | jq -r '.matched-at   // .host // "N/A"')
        TEMPL=$(echo "$finding"| jq -r '.template-id  // "N/A"')
        NUCLEI_ROWS+="<tr class=\"sev-${SEV}\"><td><span class=\"badge ${SEV}\">${SEV}</span></td><td>${NAME}</td><td class=\"url\">${URL}</td><td>${TEMPL}</td></tr>\n"
    done < <(jq -c '.' "$VULN_JSON" 2>/dev/null)
fi

# ── Leer primeras líneas de secretos JS ───────────────────────────────────────
JS_SECRETS_HTML=""
if [ -f "$SCAN_DIR/js/secrets_found.txt" ] && [ "$SECRETS" -gt 0 ]; then
    while IFS= read -r line; do
        JS_SECRETS_HTML+="<li>${line}</li>\n"
    done < <(head -30 "$SCAN_DIR/js/secrets_found.txt")
fi

# ── Escribir HTML ─────────────────────────────────────────────────────────────
cat > "$REPORT_FILE" << HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bug Bounty Report — ${DOMAIN}</title>
<style>
  :root{--bg:#0f0f0f;--surface:#1a1a2e;--accent:#6c63ff;--critical:#ff4757;--high:#ff6b35;--medium:#ffa502;--low:#2ed573;--info:#5352ed;--text:#e0e0ff;--muted:#7f8c8d}
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Segoe UI',system-ui,sans-serif;background:var(--bg);color:var(--text);padding:2rem}
  h1{font-size:2rem;background:linear-gradient(135deg,var(--accent),#ff6b9d);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:.25rem}
  .meta{color:var(--muted);font-size:.9rem;margin-bottom:2rem}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:1rem;margin-bottom:2rem}
  .card{background:var(--surface);border-radius:12px;padding:1.2rem;border:1px solid rgba(255,255,255,.05)}
  .card .num{font-size:2.2rem;font-weight:700;margin-bottom:.2rem}
  .card .lbl{font-size:.8rem;color:var(--muted);text-transform:uppercase;letter-spacing:.05em}
  .card.critical .num{color:var(--critical)}
  .card.high    .num{color:var(--high)}
  .card.medium  .num{color:var(--medium)}
  .card.low     .num{color:var(--low)}
  .card.neutral .num{color:var(--accent)}
  h2{margin:2rem 0 1rem;font-size:1.3rem;border-left:3px solid var(--accent);padding-left:.8rem}
  table{width:100%;border-collapse:collapse;background:var(--surface);border-radius:12px;overflow:hidden}
  th{background:rgba(108,99,255,.15);padding:.8rem 1rem;text-align:left;font-size:.8rem;text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}
  td{padding:.75rem 1rem;border-bottom:1px solid rgba(255,255,255,.05);font-size:.88rem}
  tr:last-child td{border-bottom:none}
  .badge{padding:.2rem .6rem;border-radius:999px;font-size:.75rem;font-weight:700;text-transform:uppercase}
  .badge.critical{background:var(--critical);color:#fff}
  .badge.high    {background:var(--high);color:#fff}
  .badge.medium  {background:var(--medium);color:#000}
  .badge.low     {background:var(--low);color:#000}
  .badge.info    {background:var(--info);color:#fff}
  .url{font-family:monospace;font-size:.8rem;word-break:break-all;color:var(--muted)}
  .empty{color:var(--muted);font-style:italic;padding:1rem}
  ul.secrets{background:var(--surface);border-radius:12px;padding:1rem 1rem 1rem 2rem;list-style:disc}
  ul.secrets li{font-family:monospace;font-size:.82rem;padding:.25rem 0;color:#ff6b9d;word-break:break-all}
  footer{margin-top:3rem;text-align:center;color:var(--muted);font-size:.8rem}
</style>
</head>
<body>
<h1>🎯 Bug Bounty Report</h1>
<p class="meta">Dominio: <strong>${DOMAIN}</strong> &nbsp;|&nbsp; Modo: <strong>${MODE}</strong> &nbsp;|&nbsp; Fecha: ${SCAN_DATE}</p>

<div class="grid">
  <div class="card neutral"><div class="num">${SUBDOMAINS}</div><div class="lbl">Subdominios</div></div>
  <div class="card neutral"><div class="num">${LIVE_URLS}</div><div class="lbl">Hosts vivos</div></div>
  <div class="card neutral"><div class="num">${TOTAL_URLS}</div><div class="lbl">URLs totales</div></div>
  <div class="card neutral"><div class="num">${JS_FILES}</div><div class="lbl">Ficheros JS</div></div>
  <div class="card critical"><div class="num">${CRIT}</div><div class="lbl">Críticos</div></div>
  <div class="card high">   <div class="num">${HIGH}</div><div class="lbl">Altos</div></div>
  <div class="card medium"> <div class="num">${MED}</div> <div class="lbl">Medios</div></div>
  <div class="card low">    <div class="num">${LOW}</div> <div class="lbl">Bajos</div></div>
</div>

<h2>🔍 Hallazgos de Nuclei</h2>
$([ -n "$NUCLEI_ROWS" ] && echo '<table><thead><tr><th>Severidad</th><th>Nombre</th><th>URL</th><th>Template</th></tr></thead><tbody>'" $NUCLEI_ROWS"'</tbody></table>' || echo '<p class="empty">No se encontraron hallazgos de nuclei.</p>')

<h2>🔑 Posibles Secretos en JavaScript</h2>
$([ -n "$JS_SECRETS_HTML" ] && echo "<ul class=\"secrets\"> $JS_SECRETS_HTML </ul>" || echo '<p class="empty">No se encontraron secretos en JS.</p>')

<h2>🌐 Subdomain Takeover</h2>
$([ "$TAKEOVER" -gt 0 ] && echo "<p style='color:var(--critical)'>⚠️ $TAKEOVER posibles subdominios vulnerables a takeover. Revisa: vulns/subzy_takeover.txt</p>" || echo '<p class="empty">No se detectaron posibles takeovers.</p>')

<footer>Generado por <strong>Bug Bounty Toolkit</strong> — Solo para uso autorizado ⚠️</footer>
</body>
</html>
HTMLEOF

log_success "Reporte generado: $REPORT_FILE"
