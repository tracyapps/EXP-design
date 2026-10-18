# Artboard notes — headings and links

October 18, 2026 · FEAT-072 · development 2.7/build 18.
Owner-verified October 18, 2026 after BUG-073/074 repairs: “that all is verified
working now.” Notes acceptance closes the next-feature sequencing gate; the full
physical accessibility/display release matrix remains open.
Crash/tooltip evidence and repeat: `NOTES-UNDO-VERIFICATION-v2.7.md`.

## What changed

The existing notes editor already styles bold, underscore italic, bullets,
checkboxes and a single `#` heading. It now styles `#` through `######` headings
and basic `[descriptive label](https://example.com)` / `mailto:` links.
Syntax stays visible for editing. Link labels are underlined and use the system
link color, with native NSTextView link behavior. Owner accepts the notes slice
October 18; the full physical VoiceOver/FKA release matrix remains separate.

`Artboard.notes` stays the same plain string; no document schema or codec changes.
The existing delayed save, document undo-session grouping and menus remain in place.
BUG-074 separates transient native text undo from the document's snapshots.
The text view moved from ArtboardNotesOverlay into its own production file so
focused checks exercise real AppKit editing/attributes/activation directly.
This adds syntax recognition, not a new canvas command; existing Format actions
remain available and replace any supported heading prefix without stacking it.

Supported destinations are HTTP, HTTPS with a host, and nonempty mailto links.
No resource is fetched by styling. File/custom/script/data schemes stay inactive,
and the allowlist is checked again on activation. Escaped links, image syntax,
inline code, fenced code and indented code are not active links. The subset
accepts one balanced parenthesis pair in a destination. Link reference definitions,
optional titles, tables, embedded HTML and full CommonMark rendering are outside
this slice. Their source remains editable text.

Ordinary edits retain paragraph-only restyling. Fence-containing notes get a full
bounded pass because a fence changes later lines. Notes over the existing 20,000
UTF-16-unit styling limit use plain text, including clearing previous links when
crossing that limit. Shrinking restores styling.

## The old bug is different

BUG-017 concerns standalone semantic HTML: notes are still a safe HTML comment,
not structured HTML note content. The Handoff README already preserves Markdown.
Changing the standalone representation needs its own contract/golden-fixture
change; it is not marked fixed by this editor enhancement.

## Verification receipts

- `bash scripts/verify_notes_formatting.sh` exercises production NotesTextView:
  all six heading levels, Unicode/source preservation, native link attributes and
  actual delegate activation, scheme checks at discovery/activation, inactive code,
  stale attributes, heading boundaries, existing emphasis/tasks, existing formatting
  actions, task continuation/end, long-note fallback and downstream fence edits.
  Latest complete log: `/tmp/exp-notes-verified-20261018.log`.
- Pre-change check fails specifically at heading level 2:
  `/tmp/exp-notes-before-20261018.log`. That first check used a fatal assertion;
  the harness now reports normal failure/exit 1. An intermediate compiler error
  used an NSString property that does not exist; corrected before passing checks.
  A subsequent regression check caught indented checklist styling being skipped
  by the new code guard (`/tmp/exp-notes-nested-before-20261018.log`); fixed and
  retained in the final passing checks. Existing nested list styling is preserved.
- Optional render command:
  `bash scripts/verify_notes_formatting.sh "$PWD/output/a11y/notes-formatting-20261018"`.
  Real AppKit light/dark text-view renders in that ignored directory were visually
  inspected. This is not full app/multi-display/contrast certification.
- Unsigned `EXP Accessibility` build-for-testing (app, thumbnail and test target)
  passes on the final source: `/tmp/exp-notes-complete-build-20261018.log`.
  Existing project warnings remain; no warning-free or signed-release claim.
- Existing appearance/style regression and backlog-ID checks pass; `git diff
  --check` is clean. Appearance log: `/tmp/exp-notes-appearance-20261018.log`.
- The Handoff package baseline was deliberately updated after a complete artifact
  comparison isolated FEAT-071's two `hasExplicitBounds: false` fields (+70 bytes)
  and the corresponding design-entry size/hash. HTML/CSS/tokens/README and other
  manifest fields are identical. `bash scripts/verify_semantic_html_package.sh`
  now passes every assertion, including later relationship/mask/CodePen checks.
  Log: `/tmp/exp-handoff-baseline-20261018.log`; original comparison:
  `BUG-TRIAGE-v2.7.md`. No assertions removed and no export behavior changed.

Native APIs and syntax references are recorded in BACKLOG FEAT-072. Native
heading styling alone does not establish heading-rotor navigation. No full
screen-reader pass is claimed. Desktop XCTest previously timed out enabling
automation before app tests; these direct AppKit checks bypass neither that
coverage gap. Owner acceptance was subsequently recorded October 18.

## Preserved owner check — slice accepted October 18

1. Open notes on a real artboard; type/paste six heading levels, Unicode, emphasis,
   checkboxes and `[Design guide](https://example.com)`.
2. Edit a heading level, change it via existing right-click Format → Bullet or
   Checklist, continue/end the list, then undo/redo. Remove a link's Markdown;
   it should stop being a link without losing the text.
3. Save/reopen the document. Verify the same literal Markdown remains and links
   work via native link interaction/context menu. Try the notes panel narrow/wide.
4. Verify keyboard/VoiceOver announcements and activation, light/dark and Increase
   Contrast on the actual displays. Unsupported schemes and code samples must
   remain plain editable text; no image should load.

No public release, push, deployment, live account changes or external link/email
launch was performed during automated verification.
