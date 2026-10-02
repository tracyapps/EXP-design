# EXP [design] v2.6 / build 17 release checklist

Owner scope/acceptance, 2026-10-01: “excellent. all work great to me” and explicit
request to make this a small release, update the roadmap page, package v2.6, and
prepare the next development version. This closes the convenience bundle gate;
previous Knife/Unite and full-wall performance acceptances remain recorded.

Public v2.5/build 16 and older shipping artifacts are immutable. No appcast item
for build 17 is deployed before its signed, notarized download exists.

## Canonical values

- Source: `/Users/tapps/_dev/apps/exp-design/EXP [design]`
- Release: **2.6 / 17**, macOS 26.2+, universal arm64/x86_64
- Archive: `/Users/tapps/Library/Developer/Xcode/Archives/2026-10-01/EXP design v2.6.xcarchive`
- Export/app/ZIP: `/Users/tapps/_dev/apps/exp-design/releases/v2.6/`
- ZIP: `EXP-design-v2.6.zip`
- Sparkle: `/Users/tapps/_dev/apps/exp-design/sparkle-releases/`
- Next development identity: **2.7 / 18**; scope remains owner-selected.

## Accepted scope

- [x] PERF-009/010/011/012: bulk artwork editing and complex-wall rendering.
- [x] FEAT-066/067: freehand Knife, straight-line preview, mask/image cuts,
      target/scope controls and nested-folder Unite.
- [x] PERF-005: independent ruler pointer markers.
- [x] FEAT-068: independent Effects / Style / Style & Effects clipboards and
      ⇧⌘C/V / ⌥⌘C/V / ⌥⇧⌘C/V shortcuts.
- [x] FEAT-034 remaining font surface: named type-style save from Properties.
- [x] FEAT-019: notes export as GFM task lists.
- [x] Release notes describe the scope and limits; owner authorizes release.

Owner acceptance is recorded at face value. No formal VoiceOver/FKA, appearance
matrix, or every ancillary stress-document scenario is inferred from that statement.
Native AX names/command paths and source regression receipts remain the evidence
for these changes. ARIA export contracts are unchanged and retested below.

## Freeze and verification

- [x] Fresh release regression battery (21 checks) and website build pass.
- [x] App, extension and runtime configuration values agree at 2.6/17.
- [x] Source/notes/checklist frozen in the release source commit before archive;
      reviewed intended changes and excluded `.zcodeignore`.
- [x] Signed universal Release archive passes `verify_release_candidate.sh --local`.

The owner-created `.zcodeignore` remains an unrelated local file; it is not part
of the shipping source commit. Test documents/apps under `/tmp` are not shipped.

## Notarization and immutable packaging

- [x] Developer ID app exported/notarized through Xcode Direct Distribution.
- [x] Export passes strict signatures, entitlements, Gatekeeper and staple checks.
- [x] Clean-copy ZIP and unzip round trip pass every release-candidate check.
- [x] SHA-256 receipt recorded; older ZIPs unchanged.

Canonical checks:

```sh
scripts/verify_release_candidate.sh --local "ARCHIVE/Products/Applications/EXP [design].app" 2.6 17
scripts/verify_release_candidate.sh "EXPORT/EXP [design].app" 2.6 17
scripts/generate_sparkle_appcast.sh 2.6 17 "/Users/tapps/_dev/apps/exp-design/releases/v2.6/EXP-design-v2.6.zip"
scripts/verify_sparkle_setup.sh 2.6 17
```

## Publish and website

- [x] Appcast generated from final ZIP bytes, EdDSA signature/size/build verified.
- [ ] Release source/tag `v2.6` identifies build 17.
- [ ] GitHub ZIP uploaded before the appcast-bearing production push.
- [ ] Downloaded GitHub asset is byte-identical to the local immutable ZIP.
- [ ] Public roadmap/download content reflects v2.6, completed tools and future queue.
- [ ] Production build/deployment and live appcast/notes/asset checks pass.

## Post-publication update proof

- [ ] Owner tests the live v2.5 → v2.6 Sparkle update, install and relaunch.
- [ ] Updated installation reads 2.6/17 and passes the release-candidate checks.

This requires the owner's running installed app. Do not replace or quit that app
for a release proof without a specific request; publishing is distinct from this
post-publication check.

## Next development cycle

