#!/bin/bash
# =============================================================================
# install.sh — Instalador de dependencias del Bug Bounty Toolkit
# =============================================================================

set -euo pipefail

# Colores para la salida
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[*]$(date + ' %Y-%m-%d %H:%M:%S') — $1${NC}"; }
log_success() { echo -e "${GREEN}[+]$(date + ' %Y-%m-%d %H:%M:%S') — $1${NC}"; }
log_error() { echo -e "${RED}[✗]$(date + ' %Y-%m-%d %H:%M:%S') — $1${NC}"; }

echo -e "${BOLD}${BLUE}══════════════════════════════════════════"
echo -e "  Instalador del Toolkit de Bug Bounty"
echo -e "══════════════════════════════════════════${NC}"

# 0. Arreglar finales de línea de Windows (CRLF a LF)
log_info "Arreglando finales de línea (CRLF -> LF)..."
find . -type f \( -name "*.sh" -o -name "*.conf" \) -exec sed -i 's/\r//' {} +

# 1. Verificar/Instalar Go
if ! command -v go &>/dev/null; then
    log_info "Instalando Go..."
    sudo apt update && sudo apt install -y golang-go
else
    log_success "Go ya instalado: $(go version | awk '{print $3}')"
fi

# Configurar PATH de Go
if ! grep -q "go/bin" ~/.bashrc; then
    echo 'export GOPATH=$HOME/go' >> ~/.bashrc
    echo 'export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin' >> ~/.bashrc
    log_info "PATH de Go añadido a ~/.bashrc. Por favor, ejecuta 'source ~/.bashrc' después de terminar."
fi
export GOPATH=$HOME/go
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin

# 2. Instalar herramientas del sistema
log_info "Instalando herramientas del sistema..."
sudo apt update
sudo apt install -y \
    parallel \
    nmap \
    masscan \
    jq \
    curl \
    wget \
    sqlmap \
    whatweb \
    libpcap-dev \
    nodejs

# 3. Instalar herramientas de Go
log_info "Instalando herramientas de Go (puede tardar)..."

install_go_tool() {
    local name=$1
    local path=$2
    log_info "Instalando $name..."
    go install "$path@latest" > /dev/null 2>&1 || log_error "Error instalando $name"
}

install_go_tool "subfinder" "github.com/projectdiscovery/subfinder/v2/cmd/subfinder"
install_go_tool "amass" "github.com/owasp-amass/amass/v4/... "
install_go_tool "dnsx" "github.com/projectdiscovery/dnsx/cmd/dnsx"
install_go_tool "httpx" "github.com/projectdiscovery/httpx/cmd/httpx"
install_go_tool "naabu" "github.com/projectdiscovery/naabu/v2/cmd/naabu"
install_go_tool "katana" "github.com/projectdiscovery/katana/cmd/katana"
install_go_tool "gau" "github.com/lc/gau/v2/cmd/gau"
install_go_tool "ffuf" "github.com/ffuf/ffuf/v2"
install_go_tool "getJS" "github.com/0x2n/getJS"
install_go_tool "mantra" "github.com/MrEmpy/mantra"
install_go_tool "nuclei" "github.com/projectdiscovery/nuclei/v3/cmd/nuclei"
install_go_tool "dalfox" "github.com/hahwul/dalfox/v2"
install_go_tool "subzy" "github.com/PentestPad/subzy"

# 4. Descargar Wordlists básicas
log_info "Descargando wordlists..."
mkdir -p wordlists
wget -q "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/subdomains-top1million-5000.txt" -O wordlists/subdomains.txt
wget -q "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/common.txt" -O wordlists/directories.txt
wget -q "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/api/api-endpoints.txt" -O wordlists/params.txt

# 5. Instalar dependencias del Web UI
log_info "Instalando dependencias de Node.js..."
cd web-ui
npm install --silent
cd ..

# 6. Permisos
log_info "Configurando permisos..."
chmod +x bounty.sh start-ui.sh
find modules -name "*.sh" -exec chmod +x {} \;

log_success "Instalación completada correctamente."
log_info "RECUERDA: Ejecuta 'source ~/.bashrc' antes de usar el toolkit."
