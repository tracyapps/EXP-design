# EXP [design] v2.1 / build 12 release checklist

The exact path from the owner-accepted v2.1 source to the public GitHub,
Sparkle, and website release. Run in a fresh Terminal tab, stop at the first
failure, and never tag/upload/deploy around a failed gate.

Release artifacts stay outside the repository in `../releases/` and
`../sparkle-releases/`. Keep Dropbox syncing paused while the archive, shipping
zip, and appcast are being generated.

## 0. Canonical paths

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail

ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.1"
BUILD="12"
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

Confirm none of the destination paths already contains a v2.1 release candidate.
Do not overwrite an existing archive or zip; inspect it and choose deliberately.

## 1. Freeze the accepted source

- [ ] `RELEASE-NOTES-v2.1.md` reflects the shipped behavior and honest limits.
- [ ] `docs/ROADMAP.md` says v2.1 feature scope is complete but not yet released.
- [ ] `docs/BACKLOG.md` marks every owner-verified v2.1 bug/feature `done`.
- [ ] Homepage feature copy, screenshot briefs, and tester feature feed are current.
- [ ] Design Language screenshots are either updated or explicitly accepted as
      the existing temporary images.
- [ ] `MARKETING_VERSION = 2.1`, `CURRENT_PROJECT_VERSION = 12`, and deployment
      target `26.2` are correct for every shipping target.
- [ ] Working tree contains only intended v2.1/release changes.

## 2. Run the complete local gate

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
cd "$ROOT"

test "$(git branch --show-current)" = "main"
test -f RELEASE-NOTES-v2.1.md

scripts/set_release_version.sh 2.1 12
scripts/verify_nested_component_graph.sh
scripts/verify_anchored_relationships.sh
scripts/verify_canvas_pages.sh
scripts/verify_xd_importer.sh
scripts/verify_figma_importer.sh
scripts/verify_semantic_html_contract.sh
scripts/verify_semantic_html_package.sh
scripts/verify_svg_token_bridge.sh
scripts/verify_sparkle_setup.sh 2.1 12
(cd website && npm run build)

xcodebuild -project "EXP [design].xcodeproj" \
  -scheme "EXP [design]" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  build

git diff --check
git status --short
)
```

The Sparkle preflight may report that v2.1 is not yet in the checked-in appcast;
that is expected until step 8. New compilation, package, signature, helper,
importer, or semantic failures are release stops.

## 3. Final owner acceptance on the Release build

### Core document smoke test

- [ ] Create, open, edit, save, close, and reopen a `.design` document.
- [ ] Confirm legacy single-page documents migrate without visual changes.
- [ ] Pan, zoom, select, move, resize, undo/redo, and export.
- [ ] Confirm About shows **2.1 / build 12**.

### Components and semantics

- [ ] Place a nested component from Components, Object menu, context menu, and
      inside the source editor; cycle attempts must be rejected.
- [ ] Change parent and nested states independently; verify text, fill, opacity,
      visibility, outline, typography, and blend-mode state differences.
- [ ] Exercise nested public props/overrides/reset, duplicate component, detach,
      and preserving source deletion.
- [ ] Save/reopen and inspect Quick Look.
- [ ] Export semantic HTML and a Handoff Package; verify stable unique IDs,
      roles, names, relationships, state data, notes, and component props.

### Pages

- [ ] Add, rename, deep-duplicate, reorder, and delete page tabs with undo.
- [ ] Verify independent camera, guides, Layers, and selection on two pages.
- [ ] Move and duplicate single/multiple layers, a nested child, and
      single/multiple artboards between pages from menu and context routes.
- [ ] Confirm the destination viewport reveals moved work and tabs stay opaque
      during fast panning.

### XD and Figma import

- [ ] Import representative XD documents, including embedded images and text;
      verify editable output, page placement, quiet success, and report-on-demand.
- [ ] Import representative Figma files, including pages, frames, text, images,
      masks, dashed/dotted strokes, rotated lines, auto layout, and components.
- [ ] Cancel each importer once and confirm no partial document mutation.
- [ ] Undo each successful import in one step, then reimport and save/reopen.
- [ ] Confirm tokens remain memory-only and fidelity reports describe every known
      approximation rather than implying an exact mapping.

### Handoff and local agent

- [ ] Dock, detach, resize, and collapse Handoff; verify keyboard order,
      VoiceOver, light/dark, increased contrast, reduced motion, and reduced
      transparency.
- [ ] Export current/selected and all artboards through the panel in every format.
- [ ] Export standalone semantic HTML, DTCG tokens, and a complete `.exph` package.
- [ ] Confirm local agent access starts **off**.
- [ ] Enable it, connect Claude Code with the generated setup, and verify `/mcp`
      exposes exactly six read-only tools.
- [ ] Call orientation, artboard, node, selection, and token reads; change the EXP
      selection and confirm the next response is fresh.
- [ ] Disconnect and disable access; EXP must return through ready to off and the
      local socket must close.

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
git commit -m "v2.1: ship open workflow import, pages, nested components, and Handoff"
test -z "$(git status --porcelain)"
)
```

