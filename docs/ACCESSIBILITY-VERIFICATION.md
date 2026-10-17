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
