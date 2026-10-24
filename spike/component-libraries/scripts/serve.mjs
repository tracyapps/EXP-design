// Local server for the comparison page. No dependencies.
//   node scripts/serve.mjs [--port 4173]
// Serves this folder on 127.0.0.1 only, plus three read-only JSON endpoints the
// page uses: /__diff (working vs control per format), /__staleness (is a
// working build older than its source?) and /__control (control integrity).
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize, sep } from 'node:path';
import { diffFormat, formats, formatsDir, hashTree, newestMtime, root } from './tree.mjs';

const port = Number(process.argv[process.argv.indexOf('--port') + 1]) || 4173;
const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml',
  '.txt': 'text/plain; charset=utf-8', '.md': 'text/plain; charset=utf-8',
};
// Source files are shown as text in the page.
const text = new Set(['.ts', '.tsx', '.jsx', '.vue', '.svelte']);

async function json(res, value) {
  res.writeHead(200, { 'content-type': types['.json'], 'cache-control': 'no-store' });
  res.end(JSON.stringify(value));
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (url.pathname === '/__diff') return json(res, await Promise.all((await formats()).map(diffFormat)));
    if (url.pathname === '/__staleness') {
      const library = JSON.parse(await readFile(join(root, 'library.json'), 'utf8'));
      const out = {};
      for (const f of library.formats) {
        if (f.build === 'none' || !f.entry) continue;
        const dir = join(formatsDir, f.id, 'working');
        const source = await newestMtime(dir, (file) => file.startsWith('src/'));
        const build = await newestMtime(dir, (file) => file === f.entry);
        out[f.id] = { stale: source.mtime > build.mtime + 1000, newestSource: source.file, build: f.entry };
      }
      return json(res, out);
    }
    if (url.pathname === '/__control') {
      const expected = JSON.parse(await readFile(join(root, 'control.sha256.json'), 'utf8'));
      const problems = [];
      for (const [format, files] of Object.entries(expected)) {
        const actual = await hashTree(join(formatsDir, format, 'control'));
        for (const [file, hash] of Object.entries(files)) if (actual[file] !== hash) problems.push(`${format}/${file}`);
        for (const file of Object.keys(actual)) if (!(file in files)) problems.push(`${format}/${file} (added)`);
      }
      return json(res, { intact: problems.length === 0, problems });
    }

    let path = decodeURIComponent(url.pathname);
    if (path.endsWith('/')) path += 'compare.html';
    const file = normalize(join(root, path));
    if (!file.startsWith(root.endsWith(sep) ? root : root + sep) || file.includes(`${sep}node_modules${sep}`)) {
      res.writeHead(403).end('Forbidden');
      return;
    }
    const info = await stat(file).catch(() => null);
    if (!info?.isFile()) { res.writeHead(404, { 'content-type': 'text/plain' }).end('Not found'); return; }
    const ext = extname(file);
    res.writeHead(200, {
      'content-type': types[ext] ?? (text.has(ext) ? 'text/plain; charset=utf-8' : 'application/octet-stream'),
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    });
    res.end(await readFile(file));
  } catch (error) {
    res.writeHead(500, { 'content-type': 'text/plain' }).end(String(error?.stack ?? error));
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Component comparison: http://127.0.0.1:${port}/`);
  console.log('Ctrl+C to stop.');
});
