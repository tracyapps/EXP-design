# v2.7 bug polish review — October 18, 2026

Review scope: open native-app bugs, current source and existing checks. No
production/test source changed. Public v2.6/build 17 remains immutable.
BUG-034 Stage 2 remains parked indefinitely; no renderer retry is proposed.

## Account handoff

The controlled hosted ticket inbox journey is complete, including opt-out,
no-backfill re-enable and duplicate suppression. Public ticket writes, automatic
mail and retention remain paused. Remaining rollout gates are hosted foreign-author
isolation, separately approved disposable-account revocation/erasure, recovery and
operator coverage, privacy/retention/log/backup decisions, and physical AT review.
See `launch/TICKET-INBOX-ACCEPTANCE-v2.7.md`; native polish does not close those gates.

## Recommended order

Estimates are focused engineering time, excluding owner review and environment
repair. These are candidates, not newly selected release blockers or completed fixes.

| Order | Item | Bounded next step / acceptance | Estimate |
| --- | --- | --- | --- |
| 1 | Handoff regression baseline | Review the explicit-bounds model addition and deliberately update the manifest golden. Run the unchanged full package assertions after the approved baseline change; retain historical/current artifact comparison. | 1–2 hours |
| 2 | BUG-069 accessibility | Restore native automation, refresh the audit, then verify actual menu actions and visible text contrast. Start with title/extension, Export/Package headings and helper text. Keep native/container observations distinct; no blanket suppression. Retest keyboard/VoiceOver, appearance and increased contrast. | 1–2 days initially |
| 3 | BUG-004 centered title | Reproduce rename/location anchoring and Edited updates on current build; source already repositions native anchors and observes updates. Repair only behavior still reproduced, using public AppKit APIs. Review keyboard/accessibility with BUG-069. | Half–one day after reproduction |
| 4 | BUG-070 panel fit | Complete the existing 1x/2x, light/dark, narrow/floating-panel visual matrix. Compact/Extra Large/larger-target geometry already has six passing native checks; no reason to rewrite it speculatively. | 1–2 hours of owner review |
| 5 | BUG-017 structured HTML notes | Choose and document a safe structured representation before exporter changes. Preserve formatted note structure and rendered design, update contract/goldens deliberately, verify hostile text. README already preserves Markdown/task syntax. | 1–2 days after contract choice |

BUG-029 text keys and BUG-039 intermittent reordering still lack a reliable
current reproduction; do not replace stock AppKit key handling or guess at
invalidation. BUG-055 SVG inner-shadow spread needs a separate rendered export
fixture and bounded fidelity investigation; it is adjacent to the parked effects
work and is excluded from this first polish pass. BUG-056's remaining transparent
gradient/PDF edge case retains its prior owner deferral.

## Fresh evidence

- Unsigned `EXP Accessibility` build-for-testing passes:
  `/tmp/exp-bug-triage-build-20261018.log`. This is not warning-free/release proof.
- The isolated October 18 audit/name run is **blocked before test execution**:
  XCTest fails initialization with “Timed out while enabling automation mode.”
  Its summary reports one runner failure and zero passed tests; this is not a new
  app defect or a fresh audit. Receipt:
  `output/a11y/bug-triage-20261018/native-current/results.xcresult`, `summary.json`;
  `/tmp/exp-bug-triage-runtime-20261018.log`. Permissions were not changed.
  The first relative-path preparation was caught before execution and replaced
  by `native-current/` using absolute runner paths.
- Latest completed broader native audit remains October 17: **23 observations**
  (9 descriptions, 5 actions, 6 contrast failures, 2 near-threshold results,
  1 parent/child mismatch). These are observations needing triage, not 23
  certified standards violations. Existing focused fixes/receipts remain valid
  within their documented scope. See `ACCESSIBILITY-VERIFICATION.md`.
- `bash scripts/verify_semantic_html_contract.sh` passes: 47 role mappings,
  identities, state selectors, escaping and document round trip.
- `bash scripts/verify_semantic_html_package.sh` **fails the manifest golden**.
  Before that failure, task-list notes, fixed-input repeat bytes, actual entry
  sizes/hashes, HTML and CSS goldens pass. The later assertions do not execute
  on current source. Log: `/tmp/exp-bug-triage-package-20261018.log`.
- Root cause isolated without editing tests or production source: build the same
  package check using only `Document.swift` from `09b43b0^`, keeping all other
  inputs current. That historical-model control passes the entire package check.
  Full package comparison shows only two new `hasExplicitBounds: false` fields in
  `design.json` (+70 bytes), and the corresponding design byte count/SHA in
  `manifest.json`. HTML, CSS, tokens and README are byte-identical. Current README
  matches its existing golden. This demonstrates expected model serialization
  drift, not corrupted entry hashes. Do not silently reset the golden.
  Preserved current/previous packages and historical model are under ignored
  `output/a11y/bug-triage-20261018/`; logs:
  `/tmp/exp-triage-package-preserved.log`, `/tmp/exp-triage-previous-package.log`.

## Tracker reconciliation

BUG-066's pending label was stale: ROADMAP records explicit owner canvas
acceptance on September 3. Its status is now done, with that original evidence.
BUG-067's specific zoom-out/artboard-isolation acceptance remains unconfirmed;
October 17 pattern editing acceptance is not silently extended to that exact case.
BUG-063 was fixed before shipment; BUG-046 already records owner acceptance.
BUG-070 keeps its broader visual matrix pending despite positive initial feedback.

No source fix, new test, push, deployment, ticket enablement, cleanup or account
deletion was performed during this review.
