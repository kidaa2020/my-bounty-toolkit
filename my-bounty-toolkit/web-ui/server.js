// =============================================================================
// server.js — Bug Bounty Toolkit Web UI Backend
// Express + Socket.io: real-time log streaming and scan control
// =============================================================================

'use strict';

const express    = require('express');
const http       = require('http');
const { Server } = require('socket.io');
const path       = require('path');
const fs         = require('fs');
const fse        = require('fs-extra');
const chokidar   = require('chokidar');
const { exec, spawn } = require('child_process');

const app    = express();
const server = http.createServer(app);
const io     = new Server(server, { cors: { origin: '*' } });

// ── Config ────────────────────────────────────────────────────────────────────
const PORT       = process.env.PORT || 3000;
const TOOLKIT    = path.resolve(__dirname, '..');
const OUTPUT_DIR = path.join(TOOLKIT, 'output');
const LOG_DIR    = path.join(TOOLKIT, 'output', 'logs');

// ── Static files ──────────────────────────────────────────────────────────────
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
fse.ensureDirSync(OUTPUT_DIR);

// ── REST API ──────────────────────────────────────────────────────────────────

// GET /api/scans — list all completed/running scans
app.get('/api/scans', (req, res) => {
    if (!fs.existsSync(OUTPUT_DIR)) return res.json([]);
    try {
        const scans = fs.readdirSync(OUTPUT_DIR)
            .filter(name => {
                const full = path.join(OUTPUT_DIR, name);
                return fs.statSync(full).isDirectory();
            })
            .map(name => {
                const scanDir = path.join(OUTPUT_DIR, name);
                const reportPath = path.join(scanDir, 'report.html');
                const parts = name.split('_');
                const domain = parts[0];
                const mode   = parts[parts.length - 1];
                const date   = parts.slice(1, parts.length - 1).join('_');
                return {
                    id: name,
                    domain,
                    mode,
                    date,
                    hasReport: fs.existsSync(reportPath),
                    stats: getScanStats(scanDir),
                };
            })
            .reverse(); // newest first
        res.json(scans);
    } catch (e) {
        res.json([]);
    }
});

// GET /api/scans/:id/report — serve the HTML report
app.get('/api/scans/:id/report', (req, res) => {
    const reportPath = path.join(OUTPUT_DIR, req.params.id, 'report.html');
    if (fs.existsSync(reportPath)) {
        res.sendFile(reportPath);
    } else {
        res.status(404).json({ error: 'Report not found' });
    }
});

// GET /api/scans/:id/events — get the jsonl events log
app.get('/api/scans/:id/events', (req, res) => {
    const eventsPath = path.join(OUTPUT_DIR, req.params.id, 'logs', 'events.jsonl');
    if (!fs.existsSync(eventsPath)) return res.json([]);
    try {
        const lines = fs.readFileSync(eventsPath, 'utf8')
            .trim().split('\n')
            .filter(l => l.trim())
            .map(l => JSON.parse(l));
        res.json(lines);
    } catch (e) {
        res.json([]);
    }
});

// POST /api/scan — start a new scan
app.post('/api/scan', (req, res) => {
    const { domain, mode = 'standard' } = req.body;
    if (!domain) return res.status(400).json({ error: 'domain required' });

    const bountyScript = path.join(TOOLKIT, 'bounty.sh');
    if (!fs.existsSync(bountyScript)) {
        return res.status(500).json({ error: 'bounty.sh not found in toolkit root' });
    }

    // Generate expected scan name prefix to track it
    const ts = new Date().toISOString()
        .replace(/[-T:]/g, '').slice(0, 15).replace(/(\d{8})(\d{6})/, '$1_$2');

    res.json({ status: 'started', domain, mode });

    // Launch the scan
    const proc = spawn('bash', [bountyScript, '-d', domain, '-m', mode], {
        cwd: TOOLKIT,
        detached: false,
    });

    let scanId = null;

    proc.stdout.on('data', data => {
        const text = data.toString();
        // Broadcast raw stdout lines
        text.split('\n').filter(l => l.trim()).forEach(line => {
            io.emit('log', { scanId, line, stream: 'stdout' });
        });
    });

    proc.stderr.on('data', data => {
        const text = data.toString();
        text.split('\n').filter(l => l.trim()).forEach(line => {
            io.emit('log', { scanId, line, stream: 'stderr' });
        });
    });

    proc.on('close', code => {
        io.emit('scan_done', { scanId, exitCode: code });
        // Refresh scan list
        io.emit('scans_updated');
    });

    // Watch the output directory for the new scan folder
    const watcher = chokidar.watch(OUTPUT_DIR, { depth: 0, ignoreInitial: true });
    watcher.on('addDir', newPath => {
        const name = path.basename(newPath);
        if (name.startsWith(domain)) {
            scanId = name;
            io.emit('scan_started', { scanId, domain, mode });
            watcher.close();

            // Watch the events.jsonl file for structured events
            const eventsFile = path.join(newPath, 'logs', 'events.jsonl');
            watchEventsFile(eventsFile, scanId);
        }
    });
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function watchEventsFile(eventsFile, scanId) {
    // Wait for the file to appear
    let attempts = 0;
    const check = setInterval(() => {
        if (fs.existsSync(eventsFile) || attempts > 60) {
            clearInterval(check);
            if (!fs.existsSync(eventsFile)) return;
            let lastSize = 0;
            const watcher = chokidar.watch(eventsFile);
            watcher.on('change', () => {
                const stat = fs.statSync(eventsFile);
                if (stat.size <= lastSize) return;
                const buf = Buffer.alloc(stat.size - lastSize);
                const fd  = fs.openSync(eventsFile, 'r');
                fs.readSync(fd, buf, 0, buf.length, lastSize);
                fs.closeSync(fd);
                lastSize = stat.size;
                buf.toString().split('\n').filter(l => l.trim()).forEach(line => {
                    try {
                        const evt = JSON.parse(line);
                        io.emit('phase_event', { scanId, ...evt });
                    } catch (_) {}
                });
            });
        }
        attempts++;
    }, 1000);
}

function getScanStats(scanDir) {
    const safe = (f) => {
        try { return fs.readFileSync(f,'utf8').trim().split('\n').filter(l=>l).length; }
        catch { return 0; }
    };
    return {
        subdomains: safe(path.join(scanDir, 'recon', 'subdomains_final.txt')),
        liveUrls:   safe(path.join(scanDir, 'recon', 'urls_live.txt')),
        totalUrls:  safe(path.join(scanDir, 'content', 'urls_all.txt')),
        jsFiles:    safe(path.join(scanDir, 'js', 'js_files.txt')),
        nucleiFindings: safe(path.join(scanDir, 'vulns', 'nuclei_results.txt')),
        secrets:    safe(path.join(scanDir, 'js', 'secrets_found.txt')),
    };
}

// ── Socket.io ─────────────────────────────────────────────────────────────────
io.on('connection', socket => {
    console.log('[WS] Client connected:', socket.id);
    socket.on('disconnect', () => console.log('[WS] Client disconnected:', socket.id));
    // Client can request scan list refresh
    socket.on('get_scans', async () => {
        socket.emit('scans_updated');
    });
});

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(PORT, () => {
    console.log(`\n🎯 Bug Bounty Toolkit UI running at http://localhost:${PORT}\n`);
});
