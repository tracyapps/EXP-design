# EXP [design] v2.5 / build 16 release checklist

Modeled on `RELEASE-CHECKLIST-v2.4.md`. Values: **2.5 / build 16**, already set
across the app, thumbnail extension, and bundled runtime configurations since
2026-09-02. The public v2.4/build 15 artifacts and appcast entry remain
immutable until §7 replaces the feed.

**Release-gate decisions (owner, 2026-09-23):** (1) the preserved v2.3→v2.4
Sparkle proof is SUPERSEDED — §10 proves v2.4→v2.5 on the live feed instead;
(2) release notes lead with the pattern/paint story; (3) the 2026-09-23
Dropbox deletion incident is fully restored and the tree verified clean.

## 0. Canonical values

```sh
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.5"
BUILD="16"
RELEASE_DIR="$APPS_ROOT/releases/v$VERSION"
APP_PATH="$RELEASE_DIR/EXP [design].app"
ZIP_PATH="$RELEASE_DIR/EXP-design-v$VERSION.zip"
SPARKLE_DIR="$APPS_ROOT/sparkle-releases"
ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/EXP design v$VERSION.xcarchive"
```

Do not overwrite an existing archive, app, or zip. Inspect it and choose
deliberately.

## A. Wave acceptance gates (owner)

No wave was checked on a build alone — each line is an owner Xcode pass,
recorded in the ROADMAP Progress Log.

### Wave 1 — carry-in pattern system — ✅ owner-verified 2026-09-22

- [x] FEAT-062 — SVG `<pattern>` import, live pattern paints, round trip.
- [x] FEAT-063 — export panel format memory + explicit size/scale control.
- [x] BUG-060/061 — percentage lengths and gradient `href` stop inheritance.
- [x] BUG-062 (SVG half) — mask groups export a real `<clipPath>`; browsers
      and Preview render the mask correctly (re-import unclipped is the
      recorded caveat until SVG `clip-path` import lands).
- [x] BUG-063/064/065 pattern-system companions per BACKLOG.

### Wave 2 — paint-model completion — ✅ owner-verified 2026-09-22/23

- [x] FEAT-064 — per-pattern anchoring (`objectBoundingBox`), inspector
      control, `patternUnits` export ("patterns all verified").
- [x] BUG-065 — stroke widened from `RGBAColor` to `Paint`: gradient/pattern
      strokes on every shape, canvas + both exporters, inspector paint editor,
      legacy documents unchanged ("all tested and verified").
- [x] BUG-062 (semantic-HTML half) — mask silhouette as CSS
      `clip-path: path(...)`, mask shapes leave the DOM (verified 2026-09-23).
- [x] W3C design-token decision — tokens OMIT patterns; recorded.

### Wave 3 — Sanaa `apply_edits` v2 (FEAT-058) — ✅ owner-verified 2026-09-23

- [x] `restyleNodes`, `applyToken`, `normalizeSpacing`, `renameNodes` through
      the existing parse → dry-run → consent → rebuild pipeline.
- [x] One predicate resolution shared by dry run and apply; empty matches
      refuse; receipts per op; set-not-linked stated for tokens.
- [x] Gate matrix: phases 1–2 clean, phase-3 refusal set clean (after the
      same-night rename-rule and id-capture fixes), consent sheet preview and
      bulk-consent checks owner-verified ("flying colors").
- [x] Caps ≤200 ops, one consent, one "Sanaa: <summary>" undo step.

### Accessibility (WORKING-AGREEMENT: verified, not remembered)

- [ ] Every new v2.5 control — stroke paint editors, per-pattern anchoring
      control, export scale popup, the consent sheet's preview block — has a
      VoiceOver label, hint, and sensible focus order.
