'use strict';

const view = document.getElementById('view');
let currentRoute = 'dashboard';
let currentName = null;
let pollTimer = null;
let ws = null;
let connOk = true;
let logLines = [];

function clearPoll() { if (pollTimer) { clearInterval(pollTimer); pollTimer = null; } }
function closeWs() { if (ws) { try { ws.close(); } catch {} ws = null; } }

function setConn(ok) {
  if (ok === connOk) return;
  connOk = ok;
  const el = document.getElementById('connIndicator');
  el.className = 'conn ' + (ok ? 'ok' : 'bad');
  el.title = ok ? 'connected' : 'server unreachable';
}

/* ---------- Toasts ---------- */
function toast(msg, type = '', ms = 3500) {
  const wrap = document.getElementById('toasts');
  const t = document.createElement('div');
  t.className = 'toast ' + type;
  t.textContent = msg;
  wrap.appendChild(t);
  setTimeout(() => { t.classList.add('fade'); setTimeout(() => t.remove(), 300); }, ms);
}

/* ---------- Routing ---------- */
function setRoute(r, name) {
  clearPoll(); closeWs();
  currentRoute = r; currentName = name || null;
  document.querySelectorAll('nav a').forEach(a => a.classList.toggle('active', a.dataset.route === r && !name));
  if (r === 'dashboard') renderDashboard();
  else if (r === 'create') renderCreate();
  else if (r === 'detail') renderDetail(name);
}

document.querySelectorAll('nav a').forEach(a => a.addEventListener('click', e => { e.preventDefault(); setRoute(a.dataset.route); }));
document.getElementById('refresh').addEventListener('click', () => { setConn(true); setRoute(currentRoute, currentName); });
document.addEventListener('keydown', e => {
  if (e.key === 'Escape' && currentRoute === 'detail') setRoute('dashboard');
  if (e.key === 'r' && !e.target.matches('input,textarea')) setRoute(currentRoute, currentName);
});

/* ---------- Helpers ---------- */
function badgeHtml(status) {
  const cls = ['active','inactive','failed'].includes(status) ? status : 'unknown';
  const dot = status === 'active' ? '<span class="dot active"></span>' : '<span class="dot"></span>';
  return `<span class="badge ${cls}">${dot}${esc(status)}</span>`;
}

async function fetchJSON(url, opts) {
  let r;
  try { r = await fetch(url, opts); }
  catch (e) { setConn(false); throw new Error('server unreachable'); }
  setConn(true);
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(body.error || r.statusText);
  return body;
}

function esc(s) { const d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }

async function svcAction(name, act, opts = {}) {
  const url = '/api/services/' + encodeURIComponent(name) + (act ? '/' + act : '');
  return fetchJSON(url, { method: opts.method || 'POST', body: opts.body, headers: opts.headers });
}

function disableActions(container, disabled) {
  container.querySelectorAll('button').forEach(b => { if (!b.dataset.persist) b.disabled = disabled; });
}

/* ---------- Dashboard ---------- */
let dashFilter = '';

