// Comparison page: working copy vs control for one format + component,
// rendered live (isolated iframes) with source and a line diff underneath.
const $ = (id) => document.getElementById(id);
const controls = { format: $('format'), component: $('component'), theme: $('theme'), watch: $('watch') };
let library;
let lastDiffJSON = '';
let watchTimer;

// ---------- state in the URL hash (bookmarkable) ----------
function readHash() {
  const hash = new URLSearchParams(location.hash.slice(1));
  return { format: hash.get('format'), component: hash.get('component'), theme: hash.get('theme') };
}
function writeHash() {
  const hash = new URLSearchParams({ format: controls.format.value, component: controls.component.value, theme: controls.theme.value });
  history.replaceState(null, '', `#${hash}`);
}

// ---------- line diff (LCS) ----------
function diffLines(a, b) {
  const n = a.length, m = b.length;
  const dp = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--)
    dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  const inA = new Uint8Array(n), inB = new Uint8Array(m);   // 1 = kept (common)
  let i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) { inA[i++] = 1; inB[j++] = 1; }
    else if (dp[i + 1][j] >= dp[i][j + 1]) i++;
    else j++;
  }
  return { inA, inB };
}

const splitLines = (text) => (text.endsWith('\n') ? text.slice(0, -1) : text).split('\n');

function codeBlock(lines, kept, kind) {
  const pre = document.createElement('pre');
  pre.className = 'code';
  pre.tabIndex = 0;   // scrollable region must be keyboard reachable
  const code = document.createElement('code');
  lines.forEach((text, index) => {
    const changed = kept && !kept[index];
    const row = document.createElement('span');
    row.className = `line${changed ? ` line--${kind}` : ''}`;
    const ln = document.createElement('span');
    ln.className = 'ln';
    ln.textContent = index + 1;
    ln.setAttribute('aria-hidden', 'true');
    const mark = document.createElement('span');
    mark.className = 'm';
    if (changed) {
      mark.textContent = kind === 'add' ? '+' : '−';
      mark.setAttribute('aria-hidden', 'true');
      const sr = document.createElement('span');
      sr.className = 'visually-hidden';
      sr.textContent = kind === 'add' ? 'Only in working copy: ' : 'Only in control: ';
      row.append(ln, mark, sr);
    } else {
      row.append(ln, mark);
    }
    const t = document.createElement('span');
    t.className = 't';
    t.textContent = text || ' ';
    row.append(t, '\n');
    code.append(row);
  });
  pre.append(code);
  return pre;
}

function badge(text, kind) {
  const span = document.createElement('span');
  span.className = `badge badge--${kind}`;
  span.textContent = text;
  return span;
}

async function fetchText(url) {
  const response = await fetch(url, { cache: 'no-store' });
  return response.ok ? response.text() : null;
}

// ---------- source panes ----------
async function renderFiles(format, component) {
  const paths = format.files[component.id] ?? [];
  const working = $('files-working'), control = $('files-control');
  const open = new Set([...document.querySelectorAll('details.file[open]')].map((d) => d.dataset.path));
  const first = !document.querySelector('details.file');
  working.replaceChildren(); control.replaceChildren();
  let differing = 0;
  for (const path of paths) {
    const [w, c] = await Promise.all([
      fetchText(`formats/${format.id}/working/${path}`),
      fetchText(`formats/${format.id}/control/${path}`),
    ]);
    const wl = w === null ? null : splitLines(w), cl = c === null ? null : splitLines(c);
    let status, kind, keptW = null, keptC = null;
    if (wl === null || cl === null) {
      status = wl === null ? 'missing from working copy' : 'missing from control'; kind = 'diff';
    } else if (w === c) {
      status = 'identical'; kind = 'ok';
    } else {
      const { inA, inB } = diffLines(wl, cl);
      keptW = inA; keptC = inB;
      const added = inA.filter((v) => !v).length, removed = inB.filter((v) => !v).length;
      status = `differs: ${added} line${added === 1 ? '' : 's'} added, ${removed} removed`; kind = 'diff';
    }
    if (kind !== 'ok') differing++;
    for (const [pane, lines, kept, mark] of [[working, wl, keptW, 'add'], [control, cl, keptC, 'del']]) {
      const details = document.createElement('details');
      details.className = 'file';
      details.dataset.path = path;
      details.open = first ? kind !== 'ok' || path === paths[0] : open.has(path);
      const summary = document.createElement('summary');
      const label = document.createElement('code');
      label.textContent = path;
      summary.append(label, badge(status, kind));
      details.append(summary);
      if (lines === null) {
        const p = document.createElement('p');
        p.className = 'missing';
        p.textContent = 'This file does not exist in this copy.';
        details.append(p);
      } else {
        details.append(codeBlock(lines, kept, mark));
      }
      // Opening a file in one column opens it in the other, so they stay aligned.
      details.addEventListener('toggle', () => {
        const twin = (pane === working ? control : working).querySelector(`details[data-path="${CSS.escape(path)}"]`);
        if (twin && twin.open !== details.open) twin.open = details.open;
      });
      pane.append(details);
    }
  }
  return differing;
}

