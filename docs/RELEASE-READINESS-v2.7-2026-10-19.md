# v2.7 release preparation — October 19, 2026

## October 20 final native packaging review

This addendum supersedes the remaining-order section below. The owner accepts
extensive accessibility testing: VoiceOver sounds fine; contrast, text size,
click areas and save/open look good. Full Keyboard Access cannot be enabled on
this Mac and remains **environment-blocked/unverified**. Raw observations and
permission skips remain preserved. Confirmed reported accessibility barriers
receive high-priority investigation and hotfix treatment. This is release
acceptance within stated limits, not full AT/conformance certification.

The accepted radial/Mesh, Color Matrix, polygon, pattern, Flip, notes and physical
multi-monitor reviews above remain closed. No additional speculative feature or
renderer work is admitted before packaging. Existing BUG-055 SVG inner-shadow
spread and unsupported import fidelity limits are disclosed in the revised
release notes; BUG-034 Stage 2 stays parked. Local importer fixtures do not become
a fresh live-Figma/API claim. Broader unexecuted matrices remain unverified.

One concrete packaging omission was found and corrected: Sparkle's license was
in the dependency artifact but absent from the app resources. Copy the exact
`LICENSE` from pinned Sparkle 2.9.4, including its external notices, to
`EXP [design]/Resources/Sparkle-LICENSE.txt`. The final built resource matches
both upstream and source byte for byte (SHA-256
`389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe`).
`verify_release_candidate.sh` now rejects a missing/different bundled copy.
This is a distribution-notice correction, not a license grant for EXP source or
a blanket legal/provenance review. Existing commercial policy decisions stay
recorded in the self-launch checklist.

Fresh final-source evidence, October 20 (all commands exit 0):

| Check | Receipt |
| --- | --- |
| Universal Release after all native repairs | `/tmp/exp-v27-final-source-release-20261020.log` |
| Incremental universal Release including Sparkle notice | `/tmp/exp-v27-final-payload-release-20261020.log` |
| App/thumbnail 2.7/18 and unchanged IDs; app, exp-mcp and sanaa-runtime arm64+x86_64; exact notice comparison; no telemetry endpoint; public appcast remains 2.6/17 | `/tmp/exp-v27-final-payload-audit-20261020.log` |
| Font distribution guard: final unsigned app, website/dist and design-system export | `/tmp/exp-v27-final-fonts-20261020.log` |
| Five contrast/reader guards, zero failures/skips | `/tmp/exp-v27-final-guards-20261020.log` |
| Interface accessibility policy | `/tmp/exp-v27-final-interface-20261020.log` |
| Appearance round trip | `/tmp/exp-v27-final-appearance-20261020.log` |
| Transient surface ordering | `/tmp/exp-v27-final-transients-20261020.log` |
| Sparkle setup 2.7/18 | `/tmp/exp-v27-final-sparkle-20261020.log` |
| Backlog identity integrity | `/tmp/exp-v27-final-backlog-20261020.log` |

`bash -n scripts/verify_release_candidate.sh` and `git diff --check` also pass.
Build commands use the same project/scheme/Release/derived-data path shown below,
with `CODE_SIGNING_ALLOWED=NO`. Existing compiler warnings remain. These builds
are not signed/notarized candidates. The October 19 broad exporter/model/service
battery remains relevant; final changes affect chrome, tests, notices and docs.
The focused native runtime/real-reader receipts are in
`NATIVE-ACCESSIBILITY-CLOSURE-v2.7.md`; no new full-suite audit pass is claimed.

### Remaining package sequence

1. Freeze the reviewed source before producing its archive; working changes are
   currently uncommitted. Preserve the accepted 2.7/18 identity.
2. Create the signed universal archive. Run the signed release-candidate check
   (`--local`) and font/resource audit on that actual archive/export.
3. Notarize, staple, create a clean ZIP and verify its extraction with production
   release-candidate checks. Record final hash, byte length and exact source.
4. With separate publication authorization, publish the immutable download before
   its signed appcast item; preserve history and disable deltas. Match notes,
   download and website version to the actual artifact.
5. Verify real v2.6→v2.7 update/install/relaunch and preference/document continuity.

Optional hosted member hub, signup/mail/retention, telemetry enablement, paid
offers, recruitment metrics and campaign plans keep their own gates. Preparing
this native package enables none of them. Earlier November/December plan dates
do not delay the owner's current native packaging request. No new source blocker
was found in this bounded review after the notice correction; broader unchecked
launch items are not silently certified. No commit, push, signing, notarization,
feed change, deployment or public release occurred.

## October 19 baseline (retained)

Source: `8cc4875e9a17c52dccc3de77530f840589cacc88`; this session changes release
documentation and existing native UI test selectors only. Development remains 2.7/build 18. Public v2.6 is unchanged.
This receipt is a preparation checkpoint, not a release approval.

## Owner acceptance recorded

- FEAT-033/076: latest radial/Mesh handles resolved, including the previously
  pending gradient refinement review.
- BUG-077: overlapping palettes and window ordering work on the owner's physical
  multi-monitor setup. Earlier BUG-072 acceptance is preserved.
