// Command-line round-trip check: lists every file that differs between each
// format's working copy and its control, and confirms the control copies are
// untouched. Exit code 1 if anything differs.
//   node scripts/verify.mjs [format ...] [--json]
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { diffFormat, formats, formatsDir, hashTree, root } from './tree.mjs';

const args = process.argv.slice(2);
const asJSON = args.includes('--json');
const selected = args.filter((a) => !a.startsWith('--'));
const ids = selected.length ? selected : await formats();

const results = await Promise.all(ids.map(diffFormat));
const expected = JSON.parse(await readFile(join(root, 'control.sha256.json'), 'utf8'));
const controlProblems = [];
for (const id of ids) {
  const actual = await hashTree(join(formatsDir, id, 'control'));
  for (const [file, hash] of Object.entries(expected[id] ?? {})) if (actual[file] !== hash) controlProblems.push(`${id}/${file}`);
  for (const file of Object.keys(actual)) if (!(file in (expected[id] ?? {}))) controlProblems.push(`${id}/${file} (added)`);
}

if (asJSON) {
  console.log(JSON.stringify({ results, controlProblems }, null, 2));
} else {
  for (const r of results) {
    if (r.identical) { console.log(`= ${r.format}: working matches control`); continue; }
    console.log(`≠ ${r.format}:`);
    for (const f of r.changed) console.log(`    changed  ${f}`);
    for (const f of r.added) console.log(`    added    ${f}`);
    for (const f of r.removed) console.log(`    REMOVED  ${f}`);
  }
  console.log(controlProblems.length ? `\nControl copies were modified:\n  ${controlProblems.join('\n  ')}` : '\nControl copies intact.');
}
process.exit(results.every((r) => r.identical) && !controlProblems.length ? 0 : 1);
