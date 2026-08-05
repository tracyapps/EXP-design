# EXP [design] v2.2 / build 13 release checklist

The exact path from the owner-accepted v2.2 source to the public GitHub,
Sparkle, and website release. Run in a fresh Terminal tab, stop at the first
failure, and never tag, upload, or deploy around a failed gate.

Release artifacts stay outside the repository in `../releases/` and
`../sparkle-releases/`. Keep Dropbox syncing paused while the archive, shipping
zip, and appcast are generated.

## 0. Canonical paths

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail

ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.2"
BUILD="13"
RELEASE_DIR="$APPS_ROOT/releases/v$VERSION"
APP_PATH="$RELEASE_DIR/EXP [design].app"
ZIP_PATH="$RELEASE_DIR/EXP-design-v$VERSION.zip"
SPARKLE_DIR="$APPS_ROOT/sparkle-releases"
ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/EXP design v$VERSION.xcarchive"

cd "$ROOT"
mkdir -p "$RELEASE_DIR" "$SPARKLE_DIR" "$(dirname "$ARCHIVE_PATH")"

printf 'root:     %s\narchive:  %s\napp:      %s\nzip:      %s\nappcasts: %s\n' \
  "$ROOT" "$ARCHIVE_PATH" "$APP_PATH" "$ZIP_PATH" "$SPARKLE_DIR"
)
```

Confirm none of the destination paths already contains a v2.2 release candidate.
Do not overwrite an existing archive or zip; inspect it and choose deliberately.

## 1. Freeze the accepted source and public story

- [ ] `RELEASE-NOTES-v2.2.md` describes the shipped behavior and honest limits.
- [ ] `docs/ROADMAP.md` says v2.2 is feature complete and at its release gate.
- [ ] `docs/BACKLOG.md` marks every owner-verified v2.2 bug or feature `done`.
- [ ] `docs/STORYBOOK-COMPATIBILITY-MATRIX.md` contains the five accepted modern
      framework/build rows and their exact receipts.
- [ ] The homepage import/handoff diagram and tester feature feed include local
      HTML/CSS, static Storybook, and both CodePen directions.
- [ ] `MARKETING_VERSION = 2.2`, `CURRENT_PROJECT_VERSION = 13`, and deployment
      target `26.2` are correct for every shipping target.
- [ ] The working tree contains only intended v2.2 and release changes. In
      particular, review local test output, browser automation state, and spike
      artifacts before staging; do not include them merely because they exist.

## 2. Run the deterministic local gate

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
cd "$ROOT"

test "$(git branch --show-current)" = "main"
test -f RELEASE-NOTES-v2.2.md
test -f docs/RELEASE-CHECKLIST-v2.2.md

scripts/set_release_version.sh 2.2 13
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
scripts/verify_sparkle_setup.sh 2.2 13
(cd website && npm run build)

DERIVED_DATA="$(mktemp -d /private/tmp/exp-v2-2-release-build.XXXXXX)"
trap 'rm -rf "$DERIVED_DATA"' EXIT
xcodebuild -project "EXP [design].xcodeproj" \
  -scheme "EXP [design]" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

git diff --check
git status --short
)
```

The unsigned isolated build proves compilation without changing the owner's
signing state. The Sparkle preflight may report that v2.2 is not yet in the
checked-in appcast; that is expected until step 8. Any new compilation, package,
importer, semantic, or website failure is a release stop.

## 2.5 Re-run the real Storybook compatibility matrix

The deterministic Storybook script always runs its synthetic fixture. Before
shipment, also run the five owner-accepted real published builds. Reuse the
receipt-verified fixture directories from acceptance testing when they are still
present, or fetch fresh static artifacts using the bounded fetchers. Never run a
package install or repository build for this gate.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
cd "$ROOT"

