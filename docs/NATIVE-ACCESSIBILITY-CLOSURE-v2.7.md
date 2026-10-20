# Native accessibility: finishing verification

October 20, 2026 · BUG-069 · development 2.7/build 18.

## Owner release decision — October 20

The owner accepts the extensive accessibility testing completed for v2.7:
VoiceOver sounds correct, and contrast, interface text size, click areas and
save/open have looked good in their testing. Full Keyboard Access could not be
enabled on this Mac and remains **unverified due to the environment**. This is
release acceptance with that limit, not a full keyboard or conformance pass.

The owner explicitly authorizes proceeding toward packaging. Retain the raw
audit observations and permission skips; they are not reclassified as passes or
blanket false positives. Confirmed accessibility barriers reported by users get
high-priority investigation and a hotfix release. Accessibility remains ongoing
work. The tasks below are a future verification guide, not a renewed request for
the owner to repeat checks before this package.

The owner's `output/a11y/2026-10-20T14-01-30-987Z/` is the baseline. Its native
suite has 13 passing tests, four failed tests and one permission skip. The website
has 201 passing checks and incomplete gradient contrast scans; owner reports
visually double-checking the website. No website implementation changes in this work.

## What the report actually found

| Result | Meaning / repair |
| --- | --- |
| Symbol names such as `rectangle.3.group` and `square.2.layers.3d.top.filled` | Real detached-header semantics gap. Decorative icons are hidden; the header is now a named collapse/expand button with an accessible state. |
| Empty-state instructions under the Design Language view bar | The view bar now reserves layout space; empty instructions wrap and scroll rather than being covered. |
| Faint small labels and `.design` extension | Stronger text tiers in both appearances, synchronized with the design tokens. Behind-window glass bounds wallpaper contribution; the extension uses the readable secondary tier. |
| Unnamed artboard popup/menu | The split menu exposed unnamed native descendants. Separate named New artboard and Artboard sizes controls keep the existing default action, presets and shortcut. Native document-location/rename controls also have explicit names. |
| `Pattern host` not hittable, followed by consent expected 0 but found 1 | The suite reused a detached workspace and persisted consent between independent tests. Each case now resets only the generated fixture's preference domain. Within-case relaunch/save/consent persistence is still tested. |
| Focus test skipped | Direct AX focus inspection requires permission for that generated runner. It is an unexecuted test, not proof that Tab navigation fails. Use the short keyboard check below if runner authorization remains unavailable. |
| VoiceOver stalls on “Keyboard shortcut: V.” | The visual hover bubble duplicated the source control’s accessible hint as a separate child window. Its redundant accessibility subtree is now hidden while the visual, hover/Escape behavior and original control hint remain. |
| VoiceOver times out asking System Events for the frontmost app | That step now uses AppKit/NSWorkspace, without System Events Automation. Startup refocuses the fixture; traversal can enter and leave scroll areas using the installed VoiceOver dictionary. |
| Disabled TouchBar/groups, parent-child mismatch or missing menu actions | Keep the observations. They need control/reader evidence; do not rename system containers or add no-op actions to silence the audit. A raw observation is not automatically a certified standards violation. |

## Future verification guide

Use a disposable document with one rectangle and one text layer in the current
Xcode build. Report the **first step that fails**, with what focus/speech did;
there is no need to diagnose the Accessibility Inspector's raw element tree.

1. **Keyboard task.** In System Settings → Accessibility → Keyboard, turn on
   Full Keyboard Access for this check. Use Tab/Shift-Tab and the displayed focus
   ring to reach the toolbar and Properties fields, edit a selected layer's field,
   Undo, save/reopen, and open/cancel an export dialog. Check that focus returns to
   a useful control. Restore your preferred system setting afterwards.
2. **VoiceOver task.** With VoiceOver on, use VO-Left/Right and VO-Space to reach
   and activate New artboard, Artboard sizes, Workspace mode and a panel's
   Collapse/Expand button. VO is your configured modifier (normally Control-Option).
   Use VO-Shift-Down to enter a group/scroll area and VO-Shift-Up to leave it.
   Reach the named Design canvas and a layer/Properties edit; check understandable
   names, current values, changes and the return from a dialog. Merely hearing a
   label is not action verification.
3. **Appearance task.** On the actual 1x and 2x displays, check light/dark and
   Large interface text. Read the filename extension, Grid/helper text and detached
   panel headings over a bright and dark desktop. Check Increase Contrast and
   Reduce Transparency/Motion. Confirm text stays readable without clipped controls.
4. **Record the result.** For each task: pass or the first failed control, appearance,
   display and input method. Keyboard/VoiceOver usability requires human judgment
   even when the automated smoke succeeds. No braille/rotor/language-wide claim is
   made by this bounded core-task review.

The automated suite retains unresolved findings. The owner's release acceptance
does not certify those observations as resolved. Signed-release font/payload checks and
the real updater continuity test remain separate release stages.

## Repeat the repaired native checks

`npm run test:a11y -- --native-only --interactive`

This uses disposable app/document identities, disables network/update integration
in the fixture, and does not change the installed app, the owner's documents,
TCC permissions or VoiceOver preferences. It records failures and skipped tests
as such. The contrast guard proves the defined compositing bounds, not every
possible external screenshot or every document color.

