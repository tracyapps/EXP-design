# Notes Undo crash and literal help — October 18, 2026

BUG-073/074 fixes implemented. Focused and isolated-app checks pass; original
owner Xcode reproduction and physical AT review remain pending.

## Evidence and mechanism

The owner confirms **Undo while notes remain open**. Read the paused Xcode
console without resuming the process: `thread backtrace`, `register read x0 x1`,
then a read-only selector string lookup. Stack: `objc_msgSend` → Foundation
`_NSUndoStack popAndInvoke` → `NSUndoManager undoNestedGroup` → menu keyboard
dispatch. Selector at the failed invocation: `_undoRedoTextOperation:`.
The ViewBridge message does not establish a cause; do not equate it or the
tooltip warnings with the separately observed native text-undo failure.
Ignored receipt: `output/a11y/notes-crash-20261018/owner-stopped-thread.txt`.

NotesTextView previously inherited the document window's UndoManager, while the
panel also registered coalesced whole-model snapshots there. A snapshot restore
refreshes the notes string. Mixing those with native text operations leaves
operations referring to a different text buffer/range.

Three investigated paths: mixed native/document history, external text replacement
invalidating text operations, and editor lifetime. The first lifetime-only fixture
could not establish editor release; it is explicitly **inconclusive**. The focused
open-editor interleaving is red: document string refresh followed by native text
undo throws NSRangeException from `NSUndoTyping undoRedo:` and Foundation's undo
stack. This proves the unsafe interleaving, **not the owner's exact EXC_BAD_ACCESS
address or identical failure mode**. Baseline log:
`/tmp/exp-notes-undo-open-before-20261018.log`.

## Repair

- The transient notes text view owns its native text UndoManager. The document
  retains its existing coalesced **Edit Notes** snapshot and dirty/save behavior.
- Changed external text clears only the local text history before replacing the
  string; an unchanged SwiftUI refresh preserves local Undo. Detach clears local
  entries. No global/document undo history is erased by those resets.
- The Markdown example in `.help` now explicitly uses `Text(verbatim:)` and a
  shared plain string. Baseline native accessibility help had stripped the link
  syntax; repaired native help preserves `[label](https://example.com)` exactly.
- No model, file schema, export, native canvas text editing or account code changed.

## Fresh checks

- `bash scripts/verify_notes_undo_lifetime.sh` — **20 real AppKit cycles pass**:
  separate managers, native text Undo/Redo, external snapshot refresh, clearing
  stale ranges, unchanged refresh retaining history and detaching safely.
  `/tmp/exp-notes-undo-final-20261018.log`.
- `bash scripts/verify_notes_undo_lifetime.sh --open` — the minimized interleaving
  now completes all 20 rounds; `/tmp/exp-notes-undo-open-verified-20261018.log`.
- `bash scripts/verify_notes_formatting.sh` — all heading/link/Unicode, supported
  activation/inert schemes/code, task formatting and long-note/fence regressions pass.
  `/tmp/exp-notes-crash-format-regression-20261018.log`.
- Final unsigned `EXP Accessibility` build-for-testing passes app/thumbnail/test
  target. Existing project warnings remain; no warning-free/signed-release claim.
  `/tmp/exp-notes-undo-fixed-build-20261018.log`.
- **Real isolated app through native UI:** five typing → Cmd-Z → Shift-Cmd-Z
  cycles while notes remain open; actual Save and parsed JSON retain all five
  edits and the literal Markdown link. Closing notes, one document Undo restores
  original notes, and document Redo restores the full edit. Save, close the
  document, reopen the actual file and reopen notes: all five edits remain.
  Tooltip is literal. No crash in this exercised journey. Receipts/screenshots:
  `output/a11y/notes-crash-20261018/fixed-ui-cycles.json`,
  `fixed-document-roundtrip.txt`, `fixed-reopened-notes-ax.txt`,
  `fixed-reopened-notes.png`; owned test documents/copies in `baseline/` and `fixed/`.
  Those copies have isolated identities and network-disabled entitlements; owner
  documents and the installed app were not edited.

A small un-debugged SwiftUI warning fixture did **not** reproduce Xcode's repeated
message (its stderr-only check was inadequate), and is not a passing regression
test. It is retained only as an inconclusive experiment in ignored output.
The normal baseline app UI also did not reproduce the owner's exact crash with a
simple typing/Undo sequence; the stronger interleaving fixture and stopped owner
stack are retained as distinct evidence. Do not imply a complete crash matrix.

API sources checked: installed SwiftUI help overloads and
[Text(verbatim:)](https://developer.apple.com/documentation/swiftui/text/init(verbatim:)),
AppKit's NSTextView undo manager and
[shouldChangeText](https://developer.apple.com/documentation/appkit/nstextview/shouldchangetext(in:replacementstring:)),
Foundation [UndoManager](https://developer.apple.com/documentation/foundation/undomanager).

## Owner repeat

Stop the old paused run when ready and rebuild in Xcode; the stopped binary does
not acquire source fixes. Repeat the original sequence and several Undo/Redo
operations with notes open; close notes and verify one document-level Undo/Redo;
save/reopen. Confirm the Markdown tooltip no longer emits the repeated warnings.
Full VoiceOver/FKA and the real document/display matrix remain separate gates.

The owner process is left paused for inspection. Only disposable fixture builds
were stopped. No push, deployment, release artifact or live account changes.
