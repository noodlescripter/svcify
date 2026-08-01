#!/usr/bin/env node
'use strict';

const express = require('express');
const WebSocket = require('ws');
const http = require('http');
const path = require('path');
const { spawn, execFile } = require('child_process');

const PORT = parseInt(process.env.SVCIFY_WEB_PORT || '8088', 10);
const HOST = process.env.SVCIFY_WEB_HOST || '127.0.0.1';
const SVCIFY_BIN = process.env.SVCIFY_BIN || 'svcify';

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

function runSvcify(args, opts = {}) {
  return new Promise((resolve, reject) => {
    execFile(SVCIFY_BIN, args, { maxBuffer: 4 * 1024 * 1024, ...opts }, (err, stdout, stderr) => {
      if (err) {
        const msg = [stderr && stderr.trim(), stdout && stdout.trim()].filter(Boolean).join('\n') || err.message;
        reject(new Error(msg));
      } else {
        resolve({ stdout, stderr });
      }
    });
  });
}

function parseSystemctlShow(name) {
  return new Promise((resolve) => {
    execFile('systemctl', ['show', name, '-p',
      'ActiveState,SubState,MainPID,MemoryCurrent,CPUUsageNSec,NRestarts,StateChangeTimestamp,Description,ExecStart,UnitFileState'],
      (err, stdout) => {
        if (err) return resolve(null);
        const props = {};
        for (const line of stdout.split('\n')) {
          const idx = line.indexOf('=');
          if (idx > 0) props[line.slice(0, idx)] = line.slice(idx + 1);
        }
        resolve(props);
      });
  });
}

function formatBytes(b) {
  if (!b || b === '[not set]' || isNaN(Number(b))) return '0B';
  b = Number(b);
  if (b >= 1e9) return (b / 1e9).toFixed(1) + 'GB';
  if (b >= 1e6) return (b / 1e6).toFixed(1) + 'MB';
  if (b >= 1e3) return (b / 1e3).toFixed(1) + 'KB';
  return b + 'B';
}

function formatUptime(ts) {
  if (!ts || ts === 'n/a') return '-';
  const sec = Math.floor(Date.now() / 1000 - new Date(ts).getTime() / 1000);
  if (isNaN(sec) || sec < 0) return '-';
  if (sec < 60) return sec + 's';
  if (sec < 3600) return Math.floor(sec / 60) + 'm ' + (sec % 60) + 's';
  if (sec < 86400) return Math.floor(sec / 3600) + 'h ' + Math.floor((sec % 3600) / 60) + 'm';
  return Math.floor(sec / 86400) + 'd ' + Math.floor((sec % 86400) / 3600) + 'h';
}

async function getServiceList() {
  const fs = require('fs');
  const dir = '/etc/systemd/system';
  let files = [];
  try { files = fs.readdirSync(dir).filter(f => f.endsWith('.service')); }
  catch { return []; }
  const out = [];
  for (const f of files) {
    let content;
    try { content = fs.readFileSync(path.join(dir, f), 'utf8'); } catch { continue; }
    if (!content.includes('Description=svcify:')) continue;
    const name = f.replace(/\.service$/, '');
    const props = await parseSystemctlShow(name);
    if (!props) continue;
    const status = props.ActiveState || 'unknown';
    const pid = props.MainPID && props.MainPID !== '0' ? props.MainPID : null;
    out.push({
      name,
      status,
      subState: props.SubState || '-',
      pid: pid || '-',
      memory: formatBytes(props.MemoryCurrent),
      cpuPct: '0.0',
      restarts: props.NRestarts || '0',
      uptime: formatUptime(props.StateChangeTimestamp),
      description: props.Description || '',
      enabled: props.UnitFileState || '-',
    });
  }
  return out;
}