Do not create the v2.1 tag yet. The generated appcast and HTML release notes must
be committed before the tag points at the final release state.

## 5. Create the archive

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
VERSION="2.1"
BUILD="12"
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
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.1/
```

The result must be exactly:

```text
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.1/EXP [design].app
```

## 7. Verify the exported app and create the one shipping zip

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.1"
BUILD="12"
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

That zip is immutable: the same bytes back Sparkle's signature, the GitHub asset,
and the public download.

## 8. Generate release metadata and mark v2.1 released

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.1"
BUILD="12"
ZIP_PATH="$APPS_ROOT/releases/v$VERSION/EXP-design-v$VERSION.zip"
SPARKLE_DIR="$APPS_ROOT/sparkle-releases"
RELEASE_DATE="$(date +%F)"

cd "$ROOT"
test -f "$ZIP_PATH"

SPARKLE_RELEASES_DIR="$SPARKLE_DIR" \
  scripts/generate_sparkle_appcast.sh "$VERSION" "$BUILD" "$ZIP_PATH"
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
cmp -s "$ZIP_PATH" "$SPARKLE_DIR/EXP-design-v$VERSION.zip"

grep -qF '## v2.1 — feature complete; release preparation' docs/ROADMAP.md
RELEASE_DATE="$RELEASE_DATE" perl -0pi -e '
  s{^## v2\.1 — feature complete; release preparation$}
   {## v2.1 — released ($ENV{RELEASE_DATE})}m
' docs/ROADMAP.md

rg -n '^## v2\.1 — released' docs/ROADMAP.md
(cd website && npm run build)
git diff --check
git status --short
)
```

Expected metadata changes:

```text
docs/ROADMAP.md
website/public/appcast.xml
website/public/EXP-design-v2.1.html
```

Commit those three files before tagging.

## 9. Tag, upload, and deploy

Publish the GitHub asset before pushing `main`, so the public appcast never points
at a download that does not exist yet.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.1"
ZIP_PATH="$APPS_ROOT/releases/v$VERSION/EXP-design-v$VERSION.zip"

cd "$ROOT"
test -z "$(git status --porcelain)"
gh auth status

git tag -a "v$VERSION" -m "EXP [design] v$VERSION"
git push origin "v$VERSION"

gh release create "v$VERSION" \
  --verify-tag \
  --title "EXP [design] v$VERSION — Bring the work in. Send the meaning onward." \
  --notes-file "RELEASE-NOTES-v$VERSION.md" \
  "$ZIP_PATH"

DOWNLOAD_CHECK="$(mktemp -d)"
gh release download "v$VERSION" --pattern "EXP-design-v$VERSION.zip" --dir "$DOWNLOAD_CHECK"
cmp -s "$ZIP_PATH" "$DOWNLOAD_CHECK/EXP-design-v$VERSION.zip"
rm -rf "$DOWNLOAD_CHECK"

git push origin main
)
```

Wait for the production website deploy to succeed before continuing.

## 10. Verify the public release

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
VERSION="2.1"
BUILD="12"
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

Confirm the public homepage still reports v2.0.1 until the metadata deploy lands,
then updates to v2.1/build 12 from the appcast.

## 11. Prove v2.0.1 → v2.1 Sparkle installation

Install the preserved public **v2.0.1 / build 11** app in `/Applications`, verify
that baseline, then use **EXP [design] → Check for Updates…**.

- [ ] The v2.1 notes are readable with VoiceOver and increased contrast.
- [ ] Download, install, and relaunch complete without installer or signature
      errors.
- [ ] About shows **2.1 / build 12**.
- [ ] A representative v2.0.1 document opens and saves without migration loss.
- [ ] Agent access remains off after update until explicitly enabled.

Finish with:

```sh
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
INSTALLED_APP="/Applications/EXP [design].app"
cd "$ROOT"
scripts/verify_release_candidate.sh "$INSTALLED_APP" 2.1 12
```

Record the successful update/relaunch proof at the top of the ROADMAP Progress
Log and push that documentation-only commit.

## 12. Announcement gate

- [ ] GitHub Release is public and contains the byte-verified zip.
- [ ] `expdesign.app` shows v2.1 and the download works.
- [ ] Public appcast and HTML release notes pass step 10.
- [ ] v2.0.1 → v2.1 update/install/relaunch proof passes step 11.
- [ ] ROADMAP records the completed release gates and is pushed.
- [ ] Send the announcement only after every item above is green.