## Standards checked before changes

- [Apple NSAccessibility hierarchy](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol)
  supports excluding redundant elements; the source control keeps the complete hint.
- [Apple accessibility labels](https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-9ek2h)
  and [hiding decorative elements](https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:)).
- [Apple accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
  describe the screen-specific contrast/description/action checks.
- [WCAG 2.1 SC 1.4.3](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html):
  normal text uses the 4.5:1 threshold, without rounding a result up to pass.
  The new independent compositing guard caught 4.495:1 at one tier; its opacity
  was increased before accepting the palette.
- [Apple VoiceOver keyboard commands](https://support.apple.com/guide/voiceover/control-your-mac-with-keyboard-commands-vo2681/mac)
  explain group interaction; `VoiceOver.sdef` on this Mac confirms the script's
  `move into item` / `move out of item` commands.
- [Apple Full Keyboard Access](https://support.apple.com/en-euro/guide/mac-help/mchlc06d1059/27/mac/27).

These are native AppKit/SwiftUI changes. No ARIA role, state or HTML mapping changes.

## October 20 repair receipts

- `/tmp/exp-a11y-repair-build-20261020.log`: initial app/thumbnail/helper and UI-test
  Debug build passes. `/tmp/exp-a11y-repair-final-build-20261020.log`: final Debug
  build including the named artboard controls and layout repair passes.
- `/tmp/exp-a11y-repair-release-20261020.log`: universal Release app/shared targets
  pass before the final Design Language layout-only repair. Final signed payload
  verification remains a release-stage gate; no signed/notarized claim here.
- `output/a11y/2026-10-20T17-49-16-336Z/`: complete first repair run, 15 pass / two
  fail / one permission skip. Both usage tests and the universal-image check now
  pass in the complete suite. One failure is its old Properties-header static-text
  lookup, now correctly targeting the new Collapse Properties button; the other
  is the retained audit (25 observations). This run does not prove the final
  artboard controls or final layout, which were built afterwards.
- `/tmp/exp-a11y-repair-guards-20261020.log`: five passing guards for native/design
  token consistency, independently calculated 4.5:1 compositing bounds, and
  reader traversal/matcher regressions. The original 4.495:1 check failure was
  corrected in the color token, rather than rounding or weakening the assertion.
- `verify_interface_accessibility.sh`, `verify_transient_surface_levels.sh`, backlog
  IDs and `git diff --check` pass. Font distribution guard passes on the unsigned
  Release app. No document model, canvas paint/export behavior or web flow changed.

All original failures remain on disk. No audit category is blanket-suppressed.

### Final source checks and reader result

- `output/a11y/native-closure-final-20261020/`: both named artboard controls and
  the detached-header expand/collapse/Properties journey pass; audit stays failed
  with 27 observations. The header test targets the real button, not removed
  separate static text.
- `output/a11y/native-closure-layout-final-20261020/`: the final named-control
  case also proves the Design Language scroll viewport ends above its view bar.
  Screenshot inspected: the bar has its own opaque layout space; longer empty
  instructions are scrollable. The retained audit has 23 observations.
- `output/a11y/native-closure-tooltip-final-20261020/voiceover-transcript.json`:
  **real VoiceOver smoke passes**, reaching Select and Design canvas in 44 moves.
  This verifies navigation and retains speech, not just an AX-tree simulation.
  It does not prove all menu activations, editing or human usability.
- `output/a11y/native-closure-hover-regression-20261020/`: corrected native hover
  check passes. A new real WindowServer window appears on hover while its duplicate
  shortcut static text is absent from accessibility; Escape removes the window.
  The first check wrongly assumed the child window kept a particular server layer;
  that failed attempt is retained. The regression checks the window's appearance
  and disappearance by identity instead.
- Later detached-menu attempts on a negative-coordinate display time out while
  XCTest traverses Window → Sanaa. Their trees show the fixture on that monitor;
  no crash or source callback failure is inferred. The fixture setup now positions
  its window on the primary display through a normal window drag. This is test
  determinism, not multi-monitor product proof or a change to owner preferences.
- The post-tooltip audit retains **14 observations**: six disabled descriptions,
  five named-menu action observations, two contrast observations and one disabled
  parent/child mismatch. See `native-closure-tooltip-final-20261020/findings.md`.
  Screens/workspace/display conditions differ across these audits: counts are not
  a controlled before/after performance or compliance score.

At this checkpoint, named-menu activation, the two contrast locations (Package
and No saved colors yet), and keyboard editing/return focus were still pending.
The later owner decision at the top of this document accepts the available
release evidence while keeping the keyboard limitation and raw observations.

### Primary-display rerun

`output/a11y/native-closure-primary-regression-20261020/`: the complete detached
Sanaa → Agent settings → General → component collapse/expand → Properties reveal
and Grid-field hit-test journey passes, zero failures or skips (exit 0). This
confirms the corrected fixture positioning and the current header semantics.
The secondary-display menu-notification failures remain preserved, rather than
being silently retried and discarded.

Final test build: `/tmp/exp-a11y-repair-primary-test-build-20261020.log`, exit 0.
All repairs are local. The owner has since accepted extensive release testing
within the limits stated above; these selected runtime passes do not establish
complete accessibility verification.
