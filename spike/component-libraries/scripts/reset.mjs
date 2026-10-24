// Restore working copies from their controls (undo a round-trip test).
// Keeps working/node_modules so rebuilds stay fast.
//   node scripts/reset.mjs <format ...|--all>
import { cp, readdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { formats, formatsDir } from './tree.mjs';

const args = process.argv.slice(2);
if (!args.length) {
  console.error('Usage: node scripts/reset.mjs <format ...|--all>');
  process.exit(2);
}
const ids = args.includes('--all') ? await formats() : args;
const known = new Set(await formats());
for (const id of ids) {
  if (!known.has(id)) { console.error(`Unknown format: ${id}`); process.exit(2); }
  const working = join(formatsDir, id, 'working');
  for (const entry of await readdir(working).catch(() => [])) {
    if (entry !== 'node_modules') await rm(join(working, entry), { recursive: true, force: true });
  }
  await cp(join(formatsDir, id, 'control'), working, {
    recursive: true,
    filter: (src) => !src.includes('node_modules'),
  });
  console.log(`Reset ${id}/working from control.`);
}