app.get('/api/services', async (_req, res) => {
  try { res.json(await getServiceList()); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/services/:name', async (req, res) => {
  try {
    const props = await parseSystemctlShow(req.params.name);
    if (!props) return res.status(404).json({ error: 'not found' });
    const fs = require('fs');
    const unitFile = `/etc/systemd/system/${req.params.name}.service`;
    let content = '';
    try { content = fs.readFileSync(unitFile, 'utf8'); } catch {}
    res.json({
      name: req.params.name,
      status: props.ActiveState || 'unknown',
      subState: props.SubState || '-',
      pid: props.MainPID || '-',
      memory: formatBytes(props.MemoryCurrent),
      restarts: props.NRestarts || '0',
      uptime: formatUptime(props.StateChangeTimestamp),
      execStart: props.ExecStart || '',
      description: props.Description || '',
      enabled: props.UnitFileState || '-',
      unitFile: content,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/services', async (req, res) => {
  const { name, appDir, entry, node, java } = req.body || {};
  if (!name) return res.status(400).json({ error: 'name is required' });
  if (!appDir) return res.status(400).json({ error: 'appDir is required' });
  const args = ['install', name, '--app-dir', appDir];
  if (entry) args.push('--entry', entry);
  if (node) args.push('--node', node);
  if (java) args.push('--java', java);
  try {
    const r = await runSvcify(args);
    res.json({ ok: true, output: r.stdout + r.stderr });
  } catch (e) { res.status(400).json({ error: e.message }); }
});

app.delete('/api/services/:name', async (req, res) => {
  try {
    const r = await runSvcify(['uninstall', req.params.name]);
    res.json({ ok: true, output: r.stdout + r.stderr });
  } catch (e) { res.status(400).json({ error: e.message }); }
});

app.post('/api/services/:name/:action', async (req, res) => {
  const allowed = ['start', 'stop', 'restart'];
  if (!allowed.includes(req.params.action)) return res.status(400).json({ error: 'invalid action' });
  try {
    const r = await runSvcify([req.params.action, req.params.name]);
    res.json({ ok: true, output: r.stdout + r.stderr });
  } catch (e) { res.status(400).json({ error: e.message }); }
});

app.get('/api/services/:name/logs/history', (req, res) => {
  const n = parseInt(req.query.n || '200', 10);
  const child = spawn('journalctl', ['-u', req.params.name, '--no-pager', '-n', String(n), '-o', 'cat']);
  let out = '';
  child.stdout.on('data', d => out += d);
  child.on('close', () => res.type('text/plain').send(out));
});

app.get('/', (_req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

const server = http.createServer(app);
const wss = new WebSocket.Server({ noServer: true });
server.on('upgrade', (req, socket, head) => {
  const m = req.url.match(/^\/api\/services\/([^/]+)\/logs\/ws$/);
  if (!m) { socket.destroy(); return; }
  wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws, req));
});

wss.on('connection', (ws, req) => {
  const m = req.url.match(/^\/api\/services\/([^/]+)\/logs\/ws$/);
  if (!m) { ws.close(); return; }
  const name = m[1];
  const child = spawn('journalctl', ['-u', name, '-f', '--no-pager', '-o', 'cat']);
  let buf = '';
  child.stdout.on('data', d => {
    buf += d.toString();
    let idx;
    while ((idx = buf.indexOf('\n')) >= 0) {
      ws.send(JSON.stringify({ type: 'log', line: buf.slice(0, idx) }));
      buf = buf.slice(idx + 1);
    }
  });
  child.on('error', () => ws.send(JSON.stringify({ type: 'error', line: 'failed to start journalctl' })));
  const cleanup = () => { child.kill(); ws.close(); };
  ws.on('close', cleanup);
  ws.on('error', cleanup);
  process.on('SIGTERM', cleanup);
  process.on('SIGINT', cleanup);
});

server.listen(PORT, HOST, () => {
  console.log(`svcify web UI on http://${HOST}:${PORT}`);
  if (process.getuid && process.getuid() !== 0) {
    console.warn('WARNING: not running as root. install/uninstall/start/stop/restart will fail.');
    console.warn('         Start with: sudo svcify web');
  }
});