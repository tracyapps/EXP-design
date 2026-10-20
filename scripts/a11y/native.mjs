import { spawn } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

export function command(executable, args, log, options = {}) {
  return new Promise(resolve => {
    const stream = createWriteStream(log);
    const child = spawn(executable, args, { ...options, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.pipe(stream); child.stderr.pipe(stream);
    const timeout = setTimeout(() => child.kill('SIGTERM'), options.timeout || 15 * 60 * 1000);
    child.on('error', error => { stream.write(error.message); });
    child.on('close', (code, signal) => { clearTimeout(timeout); stream.end(() => resolve({ code: code ?? 1, signal })); });
  });
}

export async function nativeChecks({ root, output, interactive }) {
  const results = [], directory = path.join(output, 'native');
  await mkdir(directory, { recursive: true });
  if (process.platform !== 'darwin') return { results: [{ name: 'native-build', status: 'blocked', detail: 'Xcode and macOS required.' }] };
  const contrast = await command('node', ['--test', 'scripts/a11y/chrome-contrast.test.mjs', 'scripts/a11y/voiceover.test.mjs'],
    path.join(directory, 'chrome-contrast.log'), { cwd: root });
  results.push({ name: 'native-chrome-contrast', status: contrast.code === 0 ? 'passed' : 'failed',
    detail: 'Small-text color compositing across both appearances and bounded wallpaper extremes; real screenshots/AT remain separate.' });
  const derived = '/tmp/exp-a11y-derived';
  const destination = `platform=macOS,arch=${process.arch === 'arm64' ? 'arm64' : 'x86_64'}`;
  const build = await command('xcodebuild', ['-project', 'EXP [design].xcodeproj', '-scheme', 'EXP Accessibility', '-configuration', 'Debug',
    '-destination', destination, '-derivedDataPath', derived, 'build-for-testing', 'CODE_SIGNING_ALLOWED=NO'], path.join(directory, 'build.log'), { cwd: root });
  results.push({ name: 'native-build', status: build.code === 0 ? 'passed' : 'failed', detail: 'See native/build.log; shipping scheme and bundle identity are unchanged.' });
  if (build.code !== 0) return { results };
  const appPath = path.join(directory, 'EXP Accessibility Fixture.app'), fixtureDir = path.join(directory, 'documents');
  await mkdir(fixtureDir, { recursive: true });
  const prepare = await command('python3', ['scripts/a11y/prepare_native.py', derived, appPath, fixtureDir, path.join(directory, 'fixture.xctestrun')], path.join(directory, 'prepare.log'), { cwd: root });
  if (prepare.code !== 0) { results.push({ name: 'native-isolation', status: 'failed', detail: 'Could not prepare the isolated test app.' }); return { results }; }
  results.push({ name: 'native-isolation', status: 'passed', detail: 'Disposable ad-hoc app identity; test-only local fixtures and network-disabled sandbox.' });
  const { bundleID } = JSON.parse(await readFile(path.join(directory, 'identity.json'), 'utf8'));
  if (!interactive) { results.push({ name: 'native-runtime', status: 'blocked', detail: 'Run with --interactive when the desktop is free; build alone is not UI/AT proof.' }); return { results, appPath, fixtureDir, bundleID }; }
  const run = await command('xcodebuild', ['test-without-building', '-xctestrun', path.join(directory, 'fixture.xctestrun'), '-destination', destination,
    '-parallel-testing-enabled', 'NO', '-resultBundlePath', path.join(directory, 'results.xcresult')], path.join(directory, 'runtime.log'), { cwd: root });
  const summaryFile = path.join(directory, 'summary.json');
  const parsed = await command('xcrun', ['xcresulttool', 'get', 'test-results', 'summary', '--path', path.join(directory, 'results.xcresult'), '--format', 'json'], summaryFile, { cwd: root, timeout: 30000 });
  let summary;
  if (parsed.code === 0) { try { summary = JSON.parse(await readFile(summaryFile, 'utf8')); } catch {} }
  // A successful xcodebuild with skipped tests must not appear as full coverage.
  const skipped = summary?.skippedTests || 0;
  results.push({ name: 'native-runtime', status: run.code !== 0 ? 'failed' : skipped ? 'blocked' : 'passed',
    detail: summary ? `${summary.passedTests || 0} passed, ${summary.failedTests || 0} failed, ${skipped} skipped. See xcresult/summary.` : 'See native/runtime.log; runtime result summary unavailable.' });
  if (!summary && run.code === 0) results.at(-1).status = 'blocked';
  for (const failure of new Set((summary?.testFailures || []).map(failure => `${failure.testName || failure.targetName}: ${failure.failureText}`))) results.at(-1).detail += `\n${failure}`;
  if (skipped) {
    const log = await readFile(path.join(directory, 'runtime.log'), 'utf8');
    results.push({ name: 'native-skipped-checks', status: 'blocked', detail: log.split('\n').filter(line => line.includes('Test skipped')).join('\n') || `${skipped} checks skipped; inspect runtime.log.` });
  }
  await command('xcrun', ['xcresulttool', 'export', 'attachments', '--path', path.join(directory, 'results.xcresult'),
    '--output-path', path.join(directory, 'attachments')], path.join(directory, 'attachments.log'), { cwd: root, timeout: 30000 });
  try {
    const manifest = JSON.parse(await readFile(path.join(directory, 'attachments/manifest.json'), 'utf8'));
    const findings = [];
    for (const test of manifest) for (const attachment of test.attachments) {
      if (!attachment.suggestedHumanReadableName.startsWith('Accessibility audit finding')) continue;
      const lines = (await readFile(path.join(directory, 'attachments', attachment.exportedFileName), 'utf8')).split('\n');
      findings.push({ test: test.testIdentifier, summary: lines[0], detail: lines[1],
        element: lines.find(line => line.startsWith('Attributes:')) || 'No element returned', evidence: attachment.exportedFileName });
    }
    await writeFile(path.join(directory, 'findings.json'), JSON.stringify(findings, null, 2));
    const escape = value => String(value).replaceAll('|', '\\|').replaceAll('\n', ' ');
    await writeFile(path.join(directory, 'findings.md'), '# Native audit findings\n\nAutomated findings need triage; none is suppressed or automatically certified as a WCAG failure. Full element subtrees are linked below.\n\n| Finding | Element | Evidence |\n| --- | --- | --- |\n' +
      findings.map(f => `| ${escape(f.summary)} | ${escape(f.element)} | [subtree](attachments/${f.evidence}) |`).join('\n') + '\n');
  } catch (error) { results.push({ name: 'native-findings-export', status: 'blocked', detail: `Could not index native findings: ${error.message}` }); }
  await writeFile(path.join(directory, 'native.json'), JSON.stringify({ results, summary }, null, 2));
  return { results, appPath, fixtureDir, bundleID };
}