- [ ] After freezing the 2.6 artifact, set every development config to 2.7/18.
- [ ] ROADMAP, AGENTS and CLAUDE identify the public release and open development
      cycle consistently; deferred candidates preserved, no new scope invented.
- [ ] Development baseline build and version/Sparkle checks pass; changes committed.
- [ ] Immutable release tag/app/ZIP and public version continue to read 2.6/17.

## Receipts

Preparation started 2026-10-01; unchecked items are not completion claims.

- All 21 source regression checks pass: backlog IDs, nested components, anchored
  relationships, canvas pages, XD/Figma, semantic HTML contract/package, SVG
  pattern/token import, effect export, CodePen, rendered HTML model/WebKit,
  Storybook, appearance style, ruler overlay, vector editing, node-tree/canvas-path
  performance and pattern-raster pixel/performance checks. Logs:
  `/tmp/exp-v26-regressions/`; results: `results.json` in that folder.
  The pattern check requires `/tmp/exp-wall-verification.design`; the first
  no-argument invocation failed for the missing fixture, and the corrected
  invocation passed with maximum pixel drift within 4/255.
- Website build passes: `/tmp/exp-v26-website-build.log`.
- `verify_sparkle_setup.sh 2.6 17` passes; build 17 is intentionally absent from
  the appcast until notarized ZIP creation.

- Archive succeeded from source commit `95557b1d12f2aba3e458e1a5b820367a34ecd995`;
  `verify_release_candidate.sh --local` passes all 16 pre-notarization checks.
  Logs: `/tmp/exp-v26-archive.log` and `/tmp/exp-v26-archive-check.log`.
- First Apple notarization upload rejected before submission (2026-10-01):
  HTTP 403, “A required agreement is missing or has expired.” Owner must review
  and accept the pending Apple Developer agreement; no agreement accepted by the
  agent, and no build-17 appcast or public release published while blocked.
  Log: `/tmp/exp-v26-notary-upload.log`.
- Developer ID export succeeds without account changes and passes all 16 local
  checks: `/tmp/exp-v26-developer-id-export/EXP [design].app`, signed by
  `Developer ID Application: tracy apps (65LD7TZAL3)` with hardened runtime.
  This is a preparation copy, not a notarized shipping artifact; logs:
  `/tmp/exp-v26-developer-id-export.log`, `/tmp/exp-v26-developer-id-check.log`.
- Manual-signing upload also receives the same Apple agreement HTTP 403:
  `/tmp/exp-v26-manual-notary-upload.log`. The signed preparation app is preserved
  at `/Users/tapps/_dev/apps/exp-design/releases/v2.6/pre-notarization/EXP [design].app`;
  its fresh local check passes. Durable receipts and status:
  `/Users/tapps/_dev/apps/exp-design/releases/v2.6/receipts/` and `README.md`.
  No shipping ZIP/feed/tag/release/deployment exists yet. Development remains
  2.6/17 so release helpers stay consistent; the accepted 2.7/18 transition
  follows notarization and final-byte freeze.

### Agreement cleared; notarization and packaging complete — 2026-10-01

- Owner accepted the pending Apple agreement; retry upload succeeds through
  Xcode's Developer ID distribution (`/tmp/exp-v26-notary-retry.log`). Xcode
  distribution record: `3707DC6A-27F5-4F87-BC75-AB124BDA4BA5`.
- The first notarized-export attempt hit a transient Apple account service
  timeout. Retry succeeds (`/tmp/exp-v26-notarized-export-retry.log`). Export,
  clean copy and ZIP round trip each pass every production release check,
  including Gatekeeper `Notarized Developer ID` and valid staple.
- Immutable ZIP: **32,709,986 bytes**; SHA-256:
  `7300281745f65d69445ded900e002e2dab56caf9a81753bab19ce6e24e5db468`.
  Prior v2.5 ZIP SHA-256 still equals its recorded baseline.
- Feed EdDSA independently verifies against `SUPublicEDKey` in the shipped app;
  size, build 17, version 2.6, GitHub asset URL and notes URL agree. All three
  prior appcast enclosures/versions/notes links remain identical. The generator's
  default three-version pruning was caught before publication; added
  `--maximum-versions 0` and regenerated from the preserved feed.
- Durable logs/check results are in `../releases/v2.6/receipts/`. The retained
  `pre-notarization/` app is historical preparation; the root app and ZIP are
  the notarized shipping artifact.
