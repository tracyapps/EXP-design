import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { setTimeout as pause } from 'node:timers/promises';
import { existsSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';

// Require an actual core-control name and role. “Properties selected button”
// and instructional text containing “Select layers” are not the Select tool.
export function hasCoreEditorControl(phrase) {
  return /\b(?:Zoom (?:in|out)|Rectangle|Select)(?:[, ]+selected)?[, ]+(?:toggle )?button\b/i.test(phrase);
}

export function voiceOverMove(phrase, item, repetitions, depth) {
  if (repetitions >= 3 && depth > 0) return 'out';
  if (/^(scroll area|toolbar|group|split group|layout area)$/i.test(item.trim()) && repetitions === 1 && depth < 8) return 'into';
  return 'right';
}

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
    // NSWorkspace can read the frontmost app without System Events Automation.
    previous = await run('/usr/bin/osascript', ['-l', 'JavaScript', '-e',
      'ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier.js']);
    await run('/usr/bin/open', ['-a', appPath, '--args', '-ApplePersistenceIgnoreState', 'YES', '-SUEnableAutomaticChecks', 'NO', '-SUAutomaticallyUpdate', 'NO']); opened = true;
    await run('/usr/bin/open', ['-a', appPath, fixture]);
    await apple(`tell application id ${JSON.stringify(bundleID)} to activate`);
    await pause(1500);
    await run('/usr/bin/open', ['-a', '/System/Library/CoreServices/VoiceOver.app']); started = true;
    await pause(400);
    startedPid = await run('/usr/bin/pgrep', ['-x', 'VoiceOver']);
    // VoiceOver's startup announcement/window can take focus. Re-establish the
    // fixture before traversing rather than reading the desktop or welcome UI.
    await apple(`tell application id ${JSON.stringify(bundleID)} to activate`);
    await pause(700);
    // Commands and properties come from this Mac's VoiceOver.sdef dictionary.
    // Assert EXP-specific output, not merely that some desktop speech exists.
    // "First item" is relative to the current interaction group. A previous
    // session can leave the cursor in Properties/Handoff; exit nested groups
    // before starting the bounded traversal of this document window.
    for (let level = 0; level < 8; level++) {
      await apple('tell application "VoiceOver" to tell vo cursor to move out of item');
    }
    await apple('tell application "VoiceOver" to tell vo cursor to move to first item');
    let previousItem, repetitions = 0, depth = 0;
    for (let index = 0; index < 45; index++) {
      await pause(100);
      const phrase = await apple('tell application "VoiceOver" to get content of last phrase');
      const item = await apple('tell application "VoiceOver" to get text under cursor of vo cursor');
      transcript.push({ index, phrase, item });
      if (/design canvas/i.test(phrase) && transcript.some(t => hasCoreEditorControl(t.phrase))) break;
      const key = JSON.stringify([phrase, item]);
      repetitions = key === previousItem ? repetitions + 1 : 1; previousItem = key;
      const movement = voiceOverMove(phrase, item, repetitions, depth);
      transcript.at(-1).movement = movement;
      // The installed VoiceOver.sdef exposes containment navigation. A sequence
      // of move-right commands alone cannot enter a scroll area or toolbar.
      if (movement === 'into') {
        await apple('tell application "VoiceOver" to tell vo cursor to move into item'); depth++;
      } else if (movement === 'out') {
        await apple('tell application "VoiceOver" to tell vo cursor to move out of item'); depth--;
        await apple('tell application "VoiceOver" to tell vo cursor to move right');
      } else await apple('tell application "VoiceOver" to tell vo cursor to move right');
    }
    const all = transcript.map(t => t.phrase).join('\n');
    if (!/design canvas/i.test(all) || !transcript.some(t => hasCoreEditorControl(t.phrase))) {
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
