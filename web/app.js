'use strict';

const $ = (id) => document.getElementById(id);
let state = { jobs: [] };

/* ------------------------------------------------------------------ helpers */
function human(bytes) {
  if (!bytes && bytes !== 0) return '—';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0, n = Number(bytes);
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return `${n.toFixed(n < 10 && i > 0 ? 1 : 0)} ${u[i]}`;
}
function humanSpeed(bps) {
  if (!bps) return '';
  return `${human(bps)}/s`;
}
function humanEta(sec) {
  if (sec === null || sec === undefined) return '';
  if (sec < 60) return `${Math.round(sec)}s left`;
  if (sec < 3600) return `${Math.floor(sec / 60)}m ${Math.round(sec % 60)}s left`;
  return `${Math.floor(sec / 3600)}h ${Math.floor((sec % 3600) / 60)}m left`;
}
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}
let toastTimer = null;
function toast(msg, bad = false) {
  const el = $('toast');
  el.textContent = msg;
  el.classList.toggle('bad', bad);
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, bad ? 7000 : 3500);
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  let body = {};
  try { body = await res.json(); } catch (_) { /* empty */ }
  if (!res.ok || body.ok === false) {
    throw new Error(body.error || body.detail || `HTTP ${res.status}`);
  }
  return body;
}

/* ------------------------------------------------------------------- config */
async function loadConfig() {
  try {
    const cfg = await api('/api/config');
    const bits = [
      `extractor: ${cfg.extractor}`,
      `ffmpeg: ${cfg.has_ffmpeg ? 'yes' : 'no (.ts output)'}`,
      `saves to: ${cfg.download_dir}`,
    ];
    $('meta').textContent = bits.join('  ·  ');
  } catch (e) {
    $('meta').textContent = 'config unavailable';
  }
}

/* --------------------------------------------------------------------- paste */
$('paste-btn').addEventListener('click', async () => {
  try {
    const text = (await navigator.clipboard.readText()).trim();
    if (!text) { toast('Clipboard is empty', true); return; }
    $('url').value = text;
    toast('Pasted');
  } catch (_) {
    $('url').focus();
    toast('Long-press the box and tap Paste', true);
  }
});

/* ------------------------------------------------------------------ inspect */
$('inspect-form').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const url = $('url').value.trim();
  if (!url) return;
  const btn = $('inspect-btn');
  btn.disabled = true;
  btn.textContent = 'Inspecting…';
  $('inspect-hint').textContent = 'Reading the link…';
  try {
    const data = await api('/api/inspect', {
      method: 'POST',
      body: JSON.stringify({ url, quality: $('quality').value, refresh: true }),
    });
    renderResults(data, url);
    $('inspect-hint').textContent = `${data.items.length} item(s) found · strategy: ${data.strategy || 'n/a'}`;
  } catch (e) {
    toast(e.message, true);
    $('inspect-hint').textContent = 'Could not resolve that link — try the diagnostics dump below.';
  } finally {
    btn.disabled = false;
    btn.textContent = 'Inspect';
  }
});

function renderResults(data, url) {
  const box = $('results');
  if (!data.items.length) {
    box.innerHTML = '<p class="hint">No files found.</p>';
    $('results-card').hidden = false;
    return;
  }
  box.innerHTML = data.items.map((it, i) => `
    <div class="item">
      ${it.thumb
        ? `<img src="${esc(it.thumb)}" alt="" referrerpolicy="no-referrer" loading="lazy" />`
        : '<div class="ph"></div>'}
      <div class="info">
        <div class="name">${esc(it.name)}</div>
        <div class="sub">
          ${it.is_video ? '<span class="badge vid">video</span>' : ''}
          ${it.has_stream ? '<span class="badge">HLS</span>' : ''}
          ${it.has_direct ? '<span class="badge">direct</span>' : ''}
          ${it.size ? ` · ${human(it.size)}` : ''}
        </div>
      </div>
      <button class="small" data-dl="${i}">Download</button>
    </div>
  `).join('');
  $('results-card').hidden = false;

  box.querySelectorAll('[data-dl]').forEach((btn) => {
    btn.addEventListener('click', () => startDownload(url, Number(btn.dataset.dl)));
  });
}

