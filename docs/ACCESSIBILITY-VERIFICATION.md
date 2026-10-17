# Repeatable accessibility verification

October 17, 2026 · INFRA-009 · native v2.7/build 18 + local website.

Run from the repository root:

```sh
npm run test:a11y -- --interactive
```

This runs the headless website matrix, builds an isolated native UI-test app,
runs Xcode UI tests, and attempts the real VoiceOver smoke only when its setup
is available. Use the interactive run when the desktop is free: the native app
comes to the foreground. The owner's installed app and open documents are never
the test target. No provider emails, deployments or public registrations occur.

Other useful selections:

```sh
npm run test:a11y -- --web-only
npm run test:a11y -- --native-only --interactive
npm run test:a11y
```

Without `--interactive`, native compilation/preparation runs but desktop/VoiceOver
coverage is explicitly blocked. A web-only run can pass its selected scope while
native/real-screen-reader evidence remains untested. No successful command means
full WCAG conformance or complete assistive-technology usability.

## Results you can review

Every invocation prints its new `output/a11y/<timestamp>/report.md` path.
`output/a11y/latest.json` points to the latest run. The report contains each result,
exact setup/failure reasons and the remaining human checklist. JSON is also saved
for later CI/report integration. Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Selected automated layers passed; incomplete/manual review stays separate |
| 1 | A test, audit or harness failed; inspect the evidence |
| 2 | Selected coverage is blocked/unexecuted, with no failing test |
| 64 | Unsupported command arguments |

Web evidence includes screenshots, ARIA-tree captures and complete axe JSON for
each scanned state. `review.json` deduplicates incomplete findings by rule/selector
and retains every affected scenario. An incomplete contrast result is **not a
contrast pass**. Native evidence includes build/runtime logs, XCTest summary,
`results.xcresult` and exported attachments. Custom screenshots crop to the fixture
window; Xcode also creates local diagnostic artifacts. Receipts and disposable
apps/documents are ignored by Git and are never published automatically.

## What is automated now

| Layer | Current coverage | Evidence boundary |
| --- | --- | --- |
| Web keyboard | Explicit account creation, email-code entry, post-login focus, private profile save/reload, larger text persistence, account deletion, invalid email, wrong/expired code, unavailable service, Pro confirmation/withdrawal | Real key events; no scripted DOM focus or selectOption to substitute for keyboard use. Chromium uses Tab; WebKit uses Apple's documented Option-Tab to reach every control without changing Safari/system preferences |
| Web structural audit | Account states above, support and Pro pages; axe 4.14.0 detectable WCAG 2.1 A/AA rules | Scans the entire rendered page, with no disabled rules or excluded header/footer. Browser ARIA trees are not VoiceOver speech |
| Web matrix | Chromium and WebKit; dark desktop 1280px; light 390px mobile with reduced motion; account text at 20px | Bounded combinations, not every permutation. WebKit is not installed Safari + VoiceOver evidence |
| Native UI | Named tools/zoom/panel controls and canvas; zoom-field edit; Tab/Shift-Tab focus assertion; Open/Escape and Cmd-S smoke; Apple's visible-screen accessibility audit | XCTest plus public AX focus API; saved-file write/reopen, full canvas editing and full-system Full Keyboard Access are not established by these tests |
| Real VoiceOver | Guarded native editor traversal and actual `last phrase` capture, requiring spoken core-control and canvas names | Separate real screen reader layer; current machine setup may block it. No virtual speech or AX-tree stand-in is accepted |

The native audit records **every visible finding** with its description and element
subtree and returns false to Apple's issue filter so findings remain failures.
It does not blanket-ignore unlabeled groups or contrast warnings. Native skipped
tests remain blocked, even if Xcode otherwise returns a successful exit code.

## One-time setup

Dependencies use the existing root and website lockfiles:

```sh
npm ci
npm --prefix website ci
node website/node_modules/playwright/cli.js install chromium webkit
```

The pinned axe adapter requires Node 22.12+; local evidence uses Node 24.13.
Native runs need Xcode and the macOS desktop; current evidence uses Xcode 26.6 /
macOS 26.6.2. Installed SDK declarations were checked for macOS support of
`performAccessibilityAudit`; platform-specific XCTest focus properties were not
used because macOS does not expose them. Focus uses public AX APIs instead.

For real VoiceOver, open **VoiceOver Utility → General → Allow VoiceOver to be
controlled with AppleScript**. In **System Settings → Privacy & Security**, grant
the invoking terminal/IDE the required Accessibility and Automation permissions
for System Events and VoiceOver when macOS requests them. The native focus test
may additionally require Accessibility permission for the generated
`native/EXPAccessibilityUITests-Runner.app`; its skipped-test message identifies
that gap. Rerun and use the recorded result, rather than assuming a grant worked.

