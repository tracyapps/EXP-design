// Rebuild working copies after EXP changes source files (markup/logic).
// CSS and token edits show without a rebuild: styles are plain files.
//   node scripts/rebuild.mjs [format ...]   (default: every format with a build)
// Installs dependencies with `npm ci` on first use. Angular needs Node 22.22.3+ or 24.15+.
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { formatsDir, root } from './tree.mjs';

const library = JSON.parse(readFileSync(join(root, 'library.json'), 'utf8'));
const selected = process.argv.slice(2);
const targets = library.formats.filter((f) => f.build !== 'none' && (!selected.length || selected.includes(f.id)));
let failed = false;
for (const f of targets) {
  const cwd = join(formatsDir, f.id, 'working');
  const run = (cmd, args) => spawnSync(cmd, args, { cwd, stdio: 'inherit', shell: process.platform === 'win32' });
  console.log(`\n▸ ${f.id}`);
  if (!existsSync(join(cwd, 'node_modules')) && run('npm', ['ci', '--no-audit', '--no-fund']).status !== 0) { failed = true; continue; }
  if (run('npm', ['run', 'build']).status !== 0) failed = true;
}
process.exit(failed ? 1 : 0);