async function startDownload(url, index) {
  try {
    await api('/api/download', {
      method: 'POST',
      body: JSON.stringify({ url, item_index: index, quality: $('quality').value }),
    });
    toast('Download started');
    $('jobs-card').hidden = false;
  } catch (e) {
    toast(e.message, true);
  }
}

/* --------------------------------------------------------------------- jobs */
function renderJobs() {
  const box = $('jobs');
  if (!state.jobs.length) {
    $('jobs-card').hidden = true;
    return;
  }
  $('jobs-card').hidden = false;
  box.innerHTML = state.jobs.map((j) => {
    const pct = j.percent ?? 0;
    const active = ['downloading', 'inspecting', 'merging', 'queued'].includes(j.status);
    const stats = [];
    if (j.size) stats.push(`${human(j.done)} / ${human(j.size)}`);
    if (active && j.speed) stats.push(humanSpeed(j.speed));
    if (active && j.eta) stats.push(humanEta(j.eta));
    return `
      <div class="job ${j.status}">
        <div class="head">
          <div class="name">${esc(j.name || j.url)}</div>
          <div class="status ${j.status}">${esc(j.status)}</div>
        </div>
        <div class="stats">${stats.join(' · ') || esc(j.url)}</div>
        <div class="bar"><div style="width:${pct}%"></div></div>
        ${j.error ? `<div class="err-text">${esc(j.error)}</div>` : ''}
        <div class="actions">
          ${j.status === 'done'
            ? `<a href="/api/jobs/${j.id}/file" download><button class="small">Save to device</button></a>` : ''}
          ${active ? `<button class="small ghost" data-cancel="${j.id}">Cancel</button>` : ''}
          <button class="small ghost" data-remove="${j.id}">${j.status === 'done' ? 'Clear' : 'Remove'}</button>
        </div>
      </div>
    `;
  }).join('');

  box.querySelectorAll('[data-cancel]').forEach((b) =>
    b.addEventListener('click', () => api(`/api/jobs/${b.dataset.cancel}/cancel`, { method: 'POST' }).catch((e) => toast(e.message, true)))
  );
  box.querySelectorAll('[data-remove]').forEach((b) =>
    b.addEventListener('click', () => api(`/api/jobs/${b.dataset.remove}`, { method: 'DELETE' })
      .then(() => { state.jobs = state.jobs.filter((j) => j.id !== b.dataset.remove); renderJobs(); })
      .catch((e) => toast(e.message, true)))
  );
}

function connectStream() {
  const es = new EventSource('/api/events');
  es.onmessage = (ev) => {
    try {
      state.jobs = JSON.parse(ev.data).jobs;
      renderJobs();
    } catch (_) { /* ignore malformed frame */ }
  };
  es.onerror = () => { /* EventSource reconnects on its own */ };
}

/* -------------------------------------------------------------- diagnostics */
$('diag-btn').addEventListener('click', async () => {
  const url = $('url').value.trim();
  if (!url) { toast('Paste a link first', true); return; }
  $('diag-btn').disabled = true;
  $('diag').hidden = false;
  $('diag').textContent = 'Fetching…';
  try {
    const data = await api('/api/diagnose', { method: 'POST', body: JSON.stringify({ url }) });
    const text = JSON.stringify(data.dump, null, 2);
    $('diag').textContent = text;
    $('copy-btn').hidden = false;
  } catch (e) {
    $('diag').textContent = `Error: ${e.message}`;
  } finally {
    $('diag-btn').disabled = false;
  }
});

$('copy-btn').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText($('diag').textContent);
    toast('Copied');
  } catch (_) {
    toast('Copy failed — select the text manually', true);
  }
});

/* --------------------------------------------------------------------- boot */
loadConfig();
connectStream();
(async () => {
  try {
    const d = await api('/api/jobs');
    state.jobs = d.jobs;
    renderJobs();
  } catch (_) { /* no jobs yet */ }
})();
