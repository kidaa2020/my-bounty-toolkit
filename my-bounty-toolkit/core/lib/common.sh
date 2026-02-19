#!/bin/bash
# =============================================================================
# common.sh — Funciones auxiliares compartidas por todos los módulos
# =============================================================================

# Colores (se exportan para que los módulos hereados los usen)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# === Logging ===
log_info() {
    echo -e "${BLUE}[*]${NC} $(date +'%Y-%m-%d %H:%M:%S') — $1"
}

log_success() {
    echo -e "${GREEN}[+]${NC} $(date +'%Y-%m-%d %H:%M:%S') — $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $(date +'%Y-%m-%d %H:%M:%S') — $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $(date +'%Y-%m-%d %H:%M:%S') — $1" >&2
}

log_phase() {
    echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"
}

# === Verificar si una herramienta está instalada ===
check_tool() {
    if ! command -v "$1" &>/dev/null; then
        log_warn "La herramienta '$1' no está instalada o no está en el PATH."
        return 1
    fi
    return 0
}

# === Instalar herramienta Go si no existe ===
install_go_tool() {
    local tool_name="$1"
    local install_path="$2"

    if check_tool "$tool_name" 2>/dev/null; then
        log_success "$tool_name ya está instalado."
        return 0
    fi

    log_info "Instalando $tool_name desde $install_path ..."
    go install "${install_path}@latest" 2>&1
    if command -v "$tool_name" &>/dev/null; then
        log_success "$tool_name instalado correctamente."
    else
        log_error "Error al instalar $tool_name. Instálalo manualmente."
        return 1
    fi
}

# === Ejecutar comando con log ===
# Uso: run_cmd "comando -args" "/ruta/al/log.txt"
run_cmd() {
    local cmd="$1"
    local log_file="${2:-/dev/null}"

    log_info "Ejecutando: $cmd"
    eval "$cmd" >>"$log_file" 2>&1
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_warn "El comando terminó con código $exit_code. Revisa: $log_file"
    fi
    return $exit_code
}

# === Ejecutar comandos en paralelo con GNU parallel ===
# Uso: run_parallel "/ruta/a/cmds.txt" [n_jobs]
run_parallel() {
    local commands_file="$1"
    local jobs="${2:-5}"

    if ! command -v parallel &>/dev/null; then
        log_error "GNU Parallel no instalado. Ejecuta: sudo apt install parallel"
        return 1
    fi

    parallel -j "$jobs" --bar <"$commands_file"
}

# === Contar líneas de un fichero de forma segura ===
count_lines() {
    local file="$1"
    if [ -f "$file" ]; then
        wc -l <"$file" | tr -d ' '
    else
        echo "0"
    fi
}

# === Verificar que el fichero de entrada no está vacío ===
require_input() {
    local file="$1"
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        log_error "Fichero de entrada vacío o inexistente: $file"
        return 1
    fi
    return 0
}
