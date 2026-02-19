// =============================================================================
// app.js — Bug Bounty Toolkit Frontend
// Socket.io client: real-time logs, phase events, scan control
// =============================================================================

'use strict';

// ── State ─────────────────────────────────────────────────────────────────────
const state = {
    selectedMode: 'standard',
    activeScanId: null,
    autoscroll: true,
    scans: [],
    currentReportScanId: null,
};

// ── Socket.io ─────────────────────────────────────────────────────────────────
const socket = io();

socket.on('connect', () => {
    setWsStatus(true);
    toast('Connected to toolkit server');
    loadScans();
});

socket.on('disconnect', () => {
    setWsStatus(false);
});

// New scan folder detected → update UI
socket.on('scan_started', ({ scanId, domain, mode }) => {
    state.activeScanId = scanId;
    document.getElementById('active-banner').style.display = 'flex';
    document.getElementById('banner-text').textContent = `Scanning ${domain} [${mode}]...`;
    document.getElementById('log-badge').style.display = '';
    document.getElementById('terminal-subtitle').textContent = `Active: ${scanId}`;
    resetPhases();
    toast(`🚀 Scan started: ${domain}`);
});

// Raw stdout/stderr lines → terminal
socket.on('log', ({ line, stream }) => {
    appendLog(line, classifyLine(line));
});

// Structured phase events → dashboard
socket.on('phase_event', ({ phase, message, status }) => {
    updatePhase(phase, status);
    appendLog(`[${phase.toUpperCase()}] ${message}`, status === 'done' ? 'success' : 'info');
});

// Scan finished
socket.on('scan_done', ({ scanId, exitCode }) => {
    state.activeScanId = null;
    document.getElementById('active-banner').style.display = 'none';
    document.getElementById('log-badge').style.display = 'none';
    const msg = exitCode === 0 ? '✅ Scan completed!' : `⚠️ Scan ended (exit ${exitCode})`;
    appendLog(msg, exitCode === 0 ? 'success' : 'warn');
    toast(msg);
    loadScans();
    // Show report nav if we have a report
    setTimeout(() => {
        loadScans();
    }, 1000);
});

// Scans list updated
socket.on('scans_updated', () => {
    loadScans();
});

// ── View Navigation ───────────────────────────────────────────────────────────
let currentView = 'dashboard';

function switchView(viewId, navEl) {
    // Remove active from all nav items
    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
    if (navEl) navEl.classList.add('active');

    // Animate out current view
    const current = document.getElementById(`view-${currentView}`);
    if (current) {
        current.classList.remove('active');
        current.classList.add('slide-out');
        setTimeout(() => current.classList.remove('slide-out'), 350);
    }

    // Animate in new view
    currentView = viewId;
    const next = document.getElementById(`view-${viewId}`);
    if (next) {
        // small delay for spring feel
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                next.classList.add('active');
            });
        });
    }

    // Lazily load history when switching to it
    if (viewId === 'history') renderHistory();
}

// ── Scan Launch ───────────────────────────────────────────────────────────────
function selectMode(mode, btn) {
    state.selectedMode = mode;
    document.querySelectorAll('.mode-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
}

async function launchScan() {
    const domain = document.getElementById('target-domain').value.trim();
    if (!domain) {
        toast('⚠️ Please enter a target domain');
        shakeLaunchBtn();
        return;
    }

    const btn = document.getElementById('launch-btn');
    btn.disabled = true;
    btn.innerHTML = '<span class="btn-icon">⏳</span><span>Starting...</span>';

    try {
        const res = await fetch('/api/scan', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ domain, mode: state.selectedMode }),
        });

        if (!res.ok) {
            const err = await res.json();
            throw new Error(err.error || 'Server error');
        }

        // Switch to terminal view to watch live output
        clearTerminal();
        switchView('terminal', document.querySelector('[data-view="terminal"]'));
        toast(`🚀 Launching ${state.selectedMode} scan against ${domain}`);
    } catch (err) {
        toast(`❌ Error: ${err.message}`);
        btn.disabled = false;
        btn.innerHTML = '<span class="btn-icon">🚀</span><span>Launch Scan</span>';
    } finally {
        // Reset button after a moment
        setTimeout(() => {
            btn.disabled = false;
            btn.innerHTML = '<span class="btn-icon">🚀</span><span>Launch Scan</span>';
        }, 3000);
    }
}