// ---------- previews ----------
function loadFrames(format, component) {
  for (const copy of ['working', 'control']) {
    const frame = $(`frame-${copy}`);
    const query = new URLSearchParams({ format: format.id, copy, component: component.id, theme: controls.theme.value, frame: copy });
    frame.title = `${library.copies.find((c) => c.id === copy).title}: ${format.title} ${component.title}`;
    frame.src = `preview.html?${query}`;
  }
}

window.addEventListener('message', (event) => {
  if (event.origin !== location.origin || event.data?.source !== 'exp-preview') return;
  const frame = $(`frame-${event.data.frame}`);
  if (!frame) return;
  if (event.data.type === 'size') frame.style.blockSize = `${Math.min(1200, Math.max(120, event.data.height))}px`;
});

// ---------- status + overview ----------
async function getJSON(url) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return response.json();
}

function fileList(files) {
  if (!files.length) return document.createTextNode('—');
  const ul = document.createElement('ul');
  for (const f of files) {
    const li = document.createElement('li');
    const code = document.createElement('code');
    code.textContent = f;
    li.append(code);
    ul.append(li);
  }
  return ul;
}

async function renderOverview() {
  const [diff, stale] = await Promise.all([getJSON('__diff'), getJSON('__staleness')]);
  lastDiffJSON = JSON.stringify(diff);
  const body = $('overview');
  body.replaceChildren();
  for (const row of diff) {
    const format = library.formats.find((f) => f.id === row.format);
    const tr = document.createElement('tr');
    const name = document.createElement('th');
    name.scope = 'row';
    name.textContent = format?.title ?? row.format;
    const result = document.createElement('td');
    result.append(row.identical ? badge('Matches control', 'ok') : badge('Differs', 'diff'));
    const build = document.createElement('td');
    const s = stale[row.format];
    if (!s) build.textContent = 'No build step';
    else if (s.stale) build.append(badge('Rebuild needed', 'warn'), document.createTextNode(` ${s.newestSource} is newer than ${s.build}`));
    else build.textContent = 'Up to date';
    const cells = [row.changed, row.added, row.removed].map((files) => {
      const td = document.createElement('td');
      td.append(fileList(files));
      return td;
    });
    tr.append(name, result, ...cells, build);
    body.append(tr);
  }
  const integrity = await getJSON('__control');
  const p = $('control-integrity');
  p.replaceChildren(integrity.intact
    ? badge('Control copies intact', 'ok')
    : badge(`Control copies changed: ${integrity.problems.join(', ')}`, 'diff'));
  return { diff, stale };
}

async function render() {
  const format = library.formats.find((f) => f.id === controls.format.value);
  const component = library.components.find((c) => c.id === controls.component.value);
  writeHash();

  const info = $('format-info');
  info.replaceChildren();
  for (const [label, value] of [['Format', `${format.title}: ${format.summary}`], ['Component', `${component.title} (${component.complexity.toLowerCase()}): ${component.detail}`], ['EXP import', format.expImport], ['Build', format.build === 'none' ? 'None, runs as written' : `${format.build} in formats/${format.id}/working`]]) {
    const span = document.createElement('span');
    const strong = document.createElement('strong');
    strong.textContent = `${label}: `;
    span.append(strong, value);
    info.append(span);
  }

  loadFrames(format, component);
  const status = $('status');
  status.textContent = 'Comparing…';
  try {
    const [differing, { diff, stale }] = await Promise.all([renderFiles(format, component), renderOverview()]);
    const row = diff.find((r) => r.format === format.id);
    status.replaceChildren(
      differing === 0 ? badge(`${component.title} source matches control`, 'ok') : badge(`${differing} ${component.title} file${differing === 1 ? '' : 's'} differ`, 'diff'),
      row.identical ? badge(`All ${format.title} files match`, 'ok') : badge(`${row.changed.length + row.added.length + row.removed.length} ${format.title} files differ overall`, 'diff'),
    );
    if (stale[format.id]?.stale) status.append(badge('Working build is older than its source: rebuild to see markup changes', 'warn'));
  } catch (error) {
    status.replaceChildren(badge(`Run "npm run serve" in this folder and open the address it prints (${error.message})`, 'warn'));
  }
}

function setWatch(on) {
  clearInterval(watchTimer);
  if (!on) return;
  watchTimer = setInterval(async () => {
    try {
      const diff = JSON.stringify(await getJSON('__diff'));
      if (diff !== lastDiffJSON) render();
    } catch { /* server stopped; keep the last view */ }
  }, 2000);
}

async function init() {
  library = await getJSON('library.json');
  for (const f of library.formats) controls.format.append(new Option(f.title, f.id));
  for (const c of library.components) controls.component.append(new Option(`${c.title} (${c.complexity.toLowerCase()})`, c.id));
  const hash = readHash();
  if (library.formats.some((f) => f.id === hash.format)) controls.format.value = hash.format;
  if (library.components.some((c) => c.id === hash.component)) controls.component.value = hash.component;
  if (['system', 'light', 'dark'].includes(hash.theme)) controls.theme.value = hash.theme;
  for (const el of [controls.format, controls.component, controls.theme]) el.addEventListener('change', render);
  controls.watch.addEventListener('change', () => setWatch(controls.watch.checked));
  $('refresh').addEventListener('click', render);
  render();
}

init().catch((error) => {
  $('status').replaceChildren(badge(`Couldn't load library.json. Run "npm run serve" here first. (${error.message})`, 'warn'));
});
