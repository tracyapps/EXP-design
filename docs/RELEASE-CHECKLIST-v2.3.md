# EXP [design] v2.3 / build 14 release checklist

The exact path from the owner-accepted v2.3 source to the public GitHub,
Sparkle, and website release. Stop at the first failure; never tag, upload, or
deploy around a failed gate. This follows the proven v2.2 release path.

Release artifacts stay outside the repository in `../releases/` and
`../sparkle-releases/`. Keep Dropbox syncing paused while the signed archive,
shipping zip, and appcast are generated.

## 0. Canonical values

```sh
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.3"
BUILD="14"
RELEASE_DIR="$APPS_ROOT/releases/v$VERSION"
APP_PATH="$RELEASE_DIR/EXP [design].app"
ZIP_PATH="$RELEASE_DIR/EXP-design-v$VERSION.zip"
SPARKLE_DIR="$APPS_ROOT/sparkle-releases"
ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/EXP design v$VERSION.xcarchive"
```

Do not overwrite an existing archive, app, or zip. Inspect it and choose
deliberately.

## 1. Freeze and verify the accepted source

- [x] Owner acceptance is green for Waves 1–6 and completed Wave 7 work.
- [x] Remaining Wave 7 work is explicitly deferred to v2.4 in ROADMAP/BACKLOG.
- [x] `RELEASE-NOTES-v2.3.md` describes shipped behavior and honest limits.
- [x] `MARKETING_VERSION = 2.3` and `CURRENT_PROJECT_VERSION = 14` in every config.
- [x] Working tree contains only intended v2.3/release changes.

Run:

```sh
cd "$ROOT"
test "$(git branch --show-current)" = "main"
test -f RELEASE-NOTES-v2.3.md
test -f docs/RELEASE-CHECKLIST-v2.3.md

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

The Sparkle check may note that v2.3 is not yet present in the checked-in
appcast; that is expected until the notarized zip exists.

## 2. Final owner acceptance record

The owner reported all tests green on 2026-08-21, including the final gradient,
font-picker, VoiceOver, tooltip, Inspector, and collapsible-effect checks. Preserve
that receipt; do not reopen accepted scope during release preparation.

Release smoke coverage:

- [x] Create/open/edit/save/reopen, pan/zoom/select/move/resize, undo/redo/export.
- [x] Workspace presets and connected-panel glue/pop-apart across displays.
- [x] Font search/filters/height, text memory, keyboard, and VoiceOver.
- [x] Line caps/markers and SVG browser rendering.
- [x] Gradient endpoints/stops, selected-stop and Inspector-angle sync.
- [x] Compact/Standard/Large type, contrast, Case, tooltips, effect disclosures.
- [x] Owner's configured test suite is green.

## 3. Commit the frozen source

Review every staged path. The source commit must include release notes and this
checklist, but not generated appcast metadata (that comes after notarization).

```sh
cd "$ROOT"
git diff --check
git diff --stat
# Stage the reviewed v2.3 paths explicitly.
git diff --cached --check
git diff --cached --stat
git commit -m "v2.3: polish the everyday design workflow"
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
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.3/
```

The exported result must be exactly:

```text
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.3/EXP [design].app
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
cmp -s "$ZIP_PATH" "$SPARKLE_DIR/EXP-design-v2.3.zip"

RELEASE_DATE="$(date +%F)"
RELEASE_DATE="$RELEASE_DATE" perl -0pi -e '
  s{^## v2\.3 — feature complete; release preparation$}
   {## v2.3 — released ($ENV{RELEASE_DATE})}m
' docs/ROADMAP.md

(cd website && npm run build)
git diff --check
git add docs/ROADMAP.md website/public/appcast.xml \
  website/public/EXP-design-v2.3.html website/src/generated/siteContent.json
git diff --cached --check
git commit -m "v2.3: publish release metadata"
test -z "$(git status --porcelain)"
```

## 8. Tag, upload, and deploy

Publish the GitHub asset before pushing appcast-bearing `main`, so the live feed
never points at a download that does not exist.

```sh
cd "$ROOT"
gh auth status
git tag -a v2.3 -m "EXP [design] v2.3"
git push origin v2.3

gh release create v2.3 \
  --verify-tag \
  --title "EXP [design] v2.3 — A faster, calmer everyday canvas." \
  --notes-file RELEASE-NOTES-v2.3.md \
  "$ZIP_PATH"

DOWNLOAD_CHECK="$(mktemp -d)"
gh release download v2.3 --pattern EXP-design-v2.3.zip --dir "$DOWNLOAD_CHECK"
cmp -s "$ZIP_PATH" "$DOWNLOAD_CHECK/EXP-design-v2.3.zip"
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
grep -q 'releases/download/v2.3/EXP-design-v2.3.zip' "$LIVE_APPCAST"
grep -q 'sparkle:edSignature=' "$LIVE_APPCAST"
rm -f "$LIVE_APPCAST"

curl -fsSIL https://github.com/tracyapps/EXP-design/releases/download/v2.3/EXP-design-v2.3.zip >/dev/null
curl -fsSI https://expdesign.app/EXP-design-v2.3.html >/dev/null
gh release view v2.3 --json tagName,name,isDraft,isPrerelease,assets,url
```

## 10. Prove v2.2 → v2.3 Sparkle installation

- [x] Install preserved public v2.2/build 13 in `/Applications`.
- [x] Run EXP [design] → Check for Updates… and install v2.3.
- [x] Notes are readable and exposed as text in the accessibility tree; the owner's
      accepted appearance pass includes Increase Contrast.
- [x] Download, install, relaunch, and Gatekeeper checks succeed.
- [x] About shows 2.3 / build 14.
- [x] A representative v2.2 document opens and saves without migration loss.
- [x] Agent access remains off until explicitly enabled.

Finish with:

```sh
cd "$ROOT"
scripts/verify_release_candidate.sh "/Applications/EXP [design].app" 2.3 14
```

Record the update proof at the top of the ROADMAP Progress Log and push that
documentation-only commit before announcing the release.

## Completion receipt

- [x] Notarized/stapled universal app exported from Organizer.
- [x] Shipping ZIP passed direct and unzip-roundtrip release-candidate checks.
- [x] ZIP SHA-256:
      `b898ded3c6ba2926aaf6ef62deeecd8eba1d04eeb7a0d3c74514c47755aad36b`.
- [x] Annotated tag `v2.3` points at the release-metadata commit.
- [x] GitHub release is public and its downloaded asset matches the local ZIP.
- [x] Production appcast and v2.3 HTML notes are live.
- [x] Public v2.2 → v2.3 Sparkle update proof is green.

## Next development cycle

- [x] Opened v2.4 development at `MARKETING_VERSION 2.4` /
      `CURRENT_PROJECT_VERSION 15` across the app and thumbnail extension on
      2026-08-24. This does not alter the immutable v2.3/build 14 release artifacts
      or public appcast entry.