- BUG-079/081: pattern anchoring verified by the owner's follow-up.
- BUG-078: Flip verified by the same follow-up.
- BUG-076/080 and FEAT-075: owner explicitly confirms seamless repeats, per-fill
  scaling and real-artwork SVG export/browser or Quick Look: “Yes, all three work.”

These reports close the functional reviews. They do not infer every assistive
technology, export, source-library or display combination from general acceptance.
Backlog, roadmap, feature receipts and release checklist now distinguish them.

## Fresh local evidence

All commands run on the owner's Mac with the existing Xcode and dependencies.
Logs below are local, temporary files; no external mail, rollout or release occurs.

| Boundary | Command / receipt | Result |
| --- | --- | --- |
| Universal Release app, thumbnail and helpers | `xcodebuild -project 'EXP [design].xcodeproj' -scheme 'EXP [design]' -configuration Release -derivedDataPath /tmp/exp-v27-release-readiness-20261019 CODE_SIGNING_ALLOWED=NO build`; `/tmp/exp-v27-readiness-release-build-20261019.log` | Exit 0; existing compiler warnings remain |
| Identity and architecture | Built app/thumbnail Info.plist and `lipo -archs` on app, exp-mcp and sanaa-runtime | 2.7/18; existing app/thumbnail bundle IDs; all three executables arm64 + x86_64 |
| Font distribution guard | `bash scripts/verify_font_distribution.sh APP website/dist 'design/EXP [design] Design System'`; `/tmp/exp-v27-readiness-fonts-20261019.log` | Exit 0 on all three trees; unsigned payload only |
| Mesh/radial native, PDF, SVG, CSS and editable own-import | `bash scripts/verify_mesh_fill.sh /tmp/exp-v27-readiness-mesh-20261019.json`; matching `.log` | Exit 0 |
| Handoff package | `bash scripts/verify_semantic_html_package.sh`; `/tmp/exp-v27-readiness-handoff-20261019.log` | Exit 0, including current manifest golden |
| SVG patterns | `bash scripts/verify_svg_pattern_import.sh`; `/tmp/exp-v27-readiness-patterns-20261019.log` | Exit 0 |
| Color Matrix | `bash scripts/verify_color_matrix.sh`; `/tmp/exp-v27-readiness-matrix-20261019.log` | Exit 0 |
| Appearance, interface policy, transient surface ordering | Existing `verify_appearance_style.sh`, `verify_interface_accessibility.sh`, `verify_transient_surface_levels.sh` | Exit 0; source/model checks do not replace human AT |
| Services and native consent/wire boundary | `npm test`; `/tmp/exp-v27-readiness-services-20261019.log` | Exit 0; 154 service tests plus Swift lifecycle and actual local HTTP→DB checks |
| Website build | `npm --prefix website run build`; `/tmp/exp-v27-readiness-website-20261019.log` | Exit 0; site continues to derive public version from unchanged appcast |
| Real-document pattern cache parity | `bash scripts/verify_pattern_raster_performance.sh '/Users/tapps/Desktop/test2/perf-tests-2.5/stresstest.design'`; `/tmp/exp-v27-readiness-stress-20261019.log` | Exit 0; cache/renderer parity, not whole-app performance or owner interaction proof |
| Sparkle development setup | `bash scripts/verify_sparkle_setup.sh 2.7 18`; `/tmp/exp-v27-readiness-sparkle-20261019.log` | Exit 0; no v2.7 feed item published |

An initial Sparkle invocation omitted its required version/build arguments and
exited 2 with usage only. The corrected invocation above passes; this was an
invocation error, not a product failure.

## Broader native regression receipts

All sixteen existing scripts exited 0. The command for each is
`bash scripts/verify_NAME.sh`, with NAME from the list below. Full command/exit/log
ledger: `/tmp/exp-v27-readiness-regressions-20261019.tsv`; individual logs use
`/tmp/exp-v27-readiness-NAME-20261019.log`.

- `nested_component_graph`, `anchored_relationships`, `canvas_pages`
- `xd_importer` (11 real packages, 644 artboards, 84,208 layers), `figma_importer`
- `semantic_html_contract`, `svg_token_bridge`, `effect_export_coverage`
- `codepen_package_import`, `rendered_html_importer`, `rendered_html_webkit`
- `storybook_package_import`, `ruler_pointer_overlay`, `vector_shape_editing`
- `notes_formatting`, `notes_undo_lifetime`

The Figma check is a local importer fixture check, not permitted live-file/API proof.
The additional `verify_node_tree_performance.sh`,
`verify_canvas_path_performance.sh` and `verify_source_bounds.sh` also exit 0.
Logs: `/tmp/exp-v27-readiness-node-performance-20261019.log`,
`/tmp/exp-v27-readiness-path-performance-20261019.log`,
`/tmp/exp-v27-readiness-source-bounds-20261019.log`.

## Fresh web keyboard and accessibility checks