function shakeLaunchBtn() {
    const btn = document.getElementById('launch-btn');
    btn.style.animation = 'none';
    btn.offsetHeight; // reflow
    btn.style.animation = 'shake 0.4s ease';
    setTimeout(() => btn.style.animation = '', 400);
}

// ── Terminal ──────────────────────────────────────────────────────────────────
function appendLog(text, type = 'default') {
    const output = document.getElementById('terminal-output');
    const line = document.createElement('span');
    line.className = `log-line ${type}`;
    line.textContent = text;
    output.appendChild(line);

    if (state.autoscroll) {
        output.scrollTop = output.scrollHeight;
    }
}

function clearTerminal() {
    document.getElementById('terminal-output').innerHTML = '';
}

function toggleAutoscroll() {
    state.autoscroll = !state.autoscroll;
    const btn = document.getElementById('autoscroll-btn');
    btn.textContent = `⬇ Auto-scroll: ${state.autoscroll ? 'ON' : 'OFF'}`;
    btn.style.opacity = state.autoscroll ? '1' : '0.5';
}

function classifyLine(line) {
    const l = line.toLowerCase();
    if (l.includes('[+]') || l.includes('success') || l.includes('completad') || l.includes('found')) return 'success';
    if (l.includes('[!]') || l.includes('warn') || l.includes('advertenc')) return 'warn';
    if (l.includes('[✗]') || l.includes('error') || l.includes('falló')) return 'error';
    if (l.includes('═══') || l.includes('fase ')) return 'phase';
    if (l.includes('[*]') || l.includes('info') || l.includes('ejecutand')) return 'info';
    return 'default';
}

// ── Phases ───────────────────────────────────────────────────────────────────
const PHASE_MAP = {
    recon: 'phase-recon',
    hosts: 'phase-hosts',
    urls: 'phase-urls',
    js: 'phase-js',
    vulns: 'phase-vulns',
    report: 'phase-report',
    finish: null,
};

function updatePhase(phase, status) {
    const id = PHASE_MAP[phase];
    if (!id) return;

    const el = document.getElementById(id);
    if (!el) return;

    el.className = `phase-status ${status === 'running' ? 'running' : status === 'done' ? 'done' : status === 'error' ? 'error' : 'idle'}`;
    el.textContent = status;

    // Also update the parent phase-item class
    const item = el.closest('.phase-item');
    if (item) {
        item.className = `phase-item ${status}`;
    }
}

function resetPhases() {
    Object.keys(PHASE_MAP).forEach(phase => {
        const id = PHASE_MAP[phase];
        if (!id) return;
        const el = document.getElementById(id);
        if (el) {
            el.className = 'phase-status idle';
            el.textContent = 'idle';
            el.closest('.phase-item')?.classList.remove('running', 'done', 'error');
        }
    });
    // Reset stats
    ['stat-subdomains', 'stat-live', 'stat-urls', 'stat-js', 'stat-crit', 'stat-high']
        .forEach(id => { document.getElementById(id).textContent = '—'; });
}

// ── History / Scans ───────────────────────────────────────────────────────────
async function loadScans() {
    try {
        const res = await fetch('/api/scans');
        state.scans = await res.json();

        // If there's the most recent scan with report, show nav
        if (state.scans.length > 0 && state.scans[0].hasReport) {
            document.getElementById('report-nav').style.display = '';
            if (!state.currentReportScanId) {
                state.currentReportScanId = state.scans[0].id;
            }
        }

        // Update stat cards from most recent scan
        if (state.scans.length > 0) {
            const latest = state.scans[0];
            updateStats(latest.stats);
        }

        if (currentView === 'history') renderHistory();
    } catch (e) {
        console.error('Failed to load scans:', e);
    }
}