VUE_FIXTURE="/private/tmp/exp-gitlab-ui-storybook"
REACT_FIXTURE="/private/tmp/exp-sci-storybook"
ANGULAR_FIXTURE="/private/tmp/exp-dell-angular-storybook"
SVELTE_FIXTURE="/private/tmp/exp-brave-leo-svelte-storybook"
WEB_COMPONENTS_FIXTURE="/private/tmp/exp-kintone-web-components-storybook"

# The GitLab Vue fixture is owner-supplied and is not public. Point VUE_FIXTURE
# at that accepted published build. For the four public rows, either point at
# the accepted directories or fetch their already-generated artifacts first.
test -f "$VUE_FIXTURE/index.json"
test -f "$REACT_FIXTURE/index.json"
test -f "$ANGULAR_FIXTURE/index.json"
test -f "$SVELTE_FIXTURE/index.json"
test -f "$WEB_COMPONENTS_FIXTURE/index.json"

EXP_STORYBOOK_FIXTURE="$VUE_FIXTURE" \
EXP_STORYBOOK_REACT_VITE_FIXTURE="$REACT_FIXTURE" \
EXP_STORYBOOK_ANGULAR_WEBPACK_FIXTURE="$ANGULAR_FIXTURE" \
EXP_STORYBOOK_SVELTE_VITE_FIXTURE="$SVELTE_FIXTURE" \
EXP_STORYBOOK_WEB_COMPONENTS_VITE_FIXTURE="$WEB_COMPONENTS_FIXTURE" \
  scripts/verify_storybook_package_import.sh
)
```

If a published receipt has changed, stop and inspect the new artifact rather
than weakening the pinned expectation during release preparation.

## 3. Final owner acceptance on the Release build

### Core document and canvas smoke test

- [ ] Create, open, edit, save, close, and reopen a `.design` document.
- [ ] Confirm a representative v2.1 document opens without visual or semantic
      migration loss.
- [ ] Pan, zoom, select, move, resize, undo/redo, and export.
- [ ] Create artboards with the Artboard tool; align, distribute, and clean up a
      multi-artboard selection.
- [ ] Confirm page tabs, Layers selection, notes, zoom-to-fit, numeric stepping,
      and gradient-angle editing behave normally.
- [ ] Confirm About shows **2.2 / build 13**.

### Rendered HTML and CodePen

- [ ] Import the hand-written local fixture at Phone and Desktop. Compare the
      media-query differences, edit representative text/paint/SVG, save/reopen,
      then undo the complete import in one step.
- [ ] Import a real Chrome complete-page save and confirm sibling resources are
      used without allowing outside files or external network resources.
- [ ] Confirm normal and explicit line height, fallback-font leading, percentage
      radii, generated content, clipping, masks/icons, and final animation state
      against the accepted visual fixtures.
- [ ] Open the Import Report and verify every known approximation is named and
      copyable; a clean import should not manufacture warnings.
- [ ] Cancel one HTML import and verify the document is unchanged.
- [ ] Send a representative artboard through the CodePen review page, then import
      the resulting CodePen 2.0 ZIP at two viewports.
- [ ] Confirm the ZIP import retains source/config receipts but never executes
      authored `src/`, package-manager, compiler, or build commands.

### Static Storybook

- [ ] Choose a published build, search its catalog, select a bounded story set,
      and import it at Phone and Web 1280.
- [ ] Spot-check one accepted story from Vue, React, Angular, Svelte, and Web
      Components for expected geometry, text, icons/SVG, semantics, and opacity.
- [ ] Confirm portal/modal content, one play-function final state, one collapsed
      overflow case, one generated caret, one CSS-mask icon, and one
      accessibility-only label.
- [ ] Confirm selected viewport height is the minimum canvas, transparent
      previews retain their white browser canvas, and fixed-width story content
      is reported rather than silently made responsive.
- [ ] Inspect Notes/import receipts for story ID, args, framework, builder,
      Storybook version, source path, and consumed-resource hashes.
- [ ] Cancel once and confirm no partial document mutation; undo a completed
      multi-story import in one step.

### Existing interop, handoff, and accessibility regressions

- [ ] Import representative XD and Figma files and verify editable output plus
      honest fidelity reporting.
- [ ] Export PNG/JPEG/PDF/SVG, semantic HTML, DTCG tokens, and a complete `.exph`
      Handoff Package.
- [ ] Verify nested component states, canvas pages, and the six local read-only
      agent tools still preserve their v2.1 behavior.
- [ ] Exercise all new File/Handoff import actions, story selection, progress,
      report, and cancellation flows with keyboard and VoiceOver.
- [ ] Verify light/dark appearance, increased contrast, reduced motion, and
      reduced transparency across the new import surfaces.

## 4. Commit the frozen release source

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
cd "$ROOT"

git diff --check
git add -A
git diff --cached --check
git diff --cached --stat
git commit -m "v2.2: ship editable rendered component import"
test -z "$(git status --porcelain)"
)
```

