// Shared helpers: walk a copy, hash files, diff working against control.
// No dependencies; Node 20+.
import { createHash } from 'node:crypto';
import { readdir, readFile, stat } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('..', import.meta.url));
export const formatsDir = join(root, 'formats');
export const IGNORED = new Set(['node_modules', '.DS_Store', '.angular', '.svelte-kit', 'out-tsc']);

export async function listFiles(dir) {
  const out = [];
  async function walk(current) {
    let entries;
    try { entries = await readdir(current, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      if (IGNORED.has(entry.name)) continue;
      const path = join(current, entry.name);
      if (entry.isDirectory()) await walk(path);
      else if (entry.isFile()) out.push(relative(dir, path).split(sep).join('/'));
    }
  }
  await walk(dir);
  return out.sort();
}

export async function hashFile(path) {
  return createHash('sha256').update(await readFile(path)).digest('hex');
}

export async function hashTree(dir) {
  const result = {};
  for (const file of await listFiles(dir)) result[file] = await hashFile(join(dir, file));
  return result;
}

/** Working vs control for one format: changed, added (only in working), removed (only in control). */
export async function diffFormat(format) {
  const control = await hashTree(join(formatsDir, format, 'control'));
  const working = await hashTree(join(formatsDir, format, 'working'));
  const changed = [], added = [], removed = [];
  for (const [file, hash] of Object.entries(working)) {
    if (!(file in control)) added.push(file);
    else if (control[file] !== hash) changed.push(file);
  }
  for (const file of Object.keys(control)) if (!(file in working)) removed.push(file);
  return { format, changed, added, removed, identical: !changed.length && !added.length && !removed.length };
}

export async function formats() {
  const library = JSON.parse(await readFile(join(root, 'library.json'), 'utf8'));
  return library.formats.map((f) => f.id);
}

export async function newestMtime(dir, include) {
  let newest = 0, newestFile = null;
  for (const file of await listFiles(dir)) {
    if (!include(file)) continue;
    const { mtimeMs } = await stat(join(dir, file));
    if (mtimeMs > newest) { newest = mtimeMs; newestFile = file; }
  }
  return { mtime: newest, file: newestFile };
}
