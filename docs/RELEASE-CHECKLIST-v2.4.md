# EXP [design] v2.4 / build 15 release checklist

The exact path from the owner-accepted v2.4 source to the public GitHub,
Sparkle, and website release. Stop at the first failure; never tag, upload, or
deploy around a failed gate. This follows the proven v2.4 release path.

Release artifacts stay outside the repository in `../releases/` and
`../sparkle-releases/`. Keep Dropbox syncing paused while the signed archive,
shipping zip, and appcast are generated.

## 0. Canonical values

```sh
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.4"
BUILD="15"
RELEASE_DIR="$APPS_ROOT/releases/v$VERSION"
APP_PATH="$RELEASE_DIR/EXP [design].app"
ZIP_PATH="$RELEASE_DIR/EXP-design-v$VERSION.zip"
SPARKLE_DIR="$APPS_ROOT/sparkle-releases"
ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/EXP design v$VERSION.xcarchive"
```

Do not overwrite an existing archive, app, or zip. Inspect it and choose
deliberately.

## A. Wave acceptance gates (owner)

v2.4 is a large release (ROADMAP → v2.4). No wave starts while the previous
wave awaits verification, and no wave is checked here on a build alone — each
line is an owner Xcode pass, not an agent claim.

### Wave A — carry-in slice (committed `a803df0`)

- [ ] BUG-049 — point-edit bounds, hit-testing, and shadow paint bounds.
- [ ] BUG-050 — immediate arrow nudge from Layers, docked and floating.
- [ ] BUG-051 — tray palette ordering across displays, both activation routes.
- [ ] BUG-052 — Reveal in Layers / Expand · Collapse All against the live panel.
- [ ] FEAT-047 — Auto-select on and off, including buried-layer drag and undo.
- [ ] FEAT-027 — recursive Convert to Outlines / Convert to Path / Outline Stroke.

### Wave B — Sanaa core

- [ ] FEAT-048 — socket create/undo, the full gate matrix, and a real-client batch
      that saves, reopens, and exports identically to hand-drawn content.
- [ ] FEAT-048 — with Sanaa disabled, EXP shows no trace of it anywhere.
- [ ] FEAT-049 — feed order, highlights, announcements, Reduce Motion variant.
- [ ] FEAT-050 — placement sheets, enablement matrix, keyboard and VoiceOver.

### Wave C — vector toolset, and the export fidelity bug

Run `docs/EXPORT-FIDELITY-TEST-FIXTURES.md` first — it is self-contained and needs
no code change. Both entries below are unfixed and unverified as of 2026-08-25.

- [ ] BUG-053 — Fixture A run; `noise` and `dissolve` render in PNG, JPG, and PDF
      as they do on canvas and in SVG. The hard-edged dark rectangle in the owner's
      original file is accounted for, not just gone.
- [ ] BUG-054 — Fixture B run; a blur renders at the same model-space radius on
      canvas at every zoom and in export at every scale, and an unrenderable blur
      degrades in resolution rather than in radius, never silently.

- [x] FEAT-025 — owner verified 2026-08-25 (core behaviour + the flagged
      select-and-drag change). Regression items below not separately walked.
- [ ] FEAT-025 regression — direct-select moves whole objects in one undo step; anchors and
      handles still win; Option-drag, snapping, nested and rotated ancestors, locked
      objects, and click-without-drag all still behave. BUG-028 is NOT claimed fixed.
      Look hard at the changed behaviour: pressing a DIFFERENT object now selects
      AND drags in one gesture.
- [x] FEAT-029 — owner verified 2026-08-25 (drawing, corners, fast strokes, live
      preview). Export/reopen/group/rotation checks below NOT walked.
- [ ] FEAT-029 regression — pencil output is an ordinary, fully point-editable path; anchor
      count is sane; the fidelity slider makes an obvious difference at both ends;
      one stroke is one undo step; a click leaves nothing behind. Watch the
      proximity close (12pt / 8 samples) — most likely thing to feel wrong.
- [ ] FEAT-028 — canvas, PNG, PDF, SVG, and HTML/CSS handoff all agree, with the
      browser-support caveat stated in the export contract rather than implied.
      Check both alignments at several weights; confirm Convert to Outlines
      preserves the appearance (NOT implemented yet); open the HTML in a browser
      older than Chrome 123 if one is to hand, or accept the caveat as stated.
- [ ] FEAT-031 — per-point line ends round-trip through save and SVG export.
- [ ] FEAT-030 — balanced/smooth/corner conversion, undoable, anchor does not move.
- [ ] BUG-048 — placed SVG dash patterns import as the authored pattern.
- [ ] BUG-034 Stage 2 — canvas spread matches SVG export; the Stage 1 disclosure
      note is removed only where it has genuinely stopped being true.