Review the staged file list carefully before committing. Do not create the v2.2
tag yet; the generated appcast and HTML release notes must be committed before
the tag points at the final release state.

## 5. Create the signed archive

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
VERSION="2.2"
BUILD="13"
ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/EXP design v$VERSION.xcarchive"
ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/EXP [design].app"

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

scripts/verify_release_candidate.sh --local "$ARCHIVE_APP" "$VERSION" "$BUILD"
open "$ARCHIVE_PATH"
)
```

## 6. Notarize and export from Xcode

In Organizer:

```text
Distribute App → Direct Distribution → Upload for notarization → wait for success
→ export the notarized/stapled app into:
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.2/
```

The result must be exactly:

```text
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.2/EXP [design].app
```

## 7. Verify the exported app and create the one shipping zip

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.2"
BUILD="13"
RELEASE_DIR="$APPS_ROOT/releases/v$VERSION"
APP_PATH="$RELEASE_DIR/EXP [design].app"
ZIP_PATH="$RELEASE_DIR/EXP-design-v$VERSION.zip"

cd "$ROOT"
test -d "$APP_PATH"
test ! -e "$ZIP_PATH"

CLEAN_DIR="$(mktemp -d)"
CLEAN_APP="$CLEAN_DIR/EXP [design].app"
ditto --norsrc --noextattr --noqtn --noacl "$APP_PATH" "$CLEAN_APP"
xattr -cr "$CLEAN_APP"
scripts/verify_release_candidate.sh "$CLEAN_APP" "$VERSION" "$BUILD"

ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$CLEAN_APP" "$ZIP_PATH"

CHECK_DIR="$(mktemp -d)"
ditto -x -k "$ZIP_PATH" "$CHECK_DIR"
scripts/verify_release_candidate.sh "$CHECK_DIR/EXP [design].app" "$VERSION" "$BUILD"
rm -rf "$CHECK_DIR" "$CLEAN_DIR"

ls -lh "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
)
```

That zip is immutable: the same bytes back Sparkle's signature, the GitHub
asset, and the public download.

## 8. Generate release metadata and mark v2.2 released

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.2"
BUILD="13"
ZIP_PATH="$APPS_ROOT/releases/v$VERSION/EXP-design-v$VERSION.zip"
SPARKLE_DIR="$APPS_ROOT/sparkle-releases"
RELEASE_DATE="$(date +%F)"

cd "$ROOT"
test -f "$ZIP_PATH"

SPARKLE_RELEASES_DIR="$SPARKLE_DIR" \
  scripts/generate_sparkle_appcast.sh "$VERSION" "$BUILD" "$ZIP_PATH"
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
cmp -s "$ZIP_PATH" "$SPARKLE_DIR/EXP-design-v$VERSION.zip"