`npm run test:a11y -- --web-only` exits 0: **201 passed, zero failed/blocked**,
with **128 incomplete scan results and 86 distinct review findings**. These
incomplete contrast scans still need review and are not counted as contrast passes.
Evidence: `output/a11y/2026-10-20T04-37-20-378Z/report.md`, `review.json`,
and `/tmp/exp-v27-readiness-web-a11y-20261019.log`. Chromium/WebKit local journeys
are distinct from human Safari/VoiceOver and hosted account lifecycle proof.

## Native UI regression maintenance

The initial full run is retained at
`output/a11y/2026-10-20T04-36-27-811Z/`. It reproduced stale selectors in three cases:
`testPatternCreationFromEmptyFillAndReopen` expected the removed Pattern radio
button instead of the current `Pattern fill` button; the live Settings test
expected the previous `Drawing toolbar labels` name instead of
`Toolbar and fill-type labels` (live settings and detached settings cases).
Both names/roles are confirmed in the current
production controls. Only the test selectors changed; no production semantics,
app behavior or assertions were relaxed. Focus permission and audit failures stay
separate from these test defects. Fresh isolated reruns of all three corrected journeys pass (exit 0, one test each,
zero skipped): pattern create/edit/reopen, live Settings choices and detached-window
Settings/reveal behavior. Evidence is under
`output/a11y/release-focused-final-20261019/TEST_NAME/`, with `ledger.json`,
per-case `runtime.log`, `summary.json` and `results.xcresult`. The corrected tests
retain the original behavioral assertions; only roles/names were updated.

The full native run exits 1: **10 tests passed, 7 failed, 1 skipped**. Its default
visible-editor audit attaches **36 observations**; these remain failures needing
triage, not 36 certified standards violations. The focus test skips because the
ad-hoc runner lacks Accessibility permission. Real VoiceOver smoke also fails to
reach both canvas and a core control within 45 moves; transcript is retained.
Other failures include the unexpected exposed `rectangle.3.group` image and usage
journeys (one cannot hit Pattern host after detached workspace state; its successor
then sees retained state). State interference is a hypothesis requiring isolated
reruns, not grounds for declaring these product passes.

A first focused preparation omitted its document directories; the affected tests
failed in setup before app behavior. Directories were created before continuing;
those setup-only results are preserved and are not counted as product failures.
The first coordinator also stopped when it encountered a precreated output folder;
no additional product result was inferred. Corrected fresh preparation uses
`output/a11y/release-focused-final-20261019/`, with separate identity and document
folder per test. The corrected build log is
`/tmp/exp-v27-readiness-native-selector-build-20261019.log` (exit 0).


## Final clean-start audit

The corrected focused ledger finishes with **four passes, one failed audit, zero
skips**. The four passing cases are all three repaired journeys and the unchanged
universal-name/decorative-image check. The latter passes in a new identity; its
full-suite failure therefore remains a state/context investigation, not a reproduced
default-editor labeling defect.

The separate clean-start audit retains **31 observations**: 11 missing descriptions,
five missing actions, 12 contrast failures, two near-threshold contrast findings
and one parent/child mismatch. They are not suppressed or automatically certified
as standards violations. Evidence and full subtrees:
`output/a11y/release-focused-final-20261019/testVisibleEditorAccessibilityAudit/`
(`findings.md`, `findings.json`, `attachments/`, `summary.json`, `results.xcresult`).
`ledger.json` in the parent records every exit. The audit exits 65 with one failed
test and no skips. This is a release-verification failure, not an unsigned build
failure. Real VoiceOver and the full display/keyboard review remain unresolved.

Triage order remains BUG-069: visible title/extension, Export/Package/helper/Grid
text contrast, then real MenuButton/PopUpButton actions and names. Disabled
container/TouchBar observations require context before changing semantics. Human
reader/task evidence is required before classifying any as platform false positives.
No production UI was changed to silence this audit.

## October 19 remaining order (superseded by October 20 addendum)

1. Finish native accessibility triage (BUG-069), actual VoiceOver/FKA and the full
   appearance/1x/2x/Large interface review. BUG-070's complete panel-fit matrix
   remains part of that review. Preserve any failures as failures.
2. Finish source-library/component combinations and the marketed
   create/import→edit→save/reopen→export task. Use permitted real Figma content
   for its live import gate. Pattern seams/scale/SVG functional reviews are accepted.
3. Complete the release checklist's ownership, notices, policy and first-use
   evidence. Optional member-hub rollout, analytics enablement and payments retain
   their own gates; a native update does not enable them.
4. Freeze the accepted source, then create the signed universal archive and run
   the signed font/release-candidate checks. Notarize, staple and verify a clean ZIP
   round trip; retain hash, byte length and immutable historical releases.
5. Obtain publication authorization for the concrete package. Publish its download
   before the appcast, preserve historical feed entries and disable deltas. Owner
   verifies real v2.6→v2.7 update/relaunch and settings/documents continuity.

Release notes are updated at `RELEASE-NOTES-v2.7.md` and remain a development draft.
No new feature is proposed to fill this queue; the next work is verification and
bounded correction of demonstrated release blockers.
