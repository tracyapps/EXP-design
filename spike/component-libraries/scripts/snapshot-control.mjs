// Records control-copy hashes in control.sha256.json. Run only when the
// fixtures themselves are deliberately changed (not after an EXP test).
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { formats, formatsDir, hashTree, root } from './tree.mjs';

const out = {};
for (const id of await formats()) out[id] = await hashTree(join(formatsDir, id, 'control'));
await writeFile(join(root, 'control.sha256.json'), JSON.stringify(out, null, 2) + '\n');
console.log(`Recorded ${Object.values(out).reduce((n, files) => n + Object.keys(files).length, 0)} control files.`);