async function renderDashboard() {
  view.innerHTML = document.getElementById('tpl-dashboard').innerHTML;
  const rows = document.getElementById('rows');
  const empty = document.getElementById('empty');
  const count = document.getElementById('count');
  const summary = document.getElementById('summary');
  const banner = document.getElementById('failedBanner');
  const filterEl = document.getElementById('filter');
  filterEl.value = dashFilter;
  filterEl.addEventListener('input', () => { dashFilter = filterEl.value; applyFilter(); });

  async function load() {
    let services;
    try { services = await fetchJSON('/api/services'); }
    catch (e) {
      empty.querySelector('p').textContent = 'Error: ' + e.message;
      empty.classList.remove('hidden');
      rows.innerHTML = '';
      count.textContent = '';
      summary.textContent = '';
      return;
    }
    count.textContent = `(${services.length})`;
    const active = services.filter(s => s.status === 'active').length;
    const inactive = services.filter(s => s.status === 'inactive').length;
    const failed = services.filter(s => s.status === 'failed').length;
    summary.innerHTML = `<span><b class="active">${active}</b> active</span><span><b style="color:var(--yellow)">${inactive}</b> inactive</span><span><b style="color:var(--red)">${failed}</b> failed</span>`;
    const failedNames = services.filter(s => s.status === 'failed').map(s => s.name);
    if (failedNames.length) {
      banner.classList.remove('hidden');
      banner.innerHTML = `⚠ ${failedNames.length} failed: ${esc(failedNames.join(', '))}`;
    } else { banner.classList.add('hidden'); }

    rows.innerHTML = '';
    if (!services.length) { empty.classList.remove('hidden'); return; }
    empty.classList.add('hidden');

    const order = { failed: 0, inactive: 1, active: 2, unknown: 3 };
    services.sort((a, b) => (order[a.status] ?? 9) - (order[b.status] ?? 9) || a.name.localeCompare(b.name));

    for (const s of services) {
      const tr = document.createElement('tr');
      tr.dataset.name = s.name;
      tr.innerHTML = `
        <td class="row-name">${esc(s.name)}</td>
        <td>${badgeHtml(s.status)}</td>
        <td>${esc(s.pid)}</td>
        <td>${esc(s.memory)}</td>
        <td>${esc(s.restarts)}</td>
        <td>${esc(s.uptime)}</td>
        <td>${esc(s.enabled)}</td>
        <td class="col-actions">
          <div class="row-actions">
            <button class="btn small" data-quick="start" title="Start" ${s.status === 'active' ? 'disabled' : ''}>▶</button>
            <button class="btn small" data-quick="stop" title="Stop" ${s.status !== 'active' ? 'disabled' : ''}>■</button>
            <button class="btn small" data-quick="restart" title="Restart">↻</button>
            <button class="btn small" data-quick="view">view</button>
          </div>
        </td>`;
      tr.querySelector('[data-quick="view"]').addEventListener('click', () => setRoute('detail', s.name));
      tr.querySelector('.row-name').addEventListener('click', () => setRoute('detail', s.name));
      tr.querySelectorAll('[data-quick]').forEach(btn => {
        if (btn.dataset.quick === 'view') return;
        btn.addEventListener('click', async () => {
          const act = btn.dataset.quick;
          if (act === 'stop' && !confirm(`Stop ${s.name}?`)) return;
          btn.disabled = true;
          try {
            await svcAction(s.name, act);
            toast(`${s.name}: ${act} OK`, 'ok');
            setTimeout(load, 600);
          } catch (e) { toast(`${s.name}: ${e.message}`, 'err'); btn.disabled = false; }
        });
      });
      rows.appendChild(tr);
    }
    applyFilter();
  }

  function applyFilter() {
    const q = dashFilter.toLowerCase();
    rows.querySelectorAll('tr').forEach(tr => {
      tr.style.display = !q || tr.dataset.name.toLowerCase().includes(q) ? '' : 'none';
    });
  }

  view.querySelector('[data-goto="create"]')?.addEventListener('click', () => setRoute('create'));
  await load();
  pollTimer = setInterval(() => { if (currentRoute === 'dashboard') load(); }, 3000);
}