grep -qF '## v2.2 — feature complete; release preparation' docs/ROADMAP.md
RELEASE_DATE="$RELEASE_DATE" perl -0pi -e '
  s{^## v2\.2 — feature complete; release preparation$}
   {## v2.2 — released ($ENV{RELEASE_DATE})}m
' docs/ROADMAP.md

rg -n '^## v2\.2 — released' docs/ROADMAP.md
(cd website && npm run build)
git diff --check
git status --short
)
```

Expected release-metadata changes include:

```text
docs/ROADMAP.md
website/public/appcast.xml
website/public/EXP-design-v2.2.html
website/src/generated/siteContent.json
```

Commit the generated metadata and refreshed website content before tagging.

## 9. Tag, upload, and deploy

Publish the GitHub asset before pushing the appcast-bearing `main`, so the public
appcast never points at a download that does not exist yet.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.2"
ZIP_PATH="$APPS_ROOT/releases/v$VERSION/EXP-design-v$VERSION.zip"

cd "$ROOT"
test -z "$(git status --porcelain)"
gh auth status

git tag -a "v$VERSION" -m "EXP [design] v$VERSION"
git push origin "v$VERSION"

gh release create "v$VERSION" \
  --verify-tag \
  --title "EXP [design] v$VERSION — Bring rendered components onto the canvas." \
  --notes-file "RELEASE-NOTES-v$VERSION.md" \
  "$ZIP_PATH"

DOWNLOAD_CHECK="$(mktemp -d)"
gh release download "v$VERSION" --pattern "EXP-design-v$VERSION.zip" --dir "$DOWNLOAD_CHECK"
cmp -s "$ZIP_PATH" "$DOWNLOAD_CHECK/EXP-design-v$VERSION.zip"
rm -rf "$DOWNLOAD_CHECK"

git push origin main
)
```

Wait for the existing production website deployment to succeed before
continuing. Do not substitute a second hosting path during release night.

## 10. Verify the public release

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
VERSION="2.2"
BUILD="13"
ZIP_NAME="EXP-design-v$VERSION.zip"
LIVE_APPCAST="$(mktemp)"

curl -fsS https://expdesign.app/appcast.xml -o "$LIVE_APPCAST"
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$LIVE_APPCAST"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$LIVE_APPCAST"
grep -q "releases/download/v$VERSION/$ZIP_NAME" "$LIVE_APPCAST"
grep -q 'sparkle:edSignature=' "$LIVE_APPCAST"
rm -f "$LIVE_APPCAST"

curl -fsSIL "https://github.com/tracyapps/EXP-design/releases/download/v$VERSION/$ZIP_NAME" >/dev/null
curl -fsSI "https://expdesign.app/EXP-design-v$VERSION.html" >/dev/null
gh release view "v$VERSION" --json tagName,name,isDraft,isPrerelease,assets,url
)
```

Confirm the homepage reports v2.2/build 13 after the metadata deploy and that
the import/handoff diagram contains the new rendered-source routes.

## 11. Prove v2.1 → v2.2 Sparkle installation

Install the preserved public **v2.1 / build 12** app in `/Applications`, verify
that baseline, then use **EXP [design] → Check for Updates…**.

- [ ] The v2.2 notes are readable with VoiceOver and increased contrast.
- [ ] Download, install, and relaunch complete without installer or signature
      errors.
- [ ] About shows **2.2 / build 13**.
- [ ] A representative v2.1 document opens and saves without migration loss.
- [ ] Agent access remains off after update until explicitly enabled.

Finish with:

```sh
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
INSTALLED_APP="/Applications/EXP [design].app"
cd "$ROOT"
scripts/verify_release_candidate.sh "$INSTALLED_APP" 2.2 13
```

Record the successful update/relaunch proof at the top of the ROADMAP Progress
Log and push that documentation-only commit.

## 12. Announcement gate

- [ ] GitHub Release is public and contains the byte-verified zip.
- [ ] `expdesign.app` shows v2.2 and the download works.
- [ ] Public appcast and HTML release notes pass step 10.
- [ ] v2.1 → v2.2 update/install/relaunch proof passes step 11.
- [ ] ROADMAP records the completed release gates and is pushed.
- [ ] Send the announcement only after every item above is green.