### Wave D — Sanaa companion

- [ ] FEAT-051 — fresh-account walkthroughs (Desktop only / Code only / neither).
- [ ] FEAT-052 — avatar states, zero trace when off, no frame-time regression.
- [ ] FEAT-053 — a cold real-agent session scores clean against the etiquette list.

### Accessibility (WORKING-AGREEMENT: verified, not remembered)

- [ ] Every new control has a VoiceOver label, hint, and sensible focus order.
- [ ] Every new command is fully keyboard-operable with no pointer-only path.
- [ ] Light, dark, increased contrast, reduced transparency, and Reduce Motion.
- [ ] Any export-semantics change re-verifies the ARIA/WCAG contract in full.

## 1. Freeze and verify the accepted source

- [ ] Every wave gate in §A below is green.
- [ ] Anything cut from v2.4 is explicitly deferred in ROADMAP/BACKLOG, not silently dropped.
- [ ] `RELEASE-NOTES-v2.4.md` describes shipped behavior and honest limits.
- [ ] `MARKETING_VERSION = 2.4` and `CURRENT_PROJECT_VERSION = 15` in every config.
- [ ] Working tree contains only intended v2.4/release changes.

Run:

```sh
cd "$ROOT"
test "$(git branch --show-current)" = "main"
test -f RELEASE-NOTES-v2.4.md
test -f docs/RELEASE-CHECKLIST-v2.4.md

scripts/set_release_version.sh 2.3 14
scripts/verify_backlog_ids.sh
scripts/verify_nested_component_graph.sh
scripts/verify_anchored_relationships.sh
scripts/verify_canvas_pages.sh
scripts/verify_xd_importer.sh
scripts/verify_figma_importer.sh
scripts/verify_semantic_html_contract.sh
scripts/verify_semantic_html_package.sh
scripts/verify_svg_token_bridge.sh
scripts/verify_codepen_package_import.sh
scripts/verify_rendered_html_importer.sh
scripts/verify_rendered_html_webkit.sh
scripts/verify_storybook_package_import.sh
scripts/verify_sparkle_setup.sh 2.3 14
(cd website && npm run build)

DERIVED_DATA="$(mktemp -d /private/tmp/exp-v2-3-release-build.XXXXXX)"
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

The Sparkle check may note that v2.4 is not yet present in the checked-in
appcast; that is expected until the notarized zip exists.

## 2. Final owner acceptance record

The owner's acceptance record for v2.4 goes here at release time: which
wave gates in §A were run, on what date, and anything that was NOT verified.
Do not carry a previous release's narrative forward.

Release smoke coverage:

- [ ] Create/open/edit/save/reopen, pan/zoom/select/move/resize, undo/redo/export.
- [ ] Workspace presets and connected-panel glue/pop-apart across displays.
- [ ] Font search/filters/height, text memory, keyboard, and VoiceOver.
- [ ] Line caps/markers and SVG browser rendering.
- [ ] Gradient endpoints/stops, selected-stop and Inspector-angle sync.
- [ ] Compact/Standard/Large type, contrast, Case, tooltips, effect disclosures.
- [ ] Owner's configured test suite is green.

## 3. Commit the frozen source

Review every staged path. The source commit must include release notes and this
checklist, but not generated appcast metadata (that comes after notarization).

```sh
cd "$ROOT"
git diff --check
git diff --stat
# Stage the reviewed v2.4 paths explicitly.
git diff --cached --check
git diff --cached --stat
git commit -m "v2.4: polish the everyday design workflow"
test -z "$(git status --porcelain)"
```

Do not tag yet; the tag points at the later metadata commit.

## 4. Create and verify the signed archive

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
  CODE_SIGN_STYLE=Automatic

scripts/verify_release_candidate.sh --local \
  "$ARCHIVE_PATH/Products/Applications/EXP [design].app" 2.3 14
open "$ARCHIVE_PATH"
```

## 5. Notarize and export from Xcode Organizer

In Organizer:

```text
Distribute App → Direct Distribution → Upload for notarization → wait for success
→ export the notarized/stapled app into:
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.4/
```

The exported result must be exactly:

```text
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.4/EXP [design].app
```

## 6. Create the immutable shipping zip

```sh
cd "$ROOT"
test -d "$APP_PATH"
test ! -e "$ZIP_PATH"

CLEAN_DIR="$(mktemp -d)"
CLEAN_APP="$CLEAN_DIR/EXP [design].app"
ditto --norsrc --noextattr --noqtn --noacl "$APP_PATH" "$CLEAN_APP"
xattr -cr "$CLEAN_APP"
scripts/verify_release_candidate.sh "$CLEAN_APP" 2.3 14

ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "$CLEAN_APP" "$ZIP_PATH"

CHECK_DIR="$(mktemp -d)"
ditto -x -k "$ZIP_PATH" "$CHECK_DIR"
scripts/verify_release_candidate.sh "$CHECK_DIR/EXP [design].app" 2.3 14
rm -rf "$CHECK_DIR" "$CLEAN_DIR"
shasum -a 256 "$ZIP_PATH"
```