/* ---------- Create ---------- */
function renderCreate() {
  view.innerHTML = document.getElementById('tpl-create').innerHTML;
  const form = document.getElementById('createForm');
  const msg = document.getElementById('createMsg');
  const submit = document.getElementById('createSubmit');
  form.addEventListener('submit', async e => {
    e.preventDefault();
    const body = Object.fromEntries(new FormData(form));
    if (!body.name || !body.appDir) { msg.textContent = 'name and app directory are required'; msg.className = 'msg err'; return; }
    msg.textContent = 'installing…'; msg.className = 'msg';
    submit.disabled = true;
    try {
      await svcAction(null, null, { method: 'POST', body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' } });
      toast(`installed ${body.name}`, 'ok');
      setTimeout(() => setRoute('detail', body.name), 600);
    } catch (err) {
      msg.textContent = err.message; msg.className = 'msg err';
      submit.disabled = false;
    }
  });
}

/* ---------- Detail ---------- */
async function renderDetail(name) {
  view.innerHTML = document.getElementById('tpl-detail').innerHTML;
  const back = view.querySelector('.back'); back.addEventListener('click', e => { e.preventDefault(); setRoute('dashboard'); });
  document.getElementById('dname').textContent = name;

  let lastStatus = null;
  async function load() {
    try {
      const s = await fetchJSON('/api/services/' + encodeURIComponent(name));
      const stEl = document.getElementById('dstatus');
      stEl.textContent = s.status;
      stEl.className = 'badge ' + (['active','inactive','failed'].includes(s.status) ? s.status : 'unknown');
      const stChanged = lastStatus !== null && lastStatus !== s.status;
      lastStatus = s.status;
      const meta = document.getElementById('dmeta');
      meta.innerHTML = '';
      for (const [k, v] of [['Sub-state', s.subState], ['PID', s.pid], ['Memory', s.memory], ['Restarts', s.restarts], ['Uptime', s.uptime], ['Enabled', s.enabled]]) {
        const d = document.createElement('div');
        d.innerHTML = `<div class="k">${k}</div><div class="v">${esc(v)}</div>`;
        meta.appendChild(d);
      }
      const uf = document.getElementById('unitFile');
      uf.textContent = s.unitFile || '(unit file unavailable)';
      const toggle = document.getElementById('toggleUnit');
      toggle.onclick = () => { uf.classList.toggle('hidden'); toggle.textContent = uf.classList.contains('hidden') ? 'Unit file' : 'Hide'; };
      if (stChanged) toast(`${name} → ${s.status}`, s.status === 'failed' ? 'err' : 'ok');
    } catch (e) { document.getElementById('dmeta').innerHTML = `<div class="msg err">${esc(e.message)}</div>`; }
  }
  await load();
  pollTimer = setInterval(load, 4000);

  view.querySelectorAll('.detail-actions [data-act]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const act = btn.dataset.act;
      const actName = btn.dataset.actname;
      if (act === 'uninstall' && !confirm(`Uninstall ${name}? This stops and removes the service.`)) return;
      disableActions(view.querySelector('.detail-actions'), true);
      try {
        if (act === 'uninstall') {
          await svcAction(name, null, { method: 'DELETE' });
          toast(`uninstalled ${name}`, 'ok');
          setRoute('dashboard'); return;
        }
        await svcAction(name, act);
        toast(`${name}: ${actName} OK`, 'ok');
        setTimeout(load, 400);
      } catch (e) { toast(`${name}: ${e.message}`, 'err'); }
      disableActions(view.querySelector('.detail-actions'), false);
    });
  });

  /* Logs */
  const logBox = document.getElementById('logBox');
  const logCount = document.getElementById('logCount');
  const autoScroll = document.getElementById('autoScroll');
  const logFilter = document.getElementById('logFilter');
  document.getElementById('clearLogs').addEventListener('click', () => { logLines = []; renderLogs(); });

  function renderLogs() {
    const q = logFilter.value.toLowerCase();
    logBox.innerHTML = '';
    let shown = 0;
    for (let i = 0; i < logLines.length; i++) {
      const ln = document.createElement('span');
      ln.className = 'ln' + (logLines[i].error ? ' error' : '');
      ln.textContent = logLines[i].text;
      if (q && !logLines[i].text.toLowerCase().includes(q)) ln.classList.add('filtered');
      logBox.appendChild(ln);
      shown++;
    }
    logCount.textContent = `${shown} line${shown === 1 ? '' : 's'}`;
    if (autoScroll.checked) logBox.scrollTop = logBox.scrollHeight;
  }
  logFilter.addEventListener('input', renderLogs);

  try {
    const hist = await fetch('/api/services/' + encodeURIComponent(name) + '/logs/history?n=200').then(r => r.text());
    if (hist.trim()) { logLines = hist.split('\n').filter(l => l !== '').map(t => ({ text: t })); renderLogs(); }
  } catch {}

  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(`${proto}//${location.host}/api/services/${encodeURIComponent(name)}/logs/ws`);
  ws.onmessage = ev => {
    let data; try { data = JSON.parse(ev.data); } catch { return; }
    if (data.type === 'log' || data.type === 'error') {
      logLines.push({ text: data.line, error: data.type === 'error' });
      if (logLines.length > 2000) logLines.splice(0, logLines.length - 2000);
      renderLogs();
    }
  };
  ws.onclose = () => { if (currentRoute === 'detail') toast('log stream closed', 'warn'); };
}

setRoute('dashboard');