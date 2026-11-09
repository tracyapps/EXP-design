# EXP [design] v2.8 / build 19 — published; installed update proof pending

**Published November 9, 2026.** Notarized release ZIP, GitHub source tag,
production Sparkle feed, HTML notes and website version are verified live.
Only the owner’s actual v2.7→v2.8 update/install/relaunch gate below remains open;
keep development at 2.8/19 until that result is recorded.

Opened November 9, 2026. The owner accepts the complete latest native test
checklist and saved Design Language color/gradient editing, and requests release
with the crash fixes. Public v2.7 and older artifacts remain immutable.

## Shipping scope and acceptance

- [x] Owner accepts TESTING-v2.8-RELEASE.md on November 9, explicitly including
  package/token import fidelity, multiple shadows, gradients and saved-paint edits.
- [x] Crash repairs: popover focus/lifetime, font/component-state pickers and
  empty paths; paint-editor dismissal and folder eyedropper behavior retained.
- [x] FEAT-082 source tokens/aliases/modes, local-edit retention, export and Undo.
- [x] Saved solid/linear/radial/Mesh paint editing, resizable Settings, sortable
  values, complete copy and long-value clipping; owner accepts latest work.
- [x] BUG-083 shadow stacks and open-shadow-root/slot static capture accepted.
- [x] Opt-in .designpkg hands-on checklist accepted; existing JSON remains JSON,
  and explicit legacy export is compatible with the actual v2.7 model consumer.
- [x] Release notes describe this tested slice. FEAT-083 component contracts,
  FEAT-084 changesets, FEAT-085 full revision refresh and FEAT-087 stay queued.
  No native account/file/settings sync, paid entitlement or hosted enablement.

## Fresh source and recovery verification

- [x] November 9: `bash scripts/check_release_review.sh` exits 0: **14/14 PASS**,
  including importer/shadows/production WebKit, storage/v2.7 compatibility,
  tokens, CEM reader, Handoff/effect exports, Mesh/PDF/SVG, source bounds,
  Debug app/thumbnail build, whitespace and backlog IDs.
  Logs: `output/release-review-checks/run-UZoelb/`; durable summary:
  `../releases/v2.8/receipts/regression-summary.txt`.
- [x] `bash scripts/verify_native_storage_recovery.sh` exits 0, **10 checks**:
  production codec through AppKit NSDocument safe writing, killed disposable
  writers after partial/complete staging, genuine full-volume Save and Autosave,
  successful retry and denied-write retention. Uses only a fresh 64 MB HFS+ disk
  image and temporary files. Receipt: `../releases/v2.8/receipts/storage-recovery.log`.
  This is AppKit/codec fault evidence, not a claim that the SwiftUI application
  was killed or that hardware power failure/cloud sync was simulated. The actual
  SwiftUI package workflow is covered by the owner’s accepted section E.
  [Apple’s safe-writing contract](https://developer.apple.com/documentation/appkit/nsdocument/writesafely(to:oftype:for:))
  informed the probe. No unresolved failure remains in these bounded checks.
- [x] Frozen source commit `17c38baa3fcb2a757cfe033ff91d87122dcb6577` and tag
  `v2.8` match all 145 packaged build-input SHA-256 records. The tag remains
  anchored to this exact source; later documentation receipts may follow on main.
  Durable `source-commit.txt` and `source-build-inputs.json`.
- [x] Final release metadata/website build and whitespace/backlog checks pass.
  `website-final-build.log`: public version 2.8, 52 modules built; gated feature
  summaries advertise only accepted capabilities after the feed advances.

The build uses Swift 5 language mode with Xcode 26.6; it does not establish
strict Swift 6 concurrency conformance. Historical actor-isolation warnings and
accessibility audit observations remain retained. The owner’s earlier Full
Keyboard Access inability to enable macOS’s setting is not silently converted
to an enabled-system pass by the general checklist sign-off.

The owner’s real package save/reopen/Undo/Finder checklist is accepted. Fault
injection is separate from that report. Do not claim measured physical write
reduction, smooth autosave on every document, cloud-sync durability, or power-loss
qualification. PERF-013 remains open for performance measurement and broader
catastrophic recovery qualification. Package storage is explicit and opt-in;
legacy JSON remains the default. Pattern-cache tuning is unchanged and deferred.

## Immutable distribution and publication

- [x] Universal Release archive; app/thumbnail identity 2.8/19 retained.
  Archive: `/Users/tapps/Library/Developer/Xcode/Archives/2026-11-09/EXP design v2.8.xcarchive`.
  `receipts/archive.log`, `archive-check.log`, `archive-extra-checks.json` under
  `../releases/v2.8/` record the pass and four universal executables.
- [x] Signed app/helper/thumbnail/runtime architectures, entitlements, Sparkle
  notices and restricted-font guard pass. `archive-fonts.log` covers the archive,
  built website and design-system tree. All 145 frozen build inputs still match.
- [x] Developer ID export, Apple notarization and staple accepted. Apple upload
  and `xcodebuild -exportNotarizedApp` succeed; `notarized-export-check.log` and
  `clean-app-check.log` pass Gatekeeper/staple/signature checks.
- [x] Clean final ZIP extraction passes production release-candidate checks.
  `EXP-design-v2.8.zip`: **12,180,201 bytes**, SHA-256
  `211d0dab4b72a1f6ceddffee237f337b6d3aaf96102c932e6ae95b7e747b310b`.
  `zip-round-trip-check.log` and `artifact.json` retain receipts; v2.7 ZIP unchanged.
- [x] Sparkle Ed25519 signature independently verifies against the shipped public
  key. Feed version/build/URL/length agree; all five prior updater items are
  semantically unchanged. Receipts: `sparkle-independent-signature.txt` and
  `publication-metadata.json`. Isolated feed staging avoids the stale local
  sparkle-releases folder, which lacked v2.7.
- [x] Source commit/tag and public GitHub release point to the packaged source.
  [v2.8 release](https://github.com/tracyapps/EXP-design/releases/tag/v2.8).
  Both authenticated CLI and unauthenticated public HTTP downloads match the
  immutable ZIP bytes/length/SHA-256. `github-release.json` and
  `published-download-verification.txt` retain receipts. Main fast-forwards to
  the source commit after the asset is available, triggering production deployment.
- [x] Production deployment `dpl_82B6soHSDk9uYEMK2ediCgbumfAu` is READY from
  release commit `17c38ba`, with expdesign.app assigned. Public feed and HTML
  notes match local approved bytes; the live site JS advertises **2.8** (feed build 19).
  `production-deployment.json` and `public-site-verification.json` retain proof.
  Download was available and hash-verified before the feed/main push. Existing
  hosted account service code/configuration and feature enablement are unchanged.
- [ ] Owner completes actual v2.7 → v2.8 Sparkle update/install/relaunch and
  confirms About 2.8/19, preferences/recent documents, document editing/save and
  normal account-free use. This gate requires the owner’s installed-app result.

Do not mark the native release complete until publication evidence and the
owner’s real updater result are recorded. No previous installed app is replaced
or closed by packaging alone.
