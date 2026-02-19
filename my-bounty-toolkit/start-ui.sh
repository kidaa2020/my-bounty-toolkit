#!/bin/bash
# =============================================================================
# start-ui.sh — Lanza el servidor Web UI del Toolkit de Bug Bounty
# Uso: ./start-ui.sh [--port 3000]
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DIR="$SCRIPT_DIR/web-ui"

# Cargar configuración para leer WEB_UI_PORT
if [ -f "$SCRIPT_DIR/config/config.conf" ]; then
    source "$SCRIPT_DIR/config/config.conf"
fi

PORT="${WEB_UI_PORT:-3000}"

# Parsear argumentos de línea de comandos
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port|-p) PORT="$2"; shift 2 ;;
        --help|-h)
            echo "Uso: $0 [--port PUERTO]"
            echo "  Por defecto el puerto es el definido en config/config.conf (WEB_UI_PORT=3000)"
            exit 0 ;;
        *) shift ;;
    esac
done

# Verificar Node.js
if ! command -v node &>/dev/null; then
    echo "[✗] Node.js no está instalado."
    echo "    En Kali Linux: sudo apt install nodejs npm"
    exit 1
fi

# Verificar dependencias del web-ui
if [ ! -d "$UI_DIR/node_modules" ]; then
    echo "[*] Instalando dependencias del Web UI..."
    cd "$UI_DIR"
    npm install --silent
    cd "$SCRIPT_DIR"
fi

# Crear directorio de output por si no existe todavía
mkdir -p "$SCRIPT_DIR/output"

echo ""
echo "  ██████╗  ██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗"
echo "  ██╔══██╗██╔═══██╗██║   ██║████╗  ██║╚══██╔══╝╚██╗ ██╔╝"
echo "  ██████╔╝██║   ██║██║   ██║██╔██╗ ██║   ██║    ╚████╔╝ "
echo "  ██╔══██╗██║   ██║██║   ██║██║╚██╗██║   ██║     ╚██╔╝  "
echo "  ██████╔╝╚██████╔╝╚██████╔╝██║ ╚████║   ██║      ██║   "
echo "  ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝      ╚═╝   "
echo "  ██╗  ██╗██╗████████╗                                    "
echo "  ██║ ██╔╝██║╚══██╔══╝  Bug Bounty Toolkit               "
echo "  █████╔╝ ██║   ██║     Web Interface v1.0               "
echo "  ██╔═██╗ ██║   ██║                                       "
echo "  ██║  ██╗██║   ██║                                       "
echo "  ╚═╝  ╚═╝╚═╝   ╚═╝                                       "
echo ""
echo "  🌐 Abriendo interfaz en: http://localhost:${PORT}"
echo "  💡 Usa Ctrl+C para detener el servidor"
echo ""

# Intentar abrir el navegador automáticamente (Kali Linux)
(
    sleep 2
    if command -v xdg-open &>/dev/null; then
        xdg-open "http://localhost:${PORT}" &>/dev/null &
    elif command -v firefox &>/dev/null; then
        firefox "http://localhost:${PORT}" &>/dev/null &
    fi
) &

# Lanzar el servidor
cd "$UI_DIR"
PORT="$PORT" node server.js
