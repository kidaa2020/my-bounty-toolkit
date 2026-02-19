#!/bin/bash
# =============================================================================
# install.sh — Instalador de dependencias del Toolkit de Bug Bounty
# Ejecutar una vez: chmod +x install.sh && ./install.sh
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core/lib/common.sh"

log_phase "Instalador del Toolkit de Bug Bounty"

# ── 1. Asegurar Go ────────────────────────────────────────────────────────────
log_info "Verificando Go..."
if ! command -v go &>/dev/null; then
    log_info "Instalando Go..."
    sudo apt update && sudo apt install -y golang-go
else
    GO_VER=$(go version | awk '{print $3}')
    log_success "Go ya instalado: $GO_VER"
fi

# Asegurar que $HOME/go/bin está en el PATH
if ! echo "$PATH" | grep -q "$HOME/go/bin"; then
    echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.bashrc
    export PATH="$PATH:$HOME/go/bin"
    log_info "PATH de Go añadido a ~/.bashrc"
fi

# ── 2. Herramientas del sistema ───────────────────────────────────────────────
log_info "Instalando herramientas del sistema..."
sudo apt update -qq
sudo apt install -y \
    parallel \
    nmap \
    masscan \
    jq \
    curl \
    wget \
    sqlmap \
    whatweb \
    wafw00f \
    python3 \
    python3-pip \
    nodejs \
    npm

# ── 3. Herramientas Go ────────────────────────────────────────────────────────
log_phase "Instalando herramientas Go"

install_go_tool "subfinder"  "github.com/projectdiscovery/subfinder/v2/cmd/subfinder"
install_go_tool "httpx"      "github.com/projectdiscovery/httpx/cmd/httpx"
install_go_tool "dnsx"       "github.com/projectdiscovery/dnsx/cmd/dnsx"
install_go_tool "naabu"      "github.com/projectdiscovery/naabu/v2/cmd/naabu"
install_go_tool "nuclei"     "github.com/projectdiscovery/nuclei/v3/cmd/nuclei"
install_go_tool "katana"     "github.com/projectdiscovery/katana/cmd/katana"
install_go_tool "gau"        "github.com/lc/gau/v2/cmd/gau"
install_go_tool "ffuf"       "github.com/ffuf/ffuf/v2"
install_go_tool "getJS"      "github.com/003random/getJS/v2"
install_go_tool "mantra"     "github.com/Brosck/mantra"
install_go_tool "subzy"      "github.com/LukaSikic/subzy"
install_go_tool "dalfox"     "github.com/hahwul/dalfox/v2"

# Amass (instalación especial)
if ! command -v amass &>/dev/null; then
    log_info "Instalando amass..."
    go install -v github.com/owasp-amass/amass/v4/...@master 2>&1 || \
        log_warn "amass: instalación manual puede ser necesaria. Ver: https://github.com/owasp-amass/amass"
else
    log_success "amass ya instalado."
fi

# ── 4. Nuclei: actualizar plantillas ──────────────────────────────────────────
if command -v nuclei &>/dev/null; then
    log_info "Actualizando plantillas de nuclei..."
    nuclei -update-templates -silent || true
fi

# ── 5. Wordlists ─────────────────────────────────────────────────────────────
log_phase "Descargando Wordlists"
mkdir -p "$SCRIPT_DIR/wordlists"

download_wordlist() {
    local name="$1"
    local url="$2"
    local dest="$SCRIPT_DIR/wordlists/$name"
    if [ ! -f "$dest" ]; then
        log_info "Descargando $name..."
        wget -q --show-progress -O "$dest" "$url" && log_success "$name descargada." || log_warn "No se pudo descargar $name"
    else
        log_success "$name ya existe, omitiendo."
    fi
}

download_wordlist "subdomains.txt" \
    "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/subdomains-top1million-5000.txt"
download_wordlist "directories.txt" \
    "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/common.txt"
download_wordlist "params.txt" \
    "https://raw.githubusercontent.com/s0md3v/Arjun/master/arjun/db/params.txt"

# ── 6. Dependencias del Web UI (Node.js) ─────────────────────────────────────
log_phase "Instalando dependencias del Web UI"
if [ -d "$SCRIPT_DIR/web-ui" ]; then
    cd "$SCRIPT_DIR/web-ui"
    npm install --silent
    cd "$SCRIPT_DIR"
    log_success "Dependencias del Web UI instaladas."
fi

# ── 7. Permisos ───────────────────────────────────────────────────────────────
log_phase "Configurando permisos"
chmod +x "$SCRIPT_DIR/bounty.sh"
chmod +x "$SCRIPT_DIR/start-ui.sh"
find "$SCRIPT_DIR/modules" -name "*.sh" -exec chmod +x {} \;
find "$SCRIPT_DIR/core"    -name "*.sh" -exec chmod +x {} \;

# ── Fin ───────────────────────────────────────────────────────────────────────
log_phase "Instalación Completada"
log_success "Todo listo. Usa './bounty.sh -d objetivo.com' para empezar."
log_info   "Lanza la interfaz web con: ./start-ui.sh"
log_warn   "Recuerda ejecutar 'source ~/.bashrc' o abrir una nueva terminal."
