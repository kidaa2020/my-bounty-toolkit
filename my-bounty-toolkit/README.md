# 🎯 Bug Bounty Toolkit

Un orquestador de bug bounty **modular, progresivo y 100% gratuito** para Kali Linux. Automatiza todas las fases clave del reconocimiento y análisis de vulnerabilidades, con una **interfaz web premium en tiempo real**.

---

## ✨ Características

| Característica | Descripción |
|---|---|
| **Modular** | Cada fase es un script independiente en `modules/` |
| **3 modos** | `quick` · `standard` · `deep` |
| **Web UI** | Interfaz local en `http://localhost:3000` con diseño iOS |
| **Tiempo real** | Logs en vivo vía Socket.io, progreso de fases animado |
| **Sin IA / Sin APIs** | 100% herramientas open-source, sin límites de tasa |
| **Reporte HTML** | Reporte final con hallazgos Nuclei, secretos JS, takeovers |

---

## 🛠️ Stack de herramientas integradas

**Reconocimiento:** `subfinder` · `amass` · `dnsx` · `httpx` · `naabu`  
**Contenido:** `katana` · `gau` · `ffuf`  
**JavaScript:** `getJS` · `mantra`  
**Vulnerabilidades:** `nuclei` · `dalfox` · `sqlmap` · `subzy`

---

## 📦 Instalación (Kali Linux)

```bash
# 1. Clonar el repositorio
git clone https://github.com/TU_USUARIO/my-bounty-toolkit.git
cd my-bounty-toolkit

# 2. Instalar todo (Go, herramientas, wordlists, Node.js deps)
chmod +x install.sh && ./install.sh

# 3. Aplicar el nuevo PATH de Go
source ~/.bashrc
```

---

## 🚀 Uso

### Interfaz Web (recomendado)
```bash
./start-ui.sh          # Abre http://localhost:3000
./start-ui.sh --port 8080   # Puerto personalizado
```

### Línea de comandos
```bash
./bounty.sh -d ejemplo.com              # Modo standard
./bounty.sh -d ejemplo.com -m quick    # Solo crítico/alto, más rápido
./bounty.sh -d ejemplo.com -m deep     # Escaneo completo (amass, sqlmap...)
./bounty.sh -d ejemplo.com -o ~/scans  # Carpeta de salida personalizada
```

---

## 🗂️ Estructura del proyecto

```
my-bounty-toolkit/
├── bounty.sh                 # Orquestador principal
├── install.sh                # Instalador de dependencias
├── start-ui.sh               # Lanzador de la Web UI
├── config/
│   └── config.conf           # Configuración global (rate limit, cabeceras, etc.)
├── core/lib/
│   └── common.sh             # Funciones compartidas (logging, run_cmd, etc.)
├── modules/
│   ├── recon/
│   │   ├── subdomain_enum.sh # subfinder + amass + dnsx
│   │   └── host_alive.sh     # httpx + naabu + subzy
│   ├── content/
│   │   └── url_discovery.sh  # katana + gau + ffuf
│   ├── js/
│   │   └── js_analysis.sh    # getJS + mantra
│   ├── scan/
│   │   └── vuln_scan.sh      # nuclei + dalfox + sqlmap
│   └── report/
│       └── generate_report.sh# Reporte HTML final
├── web-ui/
│   ├── server.js             # Backend Express + Socket.io
│   └── public/               # Frontend (HTML/CSS/JS vanilla)
├── wordlists/                # Descargadas por install.sh
└── output/                   # Resultados (ignorado por git)
```

---

## ⚙️ Configuración

Edita `config/config.conf` para personalizar:

```bash
CUSTOM_HEADER="X-HackerOne-Research: TU_USUARIO"  # Cabecera identificativa
PARALLEL_JOBS=5     # Trabajos en paralelo
RATE_LIMIT=150      # Peticiones/segundo
TIMEOUT=10          # Timeout por defecto
WEB_UI_PORT=3000    # Puerto de la interfaz web
```

---

## ⚠️ Advertencia Legal

Esta herramienta está diseñada **únicamente para pruebas de seguridad en sistemas con autorización explícita por escrito**. El uso no autorizado puede violar leyes locales e internacionales. El autor no se responsabiliza del mal uso.