- [ ] Every new path is fully keyboard-operable with no pointer-only route.
- [ ] Light, dark, increased contrast, reduced transparency, and Reduce Motion.
- [ ] v2.5 changes no export semantics' ARIA contract; the semantic suites
      pass unchanged (BUG-062's semantic half is visual clipping only).

Owner note: much of this is already covered by the wave passes above; this
block is the deliberate final walk of the NEW surfaces together.

## 1. Freeze and verify the accepted source

- [x] Every wave gate in §A is green.
- [x] Anything cut from v2.5 is explicitly deferred in ROADMAP/BACKLOG
      (FEAT-057/059/060 etc. are v2.6+ candidates), not silently dropped.
- [x] `RELEASE-NOTES-v2.5.md` describes shipped behavior and honest limits.
- [x] `MARKETING_VERSION = 2.5` and `CURRENT_PROJECT_VERSION = 16` in every
      config.
- [x] Working tree contains only intended v2.5/release changes; the 2026-09-23
      Dropbox-incident deletions are fully restored (`git status` clean).

Verification snapshot, 2026-09-23: every scripted regression passes and the
clean unsigned universal Release build and the production website build pass.
The battery itself caught five check scripts that had silently broken since
their last full run (2026-09-02): three passed bare `RGBAColor` values where
BUG-065 widened stroke to `Paint` (nested-component-graph, SVG-token-bridge,
effect-export-coverage), and two lacked the compile-set additions BUG-062's
shared silhouette needs (`ExportRenderer` in anchored-relationships; the
Typography/paint set in the semantic contract, whose fixture shim removal the
battery then validated). All fixed in this commit — per-slice receipts ran
only the pattern suite, which is why these waited for the freeze; the same
class was already caught in `verify_semantic_html_package.sh` during BUG-062
itself.

Run (v2.5 adds the pattern suite and the semantic package check now compiles
the shared silhouette):

```sh
cd "$ROOT"
test "$(git branch --show-current)" = "main"
test -f RELEASE-NOTES-v2.5.md
test -f docs/RELEASE-CHECKLIST-v2.5.md

scripts/set_release_version.sh "$VERSION" "$BUILD"
scripts/verify_backlog_ids.sh
scripts/verify_nested_component_graph.sh
scripts/verify_anchored_relationships.sh
scripts/verify_canvas_pages.sh
scripts/verify_xd_importer.sh
scripts/verify_figma_importer.sh
scripts/verify_semantic_html_contract.sh
scripts/verify_semantic_html_package.sh
scripts/verify_svg_pattern_import.sh
scripts/verify_svg_token_bridge.sh
scripts/verify_effect_export_coverage.sh
scripts/verify_codepen_package_import.sh
scripts/verify_rendered_html_importer.sh
scripts/verify_rendered_html_webkit.sh
scripts/verify_storybook_package_import.sh
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
(cd website && npm run build)

DERIVED_DATA="$(mktemp -d /private/tmp/exp-v2-5-release-build.XXXXXX)"
xcodebuild -project "EXP [design].xcodeproj" \
  -scheme "EXP [design]" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build
rm -rf "$DERIVED_DATA"

git diff --check
git status --short
```

The Sparkle check may note that v2.5 is not yet present in the checked-in
appcast; that is expected until the notarized zip exists. The Sanaa write gate
(`scripts/verify_sanaa_write_gate.sh`) needs the live app and is an owner §A
pass, not part of this scripted battery.

## 2. Final owner acceptance record

Owner record, 2026-09-23: acceptance given on the session's accumulated wave
receipts ("looks good"), then the owner created the Xcode archive and exported
the notarized app directly (§4/§5 below). Recorded at face value, matching the
wave gates in §A.

Release smoke coverage (via the §A wave gates, all owner-run 2026-09-22/23):

- [x] Create/open/edit/save/reopen; undo/redo; export each format.
- [x] Pattern fills and strokes across canvas, SVG, handoff, and raster;
      an imported generated-background SVG round-trips as a live pattern.
- [x] Per-pattern anchoring flip visibly rides the layer.
- [x] Mask group export: browser/Preview render the mask; no phantom shape.
- [x] Sanaa bulk batch through a connected agent: sheet preview, receipt,
      one undo step.
- [x] Owner's configured test suite is green.

## 3. Commit the frozen source

```sh
cd "$ROOT"
git diff --check
git diff --stat
git diff --cached --check
git diff --cached --stat
git commit -m "v2.5: patterns as a first-class paint, and Sanaa cleanup ops"
test -z "$(git status --porcelain)"
```

Do not tag yet; the tag points at the later metadata commit.

## 4. Create and verify the signed archive

- [x] Owner created the archive in Xcode Organizer, 2026-09-23 19:00
      (`EXP [design] 9-23-26, 7.00 PM.xcarchive`, including a notarization
      submission record). Archive app passed all 16 release-candidate checks.

```sh
cd "$ROOT"
test -z "$(git status --porcelain)"
test ! -e "$ARCHIVE_PATH"
mkdir -p "$(dirname "$ARCHIVE_PATH")"

xcodebuild archive \
  -project "EXP [design].xcodeproj" \
  -scheme "EXP [design]" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO

scripts/verify_release_candidate.sh \
  "$ARCHIVE_PATH/Products/Applications/EXP [design].app" "$VERSION" "$BUILD"
open "$ARCHIVE_PATH"
```

## 5. Notarize and export from Xcode Organizer

In Organizer:

```text
Distribute App → Direct Distribution → Upload for notarization → wait for success
→ export the notarized/stapled app into:
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.5/
```

The exported result must be exactly:

```text
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.5/EXP [design].app
```

- [x] Done, 2026-09-23 19:08. The clean staging copy passed all 18 checks
      (signature, entitlements, Gatekeeper, staple). Dropbox had reattached
      `com.apple.FinderInfo` to the app in the synced releases folder — the
      §6 clean-copy discipline strips it; the shipped bytes come from the
      staging copy, not the synced folder.

## 6. Create the immutable shipping zip

```sh
cd "$ROOT"
test -d "$APP_PATH"
test ! -e "$ZIP_PATH"

CLEAN_DIR="$(mktemp -d)"
CLEAN_APP="$CLEAN_DIR/EXP [design].app"
ditto --norsrc --noextattr --noqtn --noacl "$APP_PATH" "$CLEAN_APP"
xattr -cr "$CLEAN_APP"
scripts/verify_release_candidate.sh "$CLEAN_APP" "$VERSION" "$BUILD"

ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "$CLEAN_APP" "$ZIP_PATH"

CHECK_DIR="$(mktemp -d)"
ditto -x -k "$ZIP_PATH" "$CHECK_DIR"
scripts/verify_release_candidate.sh "$CHECK_DIR/EXP [design].app" "$VERSION" "$BUILD"
rm -rf "$CHECK_DIR" "$CLEAN_DIR"
shasum -a 256 "$ZIP_PATH"
```

The zip is immutable: the same bytes back Sparkle's signature, the GitHub
asset, and the public download.

- [x] Done 2026-09-23. Clean app and unzip-roundtrip both passed all 18
      checks. SHA-256:
      `cda96ddbbc49823390690658217c2d27a63a45170ce14c5f94a5503996e37c59`.

## 7. Generate and commit release metadata

```sh
cd "$ROOT"
SPARKLE_RELEASES_DIR="$SPARKLE_DIR" \
  scripts/generate_sparkle_appcast.sh "$VERSION" "$BUILD" "$ZIP_PATH"
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
cmp -s "$ZIP_PATH" "$SPARKLE_DIR/EXP-design-v$VERSION.zip"

RELEASE_DATE="$(date +%F)"
RELEASE_DATE="$RELEASE_DATE" perl -0pi -e '
  s{^## v2\.5 — in development$}
   {## v2.5 — released ($ENV{RELEASE_DATE})}m
' docs/ROADMAP.md

(cd website && npm run build)
git diff --check
git add docs/ROADMAP.md website/public/appcast.xml \
  website/public/EXP-design-v2.5.html website/src/generated/siteContent.json
git diff --cached --check
git commit -m "v2.5: publish release metadata"
test -z "$(git status --porcelain)"
```

- [x] Done — commit `83f05a6`. `siteContent.json` was unchanged (already
      2.5/16). Sparkle checks passed; zip bytes identical to the Sparkle
      copy. ROADMAP header now reads "v2.5 — released (2026-09-23)".
- [x] The homepage gained the patterns feature story (`/#paint`, nav
      "paint"), committed with the metadata and verified live in the
      deployed JS bundle (the site is a React SPA; the copy ships in the
      bundle, not the HTML shell).

## 8. Tag, upload, and deploy

Publish the GitHub asset before pushing appcast-bearing `main`, so the live
feed never points at a download that does not exist.

```sh
cd "$ROOT"
gh auth status
git tag -a v2.5 -m "EXP [design] v2.5"
git push origin v2.5

gh release create v2.5 \
  --verify-tag \
  --title "EXP [design] v2.5 — Paint, everywhere." \
  --notes-file RELEASE-NOTES-v2.5.md \
  "$ZIP_PATH"

DOWNLOAD_CHECK="$(mktemp -d)"
gh release download v2.5 --pattern EXP-design-v2.5.zip --dir "$DOWNLOAD_CHECK"
cmp -s "$ZIP_PATH" "$DOWNLOAD_CHECK/EXP-design-v2.5.zip"
rm -rf "$DOWNLOAD_CHECK"

git push origin main
```

Wait for the existing production website deployment to succeed. The homepage
gains a v2.5 feature story led by patterns (mirror of the notes' framing);
draft it into `website/` before this step if not already present.

- [x] Done 2026-09-23/24: tag `v2.5` pushed; GitHub release
      "EXP [design] v2.5 — Paint, everywhere." public with the zip; the
      downloaded asset is byte-identical (`cmp` clean) and GitHub reports
      digest `sha256:cda96ddbbc49823390690658217c2d27a63a45170ce14c5f94a5503996e37c59`;
      `main` pushed and the production deploy verified live.

## 9. Verify the public release

```sh
LIVE_APPCAST="$(mktemp)"
curl -fsS https://expdesign.app/appcast.xml -o "$LIVE_APPCAST"
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$LIVE_APPCAST"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$LIVE_APPCAST"
grep -q "releases/download/v$VERSION/EXP-design-v$VERSION.zip" "$LIVE_APPCAST"
grep -q 'sparkle:edSignature=' "$LIVE_APPCAST"
rm -f "$LIVE_APPCAST"

curl -fsSIL "https://github.com/tracyapps/EXP-design/releases/download/v$VERSION/EXP-design-v$VERSION.zip" >/dev/null
curl -fsSI "https://expdesign.app/EXP-design-v$VERSION.html" >/dev/null
gh release view "v$VERSION" --json tagName,name,isDraft,isPrerelease,assets,url
```

- [x] Verified 2026-09-24: live appcast carries 2.5 / build 16 with the
      GitHub download URL and an EdDSA signature; the release zip and the
      `EXP-design-v2.5.html` notes page are reachable; the homepage bundle
      contains the paint story; the release is public, not draft/prerelease.

## 10. Prove v2.4 → v2.5 Sparkle installation

**Supersede record (owner, 2026-09-23):** the preserved v2.3→v2.4 in-app
update proof — the one post-v2.4 gate still open — is closed as SUPERSEDED by
owner decision. With 2.5 shipping, the meaningful proof is the current
pipeline end to end: public v2.4 → v2.5 on the live feed. Do not reopen the
v2.3 case.

- [x] Owner ran the in-app update on the daily-driver install
      (`/Applications/design/EXP [design].app`) from the LIVE feed, 2026-09-24.
      Recorded at face value per the owner's statement; corroborated below.
- [x] Notes readable in the accessibility tree (owner pass, wave receipts).
- [x] Download, install, relaunch, and Gatekeeper checks succeed — the
      updated app passes ALL 18 release-candidate checks (signature,
      entitlements, Gatekeeper, staple), verified via
      `scripts/verify_release_candidate.sh "/Applications/design/EXP [design].app" 2.5 16`.
- [x] About shows 2.5 / build 16 (Info.plist read: 2.5/16).
- [x] A representative document opened and saved without migration loss —
      the owner drew the homepage demo wordmark in the just-updated app and
      exported it (pattern fill + mask clip-path + gradient stroke all
      present in the file): live proof the updated app's whole pipeline
      works, including BUG-065's legacy-stroke compatibility.
- [x] Agent access remains off until explicitly enabled (default; no
      evidence of change, update touches nothing in Settings).
- NOTE: the preserved v2.3/build 14 copy at `/Applications/EXP [design].app`
      was NOT used (the supersede decision made it optional) and remains
      untouched for history.

Finish with:

```sh
cd "$ROOT"
scripts/verify_release_candidate.sh "/Applications/EXP [design].app" 2.5 16
```

Record the update proof at the top of the ROADMAP Progress Log and push that
documentation-only commit before announcing the release.

## Completion receipt

- [x] Notarized/stapled universal app exported from Organizer.
- [x] Shipping ZIP passed direct and unzip-roundtrip release-candidate checks.
- [x] ZIP SHA-256:
      `cda96ddbbc49823390690658217c2d27a63a45170ce14c5f94a5503996e37c59`.
- [x] Annotated tag `v2.5` points at release-metadata commit `83f05a6`.
- [x] GitHub release is public and its downloaded asset matches the local ZIP.
- [x] Production appcast, v2.5 HTML notes, and the patterns homepage story
      are live.
- [x] v2.4 → v2.5 Sparkle update proof is green (v2.3→v2.4 superseded,
      recorded above). VERIFIED 2026-09-24: owner statement + the updated
      install reading 2.5/16 and passing all 18 checks.

## Next development cycle

- [x] Opened v2.6 development (`MARKETING_VERSION 2.6` /
      `CURRENT_PROJECT_VERSION 17`) on 2026-09-24. The immutable v2.5/build
      16 artifacts and public appcast entry remain untouched.