The zip is immutable: the same bytes back Sparkle's signature, the GitHub asset,
and the public download.

## 7. Generate and commit release metadata

```sh
cd "$ROOT"
SPARKLE_RELEASES_DIR="$SPARKLE_DIR" \
  scripts/generate_sparkle_appcast.sh 2.3 14 "$ZIP_PATH"
scripts/verify_sparkle_setup.sh 2.3 14
cmp -s "$ZIP_PATH" "$SPARKLE_DIR/EXP-design-v2.4.zip"

RELEASE_DATE="$(date +%F)"
RELEASE_DATE="$RELEASE_DATE" perl -0pi -e '
  s{^## v2\.3 — feature complete; release preparation$}
   {## v2.4 — released ($ENV{RELEASE_DATE})}m
' docs/ROADMAP.md

(cd website && npm run build)
git diff --check
git add docs/ROADMAP.md website/public/appcast.xml \
  website/public/EXP-design-v2.4.html website/src/generated/siteContent.json
git diff --cached --check
git commit -m "v2.4: publish release metadata"
test -z "$(git status --porcelain)"
```

## 8. Tag, upload, and deploy

Publish the GitHub asset before pushing appcast-bearing `main`, so the live feed
never points at a download that does not exist.

```sh
cd "$ROOT"
gh auth status
git tag -a v2.4 -m "EXP [design] v2.4"
git push origin v2.4

gh release create v2.4 \
  --verify-tag \
  --title "EXP [design] v2.4 — A faster, calmer everyday canvas." \
  --notes-file RELEASE-NOTES-v2.4.md \
  "$ZIP_PATH"

DOWNLOAD_CHECK="$(mktemp -d)"
gh release download v2.4 --pattern EXP-design-v2.4.zip --dir "$DOWNLOAD_CHECK"
cmp -s "$ZIP_PATH" "$DOWNLOAD_CHECK/EXP-design-v2.4.zip"
rm -rf "$DOWNLOAD_CHECK"

git push origin main
```

Wait for the existing production website deployment to succeed.

## 9. Verify the public release

```sh
LIVE_APPCAST="$(mktemp)"
curl -fsS https://expdesign.app/appcast.xml -o "$LIVE_APPCAST"
grep -q '<sparkle:shortVersionString>2.3</sparkle:shortVersionString>' "$LIVE_APPCAST"
grep -q '<sparkle:version>14</sparkle:version>' "$LIVE_APPCAST"
grep -q 'releases/download/v2.4/EXP-design-v2.4.zip' "$LIVE_APPCAST"
grep -q 'sparkle:edSignature=' "$LIVE_APPCAST"
rm -f "$LIVE_APPCAST"

curl -fsSIL https://github.com/tracyapps/EXP-design/releases/download/v2.4/EXP-design-v2.4.zip >/dev/null
curl -fsSI https://expdesign.app/EXP-design-v2.4.html >/dev/null
gh release view v2.4 --json tagName,name,isDraft,isPrerelease,assets,url
```

## 10. Prove v2.3 → v2.4 Sparkle installation

- [ ] Install preserved public v2.3/build 14 in `/Applications`.
- [ ] Run EXP [design] → Check for Updates… and install v2.4.
- [ ] Notes are readable and exposed as text in the accessibility tree; the owner's
      accepted appearance pass includes Increase Contrast.
- [ ] Download, install, relaunch, and Gatekeeper checks succeed.
- [ ] About shows 2.4 / build 15.
- [ ] A representative v2.3 document opens and saves without migration loss.
- [ ] Agent access remains off until explicitly enabled.

Finish with:

```sh
cd "$ROOT"
scripts/verify_release_candidate.sh "/Applications/EXP [design].app" 2.4 15
```

Record the update proof at the top of the ROADMAP Progress Log and push that
documentation-only commit before announcing the release.

## Completion receipt

- [ ] Notarized/stapled universal app exported from Organizer.
- [ ] Shipping ZIP passed direct and unzip-roundtrip release-candidate checks.
- [ ] ZIP SHA-256 recorded here at release time (do not copy a previous release's hash).
- [ ] Annotated tag `v2.4` points at the release-metadata commit.
- [ ] GitHub release is public and its downloaded asset matches the local ZIP.
- [ ] Production appcast and v2.4 HTML notes are live.
- [ ] Public v2.3 → v2.4 Sparkle update proof is green.