**Runner identity matters:** System Settings → right-click the runner → Show in
Finder reveals which copy has permission. On this Mac the enabled entry points to
`output/a11y/2026-10-17T05-47-38-041Z/native/EXPAccessibilityUITests-Runner.app`;
that exact runner passed its zoom/Tab/Shift-Tab focus test on October 17. A newly
created ad-hoc runner is not automatically authorized by an older entry with the
same visible name. A stable runner/signing identity is still needed for repeatable
unattended focus checks without repeated grants. Do not add more identical-looking
entries based only on the displayed name.

The preflight checks the system AppleScript permission flag, then attempts real
AppleScript commands. It no longer requires the legacy user-defaults domain: the
owner enabled the setting through VoiceOver Utility, producing the system flag
without that old preference. No attempt is made to read/write protected preference
stores. The October 17 follow-up could read `last phrase` and quit through scripting
(the returned phrase was `missing value`); editor traversal still fails at reader
startup/cursor movement. This is not a spoken-output pass or evidence of another
missing permission. Detailed receipts: `output/a11y/permission-recheck-20261017/`.

The runner does not edit TCC, disable SIP, import VoiceOver preference packs,
change global keyboard settings, or copy speech through the clipboard. It refuses
to take over VoiceOver if it is already running. The real-reader smoke restores
the previously focused app and stops the VoiceOver instance it started in its
cleanup path; interruption/setup failures remain visible. Read/quit scripting
commands have been exercised, but live spoken editor traversal remains unverified.
The current startup failure needs investigation before this smoke can pass.

## Isolation and repeatability

Web tests own a temporary socket-only PostgreSQL cluster and remove it on exit.
Actual account/Pro handlers persist local state; mail is captured in process
memory. The fixture has no browser-visible test-code endpoint. Code expiry is
controlled directly in the disposable database. Browser scenarios reset their
shared loopback-IP rate window between variants; **rate-limit correctness is
proved separately by the existing real-DB service tests**, not by that reset.
The release-list provider boundary is unavailable in this fixture. External
browser requests, including the icon CDN, are isolated; this is not a hosted
network/privacy proof.

Native tests build under `/tmp/exp-a11y-derived`, then copy/re-identify/re-sign
runner-owned artifacts under the receipt directory. Each run has a unique app
identifier to prevent LaunchServices from selecting an older fixture. The copy
has a separate sandbox/preferences identity, no outgoing-network or Codex access,
and no registered .design associations. Helpers/thumbnail extension are removed
only from this copy. Shipping source, bundle identity, archive scheme and immutable
releases are unchanged. This fixture does not prove helper/update/extension behavior.

## First findings and remaining human work

The initial web run exposed a shared version badge whose accessible name omitted
the visible `v2.6 / Oct 2` text. Removing that overriding name lets native link
content supply the name; the longer release detail remains in its title.
The corrected Chromium/WebKit keyboard/audit matrix passes detectable checks.
Glass/pseudo-element header and gradient footer contrast remain incomplete engine
results, with exact selectors saved for review.

Apple's runtime audit collected 27 naming, action, contrast and structural
findings in the initial editor fixture, tracked in BUG-069. Indexed findings and
individual element subtrees are retained in `native/findings.md`/`findings.json`.
Investigate actual control behavior and VoiceOver navigation before deciding
whether to change source or document a narrowly justified platform false positive.
Native focus assertions and real VoiceOver are still subject to the permission
gate above. The roadmap/release checklist records the latest counts and receipts.

Keep a short human pass for spoken clarity, useful grouping/order, canvas and
Sanaa tasks, selected-layer/Inspector edits and export/reopen. Expand the bounded
matrix for Full Keyboard Access, Quick Nav/rotor, verbosity/language, Increase
Contrast, Reduce Transparency, Large native interface type and actual 1x/2x
displays. Homepage/download/learn/ARIA-guide pages and their flows remain outside
this first account/Pro/support web matrix. Re-test changed shared controls broadly;
do not manually repeat every combination for every small change.

## Sources checked