function updateStats(stats) {
    if (!stats) return;
    document.getElementById('stat-subdomains').textContent = fmt(stats.subdomains);
    document.getElementById('stat-live').textContent = fmt(stats.liveUrls);
    document.getElementById('stat-urls').textContent = fmt(stats.totalUrls);
    document.getElementById('stat-js').textContent = fmt(stats.jsFiles);
    // nuclei findings count as a rough proxy (no severity split readily available)
    document.getElementById('stat-crit').textContent = fmt(stats.nucleiFindings);
    document.getElementById('stat-high').textContent = fmt(stats.secrets);
}

function fmt(n) {
    return n !== undefined ? n.toLocaleString() : '—';
}

function renderHistory() {
    const list = document.getElementById('history-list');
    if (!state.scans.length) {
        list.innerHTML = `<div class="empty-state"><span class="empty-icon">📭</span><p>No scans yet. Launch your first scan!</p></div>`;
        return;
    }

    list.innerHTML = '';
    state.scans.forEach((scan, i) => {
        const item = document.createElement('div');
        item.className = 'history-item';
        item.style.animationDelay = `${i * 0.05}s`;
        item.innerHTML = `
      <div class="history-icon">🎯</div>
      <div class="history-info">
        <div class="history-domain">${esc(scan.domain)}</div>
        <div class="history-meta">${esc(scan.date)} · ${scan.stats?.subdomains || 0} subdomains · ${scan.stats?.liveUrls || 0} live</div>
      </div>
      <div class="history-stats">
        <span class="mode-tag">${esc(scan.mode)}</span>
        ${scan.stats?.nucleiFindings ? `<span class="stat-chip n">🔍 ${scan.stats.nucleiFindings}</span>` : ''}
        ${scan.hasReport ? '<span class="stat-chip n">📊 Report</span>' : ''}
      </div>
      <span class="history-caret">›</span>`;
        item.onclick = () => openScanReport(scan.id);
        list.appendChild(item);
    });
}

function openScanReport(scanId) {
    state.currentReportScanId = scanId;
    const scan = state.scans.find(s => s.id === scanId);
    document.getElementById('report-subtitle').textContent = scan ? scan.domain : scanId;
    document.getElementById('report-iframe').src = `/api/scans/${encodeURIComponent(scanId)}/report`;
    document.getElementById('report-nav').style.display = '';
    switchView('report', document.querySelector('[data-view="report"]'));
}

// ── WebSocket status ──────────────────────────────────────────────────────────
function setWsStatus(connected) {
    const dot = document.getElementById('ws-dot');
    const lbl = document.getElementById('ws-label');
    dot.className = `status-dot ${connected ? 'connected' : 'disconnected'}`;
    lbl.textContent = connected ? 'Connected' : 'Disconnected';
}

// ── Toast ─────────────────────────────────────────────────────────────────────
let toastTimer;
function toast(msg) {
    const el = document.getElementById('toast');
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 3000);
}

// ── Utility ───────────────────────────────────────────────────────────────────
function esc(str) {
    return String(str || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

// ── Shake animation (inline) ──────────────────────────────────────────────────
const shakeStyle = document.createElement('style');
shakeStyle.textContent = `@keyframes shake {
  0%,100%{transform:translateX(0)}
  20%{transform:translateX(-6px)}
  40%{transform:translateX(6px)}
  60%{transform:translateX(-4px)}
  80%{transform:translateX(4px)}
}`;
document.head.appendChild(shakeStyle);

// ── Init ──────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    // Enter key triggers scan launch
    document.getElementById('target-domain').addEventListener('keydown', e => {
        if (e.key === 'Enter') launchScan();
    });

    loadScans();
});
