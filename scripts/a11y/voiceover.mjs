import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { setTimeout as pause } from 'node:timers/promises';
import { existsSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';

// Real VoiceOver output, not an AX-tree simulation. Setup is read-only: never
// imports preference packs, writes TCC/VoiceOver defaults or touches the clipboard.
export async function voiceOverSmoke({ output, appPath, fixture, bundleID, interactive }) {
  const transcript = [], result = { name: 'native-real-voiceover', status: 'blocked' };
  const execute = promisify(execFile), abort = new AbortController();
  const interrupt = () => abort.abort();
  process.once('SIGINT', interrupt); process.once('SIGTERM', interrupt);
  const run = async (command, args, cleanup = false) => (await execute(command, args, { encoding: 'utf8', timeout: 15000, signal: cleanup ? undefined : abort.signal })).stdout.trim();
  const apple = (script, cleanup = false) => run('/usr/bin/osascript', ['-e', script], cleanup);
  const running = async name => { try { await run('/usr/bin/pgrep', ['-x', name]); return true; } catch { return false; } };
  let started = false, opened = false, previous, startedPid;
  try {
    if (process.platform !== 'darwin') throw Error('VoiceOver requires a macOS desktop.');
    if (!interactive) throw Error('Desktop interaction not requested. Run with --interactive when the Mac is free.');
    if (!appPath || !existsSync(appPath)) throw Error('The isolated native test app was not built.');
    if (!/^design\.tapps\.exp\.a11y-fixture\.[a-f0-9]{10}$/.test(bundleID || '')) throw Error('An isolated app identity is required.');
    if (await running('VoiceOver')) throw Error('VoiceOver is already in use; leave it running and rerun when it is free.');
    const enabledFile = '/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled';
    // Current macOS sets this system flag through VoiceOver Utility without
    // creating the older com.apple.VoiceOver4/default preference domain.
    // Actual AppleScript calls below establish whether access is usable.
    if (!existsSync(enabledFile)) throw Error('Enable “Allow VoiceOver to be controlled with AppleScript” in VoiceOver Utility → General, and allow Accessibility/Automation for the terminal running this command. No settings were changed.');
    previous = await apple('tell application "System Events" to get bundle identifier of first application process whose frontmost is true');
    await run('/usr/bin/open', ['-a', appPath, '--args', '-ApplePersistenceIgnoreState', 'YES', '-SUEnableAutomaticChecks', 'NO', '-SUAutomaticallyUpdate', 'NO']); opened = true;
    await run('/usr/bin/open', ['-a', appPath, fixture]);
    await apple(`tell application id ${JSON.stringify(bundleID)} to activate`);
    await run('/usr/bin/open', ['-a', '/System/Library/CoreServices/VoiceOver.app']); started = true;
    await pause(400);
    startedPid = await run('/usr/bin/pgrep', ['-x', 'VoiceOver']);
    // Commands and properties come from this Mac's VoiceOver.sdef dictionary.
    // Assert EXP-specific output, not merely that some desktop speech exists.
    await apple('tell application "VoiceOver" to tell vo cursor to move to first item');
    for (let index = 0; index < 45; index++) {
      await pause(100);
      const phrase = await apple('tell application "VoiceOver" to get content of last phrase');
      const item = await apple('tell application "VoiceOver" to get text under cursor of vo cursor');
      transcript.push({ index, phrase, item });
      if (/design canvas/i.test(phrase) && transcript.some(t => /zoom|select|rectangle/i.test(t.phrase))) break;
      await apple('tell application "VoiceOver" to tell vo cursor to move right');
    }
    const all = transcript.map(t => t.phrase).join('\n');
    if (!/design canvas/i.test(all) || !/zoom|rectangle|select/i.test(all)) {
      result.status = 'failed'; result.detail = 'VoiceOver did not reach both the named canvas and a core editor control within 45 moves. Inspect transcript; this is not waived.';
    } else { result.status = 'passed'; result.detail = 'Real VoiceOver traversed named editor controls and the canvas. This smoke does not verify canvas editing, rotor, announcement timing or all settings.'; }
  } catch (error) { result.status = started ? 'failed' : 'blocked'; result.detail = String(error.message) + (error.killed ? ` (command timed out or was interrupted; signal ${error.signal})` : ''); }
  finally {
    if (started) { try { await apple('tell application "VoiceOver" to quit', true); }
      catch { if (/^\d+$/.test(startedPid || '')) { try { await run('/bin/kill', ['-TERM', startedPid], true); } catch {} }
        result.status = 'failed'; result.detail += ' VoiceOver quit command failed; the process started by this smoke was terminated if its PID was known. Check VoiceOver state.'; } }
    if (opened) { try { await apple(`tell application id ${JSON.stringify(bundleID)} to quit`, true); } catch {} }
    if (previous && previous !== bundleID) { try { await apple(`tell application id ${JSON.stringify(previous)} to activate`, true); } catch {} }
    process.removeListener('SIGINT', interrupt); process.removeListener('SIGTERM', interrupt);
    await writeFile(path.join(output, 'voiceover-transcript.json'), JSON.stringify({ result, transcript }, null, 2));
  }
  return result;
}