- [Apple app accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
- [Apple VoiceOver scripting option](https://support.apple.com/guide/voiceover/cpvougen/mac)
- [Apple Safari keyboard shortcuts](https://support.apple.com/guide/safari/keyboard-shortcuts-and-gestures-cpsh003/mac)
- [Playwright accessibility testing and its limits](https://playwright.dev/docs/accessibility-testing)
- [WCAG 2.1 focus order](https://www.w3.org/WAI/WCAG21/Understanding/focus-order.html)
- [WCAG 2.1 label in name](https://www.w3.org/WAI/WCAG21/Understanding/label-in-name.html)
- [WAI-ARIA 1.2 status](https://www.w3.org/TR/wai-aria-1.2/#status)

The installed VoiceOver.sdef dictionary and XCUIAutomation headers/Swift interface
were inspected too. Actual VoiceOver speech is a pending execution gate, not a
claim based on those declarations or successful AppleScript compilation.


## v2.7 interface preferences — FEAT-070

Settings → Accessibility separates unconditional accessibility semantics from
personal presentation choices. Names, states, input instructions and meaningful
control actions must work in every mode. Baseline legibility/contrast is not an
optional preference; BUG-069's remaining contrast findings still need triage.

- **Interface type size:** System default, Compact, Standard, Large (125%) or
  Extra Large (150%). The existing preference key/values remain valid. Shared
  `EXPType` fonts now scale explicitly; fixed numeric fields widen, layer rows
  gain space for two lines, and dock headings scroll rather than overlap.
  System default uses AppKit's public preferred body-font baseline. This does not
  promise access to the per-app text-size overrides macOS offers some Apple apps.
- **Larger click targets:** independent of text size. Shared field/button styles,
  tool buttons, Inspector icon actions and layer-row controls gain larger targets.
  This is not a claim that every legacy/custom control has a 44-point target.
  Padding on a styled field must really focus the native editor; a larger painted
  rectangle alone is not sufficient. Tool buttons scroll vertically if needed.
- **Panel help text (Accessibility):** Automatic with VoiceOver, Show, or Hide.
  This controls extra Properties explanations for grids, vector/knife operations,
  relationships, text outlines and advanced corners. It does not control font size,
  toolbar labels or inactive panel-tab titles. Critical warnings, state/empty-state
  messages, control labels and accessible hints remain unconditional. Compact type
  size means smaller interface type; choose Hide here to remove extra explanations.
- **Drawing toolbar labels (General):** Automatic with VoiceOver, Icons only, or
  Icons and text. Automatic reads the reader status directly, independently of panel
  help. The legacy Follow guidance value migrates once to the matching explicit
  toolbar mode; existing settings keep their visual choice. Unknown future values
  fall back without erasure. Text size now appears only in Accessibility.

Properties widths are constrained to the viewport. Auto Padding uses flexible
edge-marked fields (top/right/bottom/left position plus a complete accessible name),
with a two-row fallback when needed. Corner and stroke are separate rows; auto-layout
spacing and align-axis groups can reflow. Pathfinder uses compact native vector
icons, named actions, hover explanations and 28-point targets (44 when requested).
No new document operation, model, renderer, export or file format was introduced.

VoiceOver does not imply that larger text or targets are wanted. Its status is
never persisted as a user profile, sent to a provider, or used for analytics.
No special Accessibility grant or private preference-store access is required
for these public system reads. Artwork geometry, document type and exports are
unchanged by interface preferences.

Universal fixes in this slice: named 34 previously empty-title TextField
constructors and ten Picker constructors across MainWindow and the color/paint
editors (many already had additional explicit accessible names),
named polygon stepping and layer/group disclosure controls, named Settings pickers,
added grid/color input hints, restored spoken tool-shortcut hints previously
overwritten by an empty hint, and hid the redundant Components empty-state illustration.
The two default grid-field names and decorative-image behavior have runtime checks;
other selected-object Inspector contexts still need their full human matrix.

Focused policy checks: `bash scripts/verify_interface_accessibility.sh` compiles the
actual preference/model source against an isolated UserDefaults suite. It covers
legacy values, invalid-value fallback without erasure, override precedence,
VoiceOver-on/off guidance decisions, geometry and persisted reload. Native UI cases
cover real pointer interaction and changing Settings in an already-open editor.

Sources reviewed before naming/policy work:
[Apple VoiceOver guidance](https://developer.apple.com/design/human-interface-guidelines/voiceover),
[public VoiceOver status](https://developer.apple.com/documentation/appkit/nsworkspace/isvoiceoverenabled),
[AppKit preferred text styles](https://developer.apple.com/documentation/appkit/nsfont/textstyle),
[Apple larger-text criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria),
[WCAG labels/instructions](https://www.w3.org/WAI/WCAG21/Understanding/labels-or-instructions.html),
[WCAG non-text content](https://www.w3.org/WAI/WCAG21/Understanding/non-text-content.html).
Installed AppKit/SwiftUI SDK declarations were checked as well. Web ARIA attributes
are not applied to native SwiftUI/AppKit controls.

VoiceOver harness correction: a previous loose `select` match also accepted
“Properties selected button” or instructional “Select layers” text. The matcher now
requires a named core control and its button role; two regression tests reject
those false positives. Real canvas speech was captured, but that alone is not
proof of traversal to the Select/Rectangle/Zoom buttons.


October 17 FEAT-070 receipts: the combined native run at
`output/a11y/2026-10-17T14-25-39-868Z/` has five passing workflow tests, one skipped
AX focus test (new runner copy), and one failed audit test with 23 observations:
nine missing descriptions, five missing actions, six contrast failures, two near-
threshold contrast results and one parent/child mismatch. Grid-field missing-title
and decorative-symbol-name findings are absent; no other category was suppressed.
The real VoiceOver transcript contains actual canvas/editor speech, but the corrected
core-control matcher fails the 45-move traversal gate. This is not permission proof
of a missing grant and is not complete screen-reader acceptance.

The final focused native rerun after the additional color/picker naming changes is
`output/a11y/interface-final-20261017/native/results.xcresult`: all three preference,
actual padded-target, and universal-name checks pass. The policy suite and two
VoiceOver matcher regression tests pass. Final build logs:
`/tmp/exp-interface-label-followup-build.log`, `/tmp/exp-interface-hints-build.log`.
Cropped dark editor/Settings screenshots were visually inspected. A launch argument
alone did not establish Light appearance; real light-mode/1x/2x, small-window,
selected-object/color-popover, floating/source-editor and live reader on/off review
remain required. This first slice does not complete the entire accessibility audit.


October 17 toolbar-label refinement: `output/a11y/toolbar-labels-20261017/native/results.xcresult`
has three passing native tests and no failures/skips: icons only with Always show
plus larger targets; existing enlarged controls/visible guidance; live Settings
switching between Icons and text, Icons only and Follow guidance. The actual
production preference/model policy check passes, including conflict precedence,
persisted reload and non-destructive invalid-value fallback. Build-for-testing
passes (`/tmp/exp-toolbar-labels-build.log`); cropped dark editor/Settings screenshots
were inspected. This focused rerun does not close the earlier audit or reader gates.
Apple's VoiceOver guidance was rechecked: invisible alternative names must remain
available for key controls; hiding visual toolbar text does not remove those names.


October 17 owner refinement — BUG-070 / FEAT-070: the corrected regression against
preserved old code fails because Background stroke width extends 45.5pt beyond the
usable right edge (`output/a11y/panel-fit-20261017/native/baseline-recheck.xcresult`).
An initial baseline selected the artboard rather than the group and was corrected.
An intermediate expanded run missed Auto Padding after top-down panel collapsing
moved subsequent click targets; its screenshot shows the switch still off. The
harness now collapses bottom-up and waits for the new layout controls. No finding
was ignored or reclassified as a pass.

Final focused matrix: all six tests pass, no skips or failures, in
`output/a11y/panel-fit-confirmed-20261017/native/results.xcresult`.
It exercises Auto Layout plus Auto Padding at Compact, Extra Large and larger-target
sizes, all eight side fields, actual side-field editing, stroke/transform/gap
bounds, compact named Pathfinder controls and align bounds; live Settings help
Show/Hide, single placement of type/toolbar settings, toolbar switching, and the
existing enlarged-target/accessible-name checks. Production policy tests cover
legacy toolbar migration (including an unstored inherited default), independent
VoiceOver policy, persistence and invalid-value preservation. Build logs:
`/tmp/exp-panel-fit-final-build.log`, `/tmp/exp-panel-fit-tests-build.log`.
This does not close the broader audit, real-reader or 1x/light/float visual gates.


Final migration review added an explicit restart regression: after a fresh install,
changing panel help must not change an automatic toolbar choice on a later launch.
The regression failed before the fix (`/tmp/exp-toolbar-restart-regression.log`).
Legacy conversion now runs only at initialization and seeds an independent fresh
install default; subsequent refreshes only read the choices. The real UserDefaults
restart/migration/persistence suite passes. Final build:
`/tmp/exp-panel-migration-final-build.log`.

After the final migration fix, the two native live-Settings/independent-toolbar
checks pass again with no failures/skips in
`output/a11y/panel-settings-final-20261017/native/results.xcresult`.
Final cropped General/compact Properties/larger-target screenshots inspected.


## Pattern/source authoring and detached windows — October 17

FEAT-071 adds explicitly named native bounds fields and first-pattern buttons;
BUG-071 fixes fill-popover action targeting. BUG-072 restores reachable Settings
and selectable peer panels, with normal window levels and reveal commands.
The four focused native tests pass with no failures or skips; these are workflow
checks, not a new blanket accessibility-audit pass. Real reader traversal, large
text/full appearance and physical multi-display behavior remain owner gates.
Receipts, earlier failures/repairs and repeat checklist:
`SOURCE-BOUNDS-VERIFICATION.md`.
