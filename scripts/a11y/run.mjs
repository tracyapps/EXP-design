import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { nativeChecks, command } from './native.mjs';
import { voiceOverSmoke } from './voiceover.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const args = new Set(process.argv.slice(2));
if ([...args].some(arg => !['--interactive', '--web-only', '--native-only'].includes(arg)) || (args.has('--web-only') && args.has('--native-only'))) {
  console.error('Usage: npm run test:a11y -- [--interactive] [--web-only | --native-only]'); process.exit(64);
}
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const output = path.join(root, 'output/a11y', stamp);
await mkdir(output, { recursive: true });
const results = [];
const manual = [
  'Human judgment: understandable announcements, useful navigation and task completion with an experienced screen-reader user.',
  'Native: selected layer/Inspector edits, export/reopen, complex/nested canvas content and Sanaa reader journeys beyond the initial editor smoke.',
  'Actual Safari + VoiceOver, rotor, Quick Nav, verbosity/speech-language variants and braille.',
  'Website homepage/download/learn/ARIA guide and expanded header-menu keyboard/escape flows beyond the first account/Pro/support matrix.',
  'macOS Full Keyboard Access on/off, Increase Contrast, Reduce Transparency/Motion, Large interface type and real 1x/2x displays.',
  'Real inbox/provider/hosted account lifecycle. The web suite uses real local PostgreSQL with captured mail and isolates all external browser requests.'
];
let native;
console.log(`Accessibility evidence: ${output}`);
try {
  if (!args.has('--native-only')) {
    console.log('Building and checking website keyboard journeys + axe…');
    await mkdir(path.join(output, 'web'), { recursive: true });
    const build = await command('npm', ['--prefix', 'website', 'run', 'build'], path.join(output, 'web/build.log'), { cwd: root });
    results.push({ name: 'web-build', status: build.code === 0 ? 'passed' : 'failed' });
    if (build.code === 0) {
      const run = await command('bash', ['scripts/a11y/web.sh'], path.join(output, 'web/runtime.log'), { cwd: root,
        env: { ...process.env, EXP_A11Y_OUTPUT: path.join(output, 'web') } });
      try { const web = JSON.parse(await readFile(path.join(output, 'web/web.json'), 'utf8')); if (!Array.isArray(web.results) || !web.results.length) throw Error('No web cases recorded'); results.push(...web.results); }
      catch { results.push({ name: 'web-runtime', status: 'failed', detail: `No valid result ledger (exit ${run.code}); inspect web/runtime.log.` }); }
      if (run.code === 1 && !results.some(r => r.status === 'failed')) results.push({ name: 'web-process', status: 'failed', detail: 'Web process failed without a recorded failing case.' });
    }
  }
  if (!args.has('--web-only')) {
    console.log('Building isolated native UI tests…');
    native = await nativeChecks({ root, output, interactive: args.has('--interactive') });
    results.push(...native.results);
    console.log('Checking real VoiceOver readiness/smoke…');
    results.push(await voiceOverSmoke({ output, appPath: native.appPath, bundleID: native.bundleID,
      fixture: path.join(native.fixtureDir || output, 'Keyboard Fixture.design'), interactive: args.has('--interactive') }));
  }
} catch (error) { results.push({ name: 'harness', status: 'failed', detail: error.message }); }
finally {
  const failed = results.filter(r => r.status === 'failed'), blocked = results.filter(r => r.status === 'blocked');
  const review = results.filter(r => r.status === 'needs-review');
  const uniqueReview = new Map();
  for (const item of review) for (const finding of item.reviewItems || []) {
    const key = JSON.stringify([finding.rule, finding.target]);
    const previous = uniqueReview.get(key) || { ...finding, cases: [] };
    previous.cases.push(item.name); uniqueReview.set(key, previous);
  }
  await writeFile(path.join(output, 'review.json'), JSON.stringify([...uniqueReview.values()], null, 2));
  const status = failed.length ? 'FAILED' : blocked.length ? 'BLOCKED / PARTIAL' : 'SELECTED AUTOMATED CHECKS PASSED';
  const report = { generatedAt: new Date().toISOString(), status, node: process.version, platform: `${process.platform}/${process.arch}`,
    selected: args.has('--web-only') ? ['web'] : args.has('--native-only') ? ['native', 'VoiceOver'] : ['web', 'native', 'VoiceOver'], results, manual };
  await writeFile(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
  const escape = value => String(value || '').replaceAll('|', '\\|').replaceAll('\n', '<br>');
  const markdown = `# EXP accessibility verification\n\n**${status}** · ${report.generatedAt}\n\nSelected layers: ${report.selected.join(', ')}. No result here certifies complete WCAG/AT usability.\n\n` +
    '| Check | Result | Detail |\n| --- | --- | --- |\n' + results.map(r => `| ${escape(r.name)} | ${r.status} | ${escape(r.detail)} |`).join('\n') +
    `\n\n## Evidence\n\nWeb screenshots, ARIA-tree captures and full axe JSON are in \`web/\`. ${review.length} incomplete scan results contain ${uniqueReview.size} distinct rule/selector findings, deduplicated with their affected cases in \`review.json\`; these are not contrast passes. Native build/runtime logs, \`summary.json\`, indexed \`findings.md\`/\`findings.json\`, cropped window attachments and \`results.xcresult\` are in \`native/\`. Real VoiceOver output or its exact setup gap is in \`voiceover-transcript.json\`. Missing/skipped/unexecuted checks are never counted as passes.\n\n## Still needs review\n\n` + manual.map(item => `- [ ] ${item}`).join('\n') +
    '\n\n## Repeat\n\n`npm run test:a11y -- --interactive` runs desktop checks when the Mac is free. Omit `--interactive` for web checks + native build/preparation only. `--web-only` selects only the headless web layer. Exit codes: 0 selected automated layers passed; 1 failure; 2 blocked coverage; 64 bad invocation. Human review stays separate even after exit 0.\n';
  await writeFile(path.join(output, 'report.md'), markdown);
  await writeFile(path.join(root, 'output/a11y/latest.json'), JSON.stringify({ output, status }, null, 2));
  console.log(`${status}: ${results.filter(r => r.status === 'passed').length} passed; ${failed.length} failed; ${blocked.length} blocked; ${review.length} need review.\nReport: ${path.join(output, 'report.md')}`);
  process.exitCode = failed.length ? 1 : blocked.length ? 2 : 0;
}
