# Release checklist (reusable)

The repeatable path from a green build on `dev` to a tagged GitHub Release.
GitHub auth is off-box, so the owner runs every `git`/`gh` step.

## Current release

Use **[RELEASE-CHECKLIST-v2.2.md](RELEASE-CHECKLIST-v2.2.md)** for the complete
v2.2/build 13 path. The older version-specific paths below remain as historical
release records and recovery references.

## v2.0.1 copy/paste path

The complete v2.0.1 / build 11 bug-fix path: BUG-006 (component-state typography
and opacity leak), BUG-005 (Shift ignored on a new Pen handle), and the Type-panel
polish (labeled Font/Weight menus + Content role in its own sub-section). It mirrors
the hardened v2.0 path below with the version variables changed to `2.0.1` / `11`.
Same rules: fresh Terminal tab, stop at the first failed command, do not tag/upload/
deploy around a failure. Each block neutralizes leaked fail-fast options, then runs
inside `( … )`. Release artifacts stay OUTSIDE the repo (`../releases/`,
`../sparkle-releases/`); keep Dropbox syncing paused through appcast generation.

### 0. Canonical paths

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail

ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.0.1"
BUILD="11"
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

### 0.5 Working-tree hygiene (one-time repo cleanup)

Two housekeeping items surfaced during the 2.0.1 work. Clear them before the gate so
the release diff is clean.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
cd "$ROOT"

# 1) Remove any stale git lock left by an interrupted or mounted git run. (A
#    Cowork session editing over the Dropbox mount can leave a 0-byte lock it
#    cannot unlink; only a local macOS delete clears it.)
rm -f .git/index.lock

# 2) Stop tracking Xcode per-user state (scheme list + order hints). It should
#    never have been committed; .gitignore now ignores `xcuserdata/`, but the
#    already-tracked copy must leave the index once. Deletes nothing on disk.
git rm -r --cached --ignore-unmatch "EXP [design].xcodeproj/xcuserdata" >/dev/null 2>&1 || true

# 3) A ".fuse_hidden…" file inside the .xcodeproj is a Linux/FUSE artifact from a
#    mounted editor rewriting project.pbxproj while a handle was open. macOS does
#    not create these; if one exists locally it is safe to delete.
find "EXP [design].xcodeproj" -name '.fuse_hidden*' -delete 2>/dev/null || true

git status --short
)
```

Expect `.gitignore` and the removed `xcuserdata/...xcschememanagement.plist` in the
status; they get committed with the release source in step 3.

### 1. Run the complete local gate

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
cd "$ROOT"

test "$(git branch --show-current)" = "main"
test -f RELEASE-NOTES-v2.0.1.md

scripts/set_release_version.sh 2.0.1 11
scripts/verify_semantic_html_contract.sh
scripts/verify_semantic_html_package.sh
scripts/verify_svg_token_bridge.sh
scripts/verify_sparkle_setup.sh 2.0.1 11
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

The v2.0 path's PlistBuddy scheme-cleanup step is no longer needed here: with
`xcuserdata/` untracked and ignored (step 0.5), Xcode's scheme churn never reaches
the index. The Sparkle preflight should end noting v2.0.1 is not yet in the checked-in
appcast — expected until the notarized zip exists. Known non-blocking output: the
existing Swift 6 deprecation backlog and AppIntents' "No AppIntents.framework
dependency found" notice. Any new error, test/signature/package failure is a stop.

### 2. Owner acceptance before freezing source

- [ ] Launch the Release build; confirm create/open/edit/save/export still work.
- [ ] Reproduce the two fixed defects from the 2026-07-23 recording:
      - **BUG-006:** in a component source, activate a non-default state (e.g.
        Disabled), change a text layer's color / size / face / alignment /
        line-height / tracking / case and a layer or group opacity; confirm Default
        and sibling states are byte-for-byte unchanged and instances render the
        chosen state correctly.
      - **BUG-005:** with the Pen, click-drag a new anchor's handle while holding
        Shift; confirm it snaps to axis/45° and the opposite handle stays mirrored,
        and that pressing/releasing Shift mid-drag toggles the snap.
- [ ] In the Type inspector, confirm the Font and Weight menus are labeled and the
      Content role sits in its own divider-separated sub-section below Case.
- [ ] Export a Handoff Package from a doc with a stated component; confirm per-state
      typography/opacity appear in the state CSS.
- [ ] Confirm About shows **2.0.1 / build 11**.

### 3. Commit the release source

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
git commit -m "v2.0.1: fix component-state edit leak (BUG-006) and Pen Shift constraint (BUG-005)"
test -z "$(git status --porcelain)"
)
```

Do not create the `v2.0.1` tag yet — the generated appcast and its release-note HTML
must be committed first.

### 4. Create the final archive

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
VERSION="2.0.1"
BUILD="11"
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

### 5. Direct Distribution in Xcode

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
RELEASE_DIR="$APPS_ROOT/releases/v2.0.1"
APP_PATH="$RELEASE_DIR/EXP [design].app"
ZIP_PATH="$RELEASE_DIR/EXP-design-v2.0.1.zip"

mkdir -p "$RELEASE_DIR"
test ! -e "$APP_PATH"
test ! -e "$ZIP_PATH"
printf 'Export the Direct Distribution app into:\n%s\n' "$RELEASE_DIR"
)
```

In Xcode Organizer (the archive opened in step 4):

```text
Distribute App → Direct Distribution → Upload for notarization → wait for success
→ export the notarized/stapled app into:
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.0.1/
```

The exported bundle must land at exactly:

```text
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.0.1/EXP [design].app
```

### 6. Verify the exported app and create the one shipping zip

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.0.1"
BUILD="11"
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

That zip is now immutable — the same bytes back Sparkle's signature, the GitHub asset,
and every downloaded byte. Do not re-zip.

### 7. Generate the v2.0.1 appcast and mark the roadmap released

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.0.1"
BUILD="11"
ZIP_PATH="$APPS_ROOT/releases/v$VERSION/EXP-design-v$VERSION.zip"
SPARKLE_DIR="$APPS_ROOT/sparkle-releases"
RELEASE_DATE="$(date +%F)"

cd "$ROOT"
test -f "$ZIP_PATH"

SPARKLE_RELEASES_DIR="$SPARKLE_DIR" \
  scripts/generate_sparkle_appcast.sh "$VERSION" "$BUILD" "$ZIP_PATH"
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
cmp -s "$ZIP_PATH" "$SPARKLE_DIR/EXP-design-v$VERSION.zip"

grep -qF '## v2.0.1 — in progress (opened 2026-07-23)' docs/ROADMAP.md

RELEASE_DATE="$RELEASE_DATE" perl -0pi -e '
  s{^## v2\.0\.1 — in progress \(opened 2026-07-23\)$}
   {## v2.0.1 — released ($ENV{RELEASE_DATE})}m
' docs/ROADMAP.md

rg -n '^## v2\.0\.1 — released' docs/ROADMAP.md
(cd website && npm run build)
git diff --check
git status --short
)
```

Expected release-metadata changes:

```text
docs/ROADMAP.md
website/public/appcast.xml
website/public/EXP-design-v2.0.1.html
```

Commit them before tagging:

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
cd "$ROOT"
git add \
  docs/ROADMAP.md \
  website/public/appcast.xml \
  website/public/EXP-design-v2.0.1.html
git diff --cached --check
git diff --cached --stat
git commit -m "v2.0.1: publish release metadata"
test -z "$(git status --porcelain)"
)
```

### 8. Tag, upload the exact asset, then deploy the site

Publish the GitHub asset before pushing `main`, so Vercel never serves an appcast
that points at a not-yet-existing download.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.0.1"
ZIP_PATH="$APPS_ROOT/releases/v$VERSION/EXP-design-v$VERSION.zip"

cd "$ROOT"
test -z "$(git status --porcelain)"
gh auth status

git tag -a "v$VERSION" -m "EXP [design] v$VERSION"
git push origin "v$VERSION"

gh release create "v$VERSION" \
  --verify-tag \
  --title "EXP [design] v$VERSION — Component states and Pen curves, fixed" \
  --notes-file "RELEASE-NOTES-v$VERSION.md" \
  "$ZIP_PATH"

DOWNLOAD_CHECK="$(mktemp -d)"
gh release download "v$VERSION" --pattern "EXP-design-v$VERSION.zip" --dir "$DOWNLOAD_CHECK"
cmp -s "$ZIP_PATH" "$DOWNLOAD_CHECK/EXP-design-v$VERSION.zip"
rm -rf "$DOWNLOAD_CHECK"

git push origin main
)
```

Wait for the Vercel production deploy to report success before the live checks.

### 9. Verify the public release

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
VERSION="2.0.1"
BUILD="11"
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

Every command must return zero; confirm the release is neither draft nor prerelease
and lists `EXP-design-v2.0.1.zip`.

### 10. Prove v2.0 → v2.0.1 Sparkle installation

Install the preserved public **v2.0 / build 10** build in `/Applications`, then:

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
INSTALLED_APP="/Applications/EXP [design].app"
cd "$ROOT"
scripts/verify_installed_update_baseline.sh "$INSTALLED_APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED_APP/Contents/Info.plist")" = "2.0"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALLED_APP/Contents/Info.plist")" = "10"
open "$INSTALLED_APP"
)
```

In the running v2.0 app: **EXP [design] → Check for Updates…**; confirm the v2.0.1
notes read well with VoiceOver and increased contrast; install, allow relaunch, and
confirm About shows **2.0.1 / build 11**. Then:

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
INSTALLED_APP="/Applications/EXP [design].app"
SOCKET_PATH="$HOME/Library/Containers/tapps.EXP--design-/Data/Library/Application Support/EXP/agent.sock"
cd "$ROOT"
scripts/verify_release_candidate.sh "$INSTALLED_APP" 2.0.1 11
test ! -e "$SOCKET_PATH"
)
```

The socket check proves agent access stays off by default. Record the install/relaunch
proof in the ROADMAP Progress Log, then commit/push that documentation-only update.

### 11. Final announcement checklist

- [ ] GitHub Release is public and contains the byte-verified zip.
- [ ] `expdesign.app` shows v2.0.1 and its download works.
- [ ] Public appcast and HTML release notes pass step 9.
- [ ] v2.0 → v2.0.1 update/install/relaunch proof passes step 10.
- [ ] ROADMAP records the completed release gates and is pushed.
- [ ] Send the announcement only after all checks above are green.

## v2.0 copy/paste path

This is the complete v2.0/build 10 path. It does not depend on translating any
`X.Y` placeholders in the reusable sections below. Use a fresh Terminal tab and
stop at the first failed command. Do not tag, upload, or deploy around a failure.
Every command block first neutralizes fail-fast options leaked by an earlier
attempt, then runs inside `( … )`. A failure stops that block but always returns
to the Terminal prompt instead of closing the window.

SCSS is deliberately deferred and is not a release gate. CSS custom properties
are the v2 handoff contract.

### 0. Canonical paths

Paste this block at the start of a Terminal tab. Keep that tab open for the
release; later blocks repeat critical values where a mistake would be costly.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail

ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.0"
BUILD="10"
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

Release artifacts stay outside the repository. The `.xcarchive` stays in Xcode's
local Archives folder; the exported app/zip and accumulated Sparkle archives use
the normal sibling `apps/releases/` and `apps/sparkle-releases/` folders. Keep
Dropbox syncing paused—or confirm the `apps` ignore rule is actually honored—
through appcast generation. Step 6 deliberately copies the exported app into a
temporary non-synced directory for signature verification and zipping because
Dropbox's File Provider can attach `com.apple.FinderInfo` even while syncing is
paused. The final zip still lives in the normal release directory.

### 1. Run the complete local gate

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
cd "$ROOT"

test "$(git branch --show-current)" = "main"
test -f RELEASE-NOTES-v2.0.md

scripts/set_release_version.sh 2.0 10
scripts/verify_semantic_html_contract.sh
scripts/verify_semantic_html_package.sh
scripts/verify_svg_token_bridge.sh
scripts/verify_sparkle_setup.sh 2.0 10
(cd website && npm run build)

xcodebuild -project "EXP [design].xcodeproj" \
  -scheme "EXP [design]" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  build

# Xcode may add the new helper's auto-scheme to this tracked per-user plist.
# Remove only that generated entry; it is not release source.
SCHEME_STATE="EXP [design].xcodeproj/xcuserdata/tapps.xcuserdatad/xcschemes/xcschememanagement.plist"
/usr/libexec/PlistBuddy \
  -c 'Delete :SchemeUserState:exp-mcp.xcscheme_^#shared#^_' \
  "$SCHEME_STATE" 2>/dev/null || true

git diff --check
git status --short
)
```

The Sparkle preflight should end with a note that v2.0 is not in the checked-in
appcast yet. That is expected here: the appcast cannot be generated until the
final notarized zip exists.

Known non-blocking output: the existing Swift 6 migration/deprecation warning
backlog and AppIntents' “No AppIntents.framework dependency found” notice. Any
new error, signature failure, test failure, or package mismatch is a stop.

### 2. Owner acceptance before freezing source

- [ ] Open a normal working `.design` document and export its Handoff Package.
- [ ] Inspect `README.llm.md`, `manifest.json`, `tokens.json`, `design.json`, and
      representative artboard HTML. Confirm notes, roles, heading intent, and
      visual fallbacks survive.
- [ ] Open representative HTML in Firefox and Safari/WebKit. Spot-check keyboard
      operation and VoiceOver reading order in light/dark and increased contrast.
- [ ] Launch the Release build and confirm normal create/open/edit/save/export,
      Design Language typography, and Help → ARIA Roles Guide behavior.
- [ ] Confirm About shows **2.0 / build 10**.

The automated half of the real-document handoff gate and all six bridge tools
already pass. This step is the owner's subjective “does this handoff feel right?”
check, not a repeat of the protocol harness.

### 3. Commit the release source

Review the status printed by step 1. When every listed change belongs in v2.0,
paste:

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
git commit -m "v2.0: semantic handoff and agent bridge"
test -z "$(git status --porcelain)"
)
```

Do not create the `v2.0` tag yet. The generated appcast and its release-note HTML
must be committed before the tag is created.

### 4. Create the final archive

This produces a fresh archive from committed source and refuses to overwrite an
older archive with the same name.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
VERSION="2.0"
BUILD="10"
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

SCHEME_STATE="EXP [design].xcodeproj/xcuserdata/tapps.xcuserdatad/xcschemes/xcschememanagement.plist"
/usr/libexec/PlistBuddy \
  -c 'Delete :SchemeUserState:exp-mcp.xcscheme_^#shared#^_' \
  "$SCHEME_STATE" 2>/dev/null || true

scripts/verify_release_candidate.sh --local "$ARCHIVE_APP" "$VERSION" "$BUILD"
open "$ARCHIVE_PATH"
)
```

The local verifier must confirm version/build, universal arm64+x86_64 app and
helper slices, strict nested signatures, no forbidden Finder metadata, and the
intended entitlement boundary. The sandboxed app owns network client/server and
Sparkle exceptions; `exp-mcp` owns no sandbox or network entitlement.

### 5. Direct Distribution in Xcode

Before using Organizer, this block confirms an older app or zip will not be
silently reused. If it stops, move the old artifact aside deliberately and
rerun it.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
RELEASE_DIR="$APPS_ROOT/releases/v2.0"
APP_PATH="$RELEASE_DIR/EXP [design].app"
ZIP_PATH="$RELEASE_DIR/EXP-design-v2.0.zip"

mkdir -p "$RELEASE_DIR"
test ! -e "$APP_PATH"
test ! -e "$ZIP_PATH"
printf 'Export the Direct Distribution app into:\n%s\n' "$RELEASE_DIR"
)
```

The archive command in step 4 opens the archive. In Xcode Organizer:

```text
Distribute App
→ Direct Distribution
→ Upload for notarization
→ wait for success
→ export the notarized/stapled app into:

/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.0/
```

The exported bundle must land at this exact path:

```text
/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/releases/v2.0/EXP [design].app
```

### 6. Verify the exported app and create the one shipping zip

Run only after Xcode reports successful notarization/stapling and the app exists
at the exact path above.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.0"
BUILD="10"
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

ditto -c -k \
  --norsrc --noextattr --noqtn --noacl --keepParent \
  "$CLEAN_APP" "$ZIP_PATH"

CHECK_DIR="$(mktemp -d)"
ditto -x -k "$ZIP_PATH" "$CHECK_DIR"
scripts/verify_release_candidate.sh \
  "$CHECK_DIR/EXP [design].app" "$VERSION" "$BUILD"
rm -rf "$CHECK_DIR" "$CLEAN_DIR"

ls -lh "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
)
```

That zip is now immutable. Do not re-zip the app. Sparkle's EdDSA signature,
the GitHub asset, and every downloaded byte must all refer to this exact file.

### 7. Generate the v2.0 appcast and mark the roadmap released

The appcast helper copies the byte-identical zip into the accumulated local
Sparkle folder, signs it, creates the HTML update notes, updates the public
appcast, and refuses to replace a different existing v2.0 archive.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.0"
BUILD="10"
ZIP_PATH="$APPS_ROOT/releases/v$VERSION/EXP-design-v$VERSION.zip"
SPARKLE_DIR="$APPS_ROOT/sparkle-releases"
RELEASE_DATE="$(date +%F)"

cd "$ROOT"
test -f "$ZIP_PATH"

SPARKLE_RELEASES_DIR="$SPARKLE_DIR" \
  scripts/generate_sparkle_appcast.sh "$VERSION" "$BUILD" "$ZIP_PATH"
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
cmp -s "$ZIP_PATH" "$SPARKLE_DIR/EXP-design-v$VERSION.zip"

grep -qF \
  '## v2.0 — Interop & Handoff (ACTIVE — build 10; anchor: docs/V2-INTEROP-PLAN.md)' \
  docs/ROADMAP.md

RELEASE_DATE="$RELEASE_DATE" perl -0pi -e '
  s{^## v2\.0 — Interop & Handoff \(ACTIVE — build 10; anchor: docs/V2-INTEROP-PLAN\.md\)$}
   {## v2.0 — released ($ENV{RELEASE_DATE})\n\nInterop & Handoff, build 10. Planning record: `docs/V2-INTEROP-PLAN.md`.}m
' docs/ROADMAP.md

rg -n '^## v2\.0 — released' docs/ROADMAP.md
(cd website && npm run build)
git diff --check
git status --short
)
```

Expected release-metadata changes are:

```text
docs/ROADMAP.md
website/public/appcast.xml
website/public/EXP-design-v2.0.html
```

On a resumed release, the checklist/verifier may also contain reviewed workflow
hardening from the failed attempt. The commit block intentionally includes those
paths when changed and is a no-op for them otherwise.

Commit them before tagging:

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
cd "$ROOT"

git add \
  docs/RELEASE-CHECKLIST.md \
  docs/ROADMAP.md \
  scripts/verify_release_candidate.sh \
  website/public/appcast.xml \
  website/public/EXP-design-v2.0.html
git diff --cached --check
git diff --cached --stat
git commit -m "v2.0: publish release metadata and harden workflow"
test -z "$(git status --porcelain)"
)
```

### 8. Tag, upload the exact asset, then deploy the site

The order is intentional: publish the GitHub asset before pushing `main`, so
Vercel never serves an appcast that points at a not-yet-existing download.

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
APPS_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="2.0"
ZIP_PATH="$APPS_ROOT/releases/v$VERSION/EXP-design-v$VERSION.zip"

cd "$ROOT"

# A resumed release may have reviewed runbook-only corrections made after the
# local metadata commit. Fold only those known paths into that unpushed commit.
if [[ -n "$(git status --porcelain -- \
  docs/RELEASE-CHECKLIST.md \
  docs/ROADMAP.md \
  scripts/verify_release_candidate.sh)" ]]; then
  git add \
    docs/RELEASE-CHECKLIST.md \
    docs/ROADMAP.md \
    scripts/verify_release_candidate.sh
  git diff --cached --check
  git commit --amend --no-edit
fi

test -z "$(git status --porcelain)"
gh auth status

if git rev-parse --verify --quiet "refs/tags/v$VERSION" >/dev/null; then
  TAG_COMMIT="$(git rev-list -n 1 "v$VERSION")"
  git merge-base --is-ancestor "$TAG_COMMIT" HEAD
  TAG_DISTANCE="$(git rev-list --count "v$VERSION..HEAD")"
  test "$TAG_DISTANCE" -le 1
  echo "Reusing existing v$VERSION tag at $TAG_COMMIT ($TAG_DISTANCE metadata commit(s) behind HEAD)."
else
  if git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1; then
    echo "Remote tag v$VERSION exists without a matching local tag; stop and inspect it." >&2
    exit 1
  fi
  git tag -a "v$VERSION" -m "EXP [design] v$VERSION"
fi

LOCAL_TAG_COMMIT="$(git rev-list -n 1 "v$VERSION")"
REMOTE_TAG_COMMIT="$(git ls-remote --tags origin "refs/tags/v$VERSION^{}" | awk 'NR == 1 { print $1 }')"
if [[ -z "$REMOTE_TAG_COMMIT" ]]; then
  git push origin "v$VERSION"
else
  test "$REMOTE_TAG_COMMIT" = "$LOCAL_TAG_COMMIT"
  echo "Remote v$VERSION tag already matches $LOCAL_TAG_COMMIT."
fi

gh release create "v$VERSION" \
  --verify-tag \
  --title "EXP [design] v$VERSION — Handoff that keeps its meaning" \
  --notes-file "RELEASE-NOTES-v$VERSION.md" \
  "$ZIP_PATH"

DOWNLOAD_CHECK="$(mktemp -d)"
gh release download "v$VERSION" \
  --pattern "EXP-design-v$VERSION.zip" \
  --dir "$DOWNLOAD_CHECK"
cmp -s \
  "$ZIP_PATH" \
  "$DOWNLOAD_CHECK/EXP-design-v$VERSION.zip"
rm -rf "$DOWNLOAD_CHECK"

git push origin main
)
```

Pushing `main` triggers the configured Vercel production build from the repo
root. Wait for that deployment to report success before running the live checks.

### 9. Verify the public release

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
VERSION="2.0"
BUILD="10"
ZIP_NAME="EXP-design-v$VERSION.zip"
LIVE_APPCAST="$(mktemp)"

cd "$ROOT"
curl -fsS https://expdesign.app/appcast.xml -o "$LIVE_APPCAST"
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$LIVE_APPCAST"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$LIVE_APPCAST"
grep -q "releases/download/v$VERSION/$ZIP_NAME" "$LIVE_APPCAST"
grep -q 'sparkle:edSignature=' "$LIVE_APPCAST"
rm -f "$LIVE_APPCAST"

curl -fsSIL "https://github.com/tracyapps/EXP-design/releases/download/v$VERSION/$ZIP_NAME" >/dev/null
curl -fsSI "https://expdesign.app/EXP-design-v$VERSION.html" >/dev/null
curl -fsSI "https://expdesign.app/aria-roles/" >/dev/null
gh release view "v$VERSION" --json tagName,name,isDraft,isPrerelease,assets,url
)
```

Every command must return zero. Confirm the GitHub result says the release is
neither draft nor prerelease and lists `EXP-design-v2.0.zip`.

### 10. Prove v1.6.1 → v2.0 Sparkle installation

This is the first complete automatic-update proof because v1.6.1 repaired the
installed-app baseline. Install the preserved public v1.6.1 build in
`/Applications`, then paste:

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
INSTALLED_APP="/Applications/EXP [design].app"

cd "$ROOT"
scripts/verify_installed_update_baseline.sh "$INSTALLED_APP"

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$INSTALLED_APP/Contents/Info.plist")" = "1.6.1"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$INSTALLED_APP/Contents/Info.plist")" = "9"

open "$INSTALLED_APP"
)
```

In the running v1.6.1 app:

1. Choose **EXP [design] → Check for Updates…**.
2. Confirm the v2.0 notes are readable with VoiceOver and increased contrast.
3. Install, allow relaunch, and confirm About shows **2.0 / build 10**.

Then paste:

```sh
set +e +u
set +o pipefail 2>/dev/null || true
(
set -euo pipefail
ROOT="/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"
INSTALLED_APP="/Applications/EXP [design].app"
SOCKET_PATH="$HOME/Library/Containers/tapps.EXP--design-/Data/Library/Application Support/EXP/agent.sock"

cd "$ROOT"
scripts/verify_release_candidate.sh "$INSTALLED_APP" 2.0 10
test ! -e "$SOCKET_PATH"
)
```

The final socket check proves agent access remains off by default in the
installed public build. Record the successful install/relaunch proof in the
ROADMAP Progress Log and check the final v2.0 release gate, then commit/push that
documentation-only update.

### 11. Final announcement checklist

- [x] GitHub Release is public and contains the byte-verified zip.
- [x] `expdesign.app` shows v2.0 and its download works.
- [x] Public appcast and HTML release notes pass step 9.
- [x] v1.6.1 → v2.0 update/install/relaunch proof passes step 10.
- [ ] ROADMAP records the completed release gates and is pushed.
- [ ] Send the release announcement only after all checks above are green.

## v1.6.1 copy/paste path
Use this section for the v1.6.1 bug-fix release. The project is already set to
`MARKETING_VERSION 1.6.1` / build `9`; rerun the prep commands anyway because
they are cheap and catch drift.

Assumption: Xcode exports the notarized/stapled app to:

```text
../releases/v1.6.1/EXP [design].app
```

The Sparkle archive folder lives next to this repo:

```text
../sparkle-releases/
```

### 0. Prep / verify before Xcode archive
```sh
cd "/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"

VERSION="1.6.1"
BUILD="9"
RELEASE_DIR="../releases/v$VERSION"
APP_PATH="$RELEASE_DIR/EXP [design].app"
ZIP_PATH="$RELEASE_DIR/EXP-design-v$VERSION.zip"

scripts/set_release_version.sh "$VERSION" "$BUILD"
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
mkdir -p "$RELEASE_DIR" ../sparkle-releases
```

Optional local compile sanity before archiving:

```sh
xcodebuild -project "EXP [design].xcodeproj" \
  -scheme "EXP [design]" \
  -configuration Debug \
  build
```

Then in Xcode:

```text
Product -> Archive
Distribute App -> Direct Distribution
Export the stapled app to ../releases/v1.6.1/
```

Keep the `.xcarchive` in Xcode's local Archives directory, not in the
Dropbox-synced release folder. A synced-folder/Finder metadata write can attach
`com.apple.FinderInfo` to Sparkle XPC services or the thumbnail extension,
making an otherwise valid nested signature fail. If an archive was accidentally
created there, move it into Xcode's local archive directory. In either case,
clear attributes and verify immediately before Direct Distribution:

```sh
ARCHIVE_APP="/absolute/path/to/<archive>.xcarchive/Products/Applications/EXP [design].app"
xattr -cr "$ARCHIVE_APP"
codesign --verify --deep --strict --verbose=2 "$ARCHIVE_APP"
```

This pre-distribution check does not replace the identical cleanup and round-trip
verification on the final exported app below. The final app/zip check is the
shipping authority because a queued metadata write may occur after archive
creation or movement.

Important: Sparkle runs inside the sandboxed app, so the exported app must have
outbound network permission. The preflight script checks the Xcode build setting,
and the post-export step below checks the signed app entitlement, strict nested
code signatures, and Gatekeeper assessment.

### 1. Verify and zip the exported app
Run this after Xcode has exported the app:

```sh
cd "/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"

VERSION="1.6.1"
BUILD="9"
RELEASE_DIR="../releases/v$VERSION"
APP_PATH="$RELEASE_DIR/EXP [design].app"
ZIP_PATH="$RELEASE_DIR/EXP-design-v$VERSION.zip"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing exported app: $APP_PATH"
else
  xattr -cr "$APP_PATH"

  ENTITLEMENTS_FILE="$(mktemp)"
  codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS_FILE" 2>/dev/null
  if ! /usr/libexec/PlistBuddy -c "Print :com.apple.security.network.client" "$ENTITLEMENTS_FILE" 2>/dev/null | grep -qx true; then
    echo "Missing outgoing network entitlement; Sparkle cannot fetch appcast.xml"
  elif ! /usr/libexec/PlistBuddy -c "Print :SUEnableInstallerLauncherService" "$APP_PATH/Contents/Info.plist" 2>/dev/null | grep -qx true; then
    echo "Missing SUEnableInstallerLauncherService; sandboxed Sparkle cannot launch its installer"
  elif ! /usr/libexec/PlistBuddy -c "Print :com.apple.security.temporary-exception.mach-lookup.global-name" "$ENTITLEMENTS_FILE" 2>/dev/null | grep -q -- '-spks$'; then
    echo "Missing Sparkle -spks Mach lookup exception"
  elif ! /usr/libexec/PlistBuddy -c "Print :com.apple.security.temporary-exception.mach-lookup.global-name" "$ENTITLEMENTS_FILE" 2>/dev/null | grep -q -- '-spki$'; then
    echo "Missing Sparkle -spki Mach lookup exception"
  elif ! codesign --verify --deep --strict --verbose=2 "$APP_PATH"; then
    echo "Strict code-signing verification failed; do not ship this app"
  elif ! spctl -a -vvv -t install "$APP_PATH"; then
    echo "Gatekeeper assessment failed; do not ship this app"
  else
    rm -f "$ZIP_PATH"
    ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_PATH" "$ZIP_PATH"

    CHECK_DIR="$(mktemp -d)"
    ditto -x -k "$ZIP_PATH" "$CHECK_DIR"
    codesign --verify --deep --strict --verbose=2 "$CHECK_DIR/EXP [design].app"
    spctl -a -vvv -t install "$CHECK_DIR/EXP [design].app"
    rm -rf "$CHECK_DIR"

    ls -lh "$ZIP_PATH"
  fi
  rm -f "$ENTITLEMENTS_FILE"
fi
```

If any post-export check changes the app or zip, regenerate the appcast and
upload that exact new archive. Sparkle signatures are tied to the exact zip
bytes.

### 2. Generate the Sparkle appcast
This copies the zip into `../sparkle-releases/`, creates the matching
`EXP-design-v1.6.1.html`, updates `website/public/appcast.xml`, disables delta
updates, and verifies the URL/build/signature shape.

```sh
cd "/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"

VERSION="1.6.1"
BUILD="9"
ZIP_PATH="../releases/v$VERSION/EXP-design-v$VERSION.zip"

scripts/generate_sparkle_appcast.sh "$VERSION" "$BUILD" "$ZIP_PATH"
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
```

Important: generate the appcast **after** the final notarized zip exists and
before creating/deploying the release. The appcast EdDSA signature is for the
exact bytes of this archive.

### 3. Create the GitHub release
If using GitHub CLI:

```sh
cd "/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"

VERSION="1.6.1"
ZIP_PATH="../releases/v$VERSION/EXP-design-v$VERSION.zip"

gh release create "v$VERSION" \
  --title "EXP [design] v$VERSION" \
  --notes-file "RELEASE-NOTES-v$VERSION.md" \
  "$ZIP_PATH"
```

If using GitHub in the browser, upload this exact same file:

```text
../releases/v1.6.1/EXP-design-v1.6.1.zip
```

Do not re-zip. Sparkle's signature is for that exact archive.

### 4. Deploy + verify
```sh
cd "/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]/website"
npm run build
```

After deploying the website:

```sh
curl -s https://expdesign.app/appcast.xml | grep -E "1.6.1|sparkle:edSignature|releases/download/v1.6.1"
curl -I https://expdesign.app/EXP-design-v1.6.1.html
```

Final human test for v1.6.1:

```text
1. Install v1.6.1 manually; v1.6 and earlier lack the sandbox entitlement needed
   to launch their own Sparkle installer.
2. Confirm About EXP [design] shows 1.6.1 / build 9.
3. Run scripts/verify_installed_update_baseline.sh and preserve this installed
   copy as the baseline for the next release's prompt → install → relaunch proof.
```

v1.6.1 repairs the baseline itself. The first valid end-to-end automatic-update
proof therefore begins with installed v1.6.1 and targets the next published build.

### 5. After v1.6.1 is live
Open the approved v2.0 interop/handoff cycle:

```sh
scripts/set_release_version.sh 2.0 10
grep MARKETING_VERSION "EXP [design].xcodeproj/project.pbxproj" | sort -u
grep CURRENT_PROJECT_VERSION "EXP [design].xcodeproj/project.pbxproj" | sort -u
```

Then update `docs/ROADMAP.md` if the v2.0 section needs adjustment, commit on
the active development branch, and keep release artifacts out of the repo.

## 1. Land the work on `dev`
- [ ] Xcode build is clean and the release's changes are smoke-tested.
- [ ] Progress Log updated in `docs/ROADMAP.md` (newest on top).
- [ ] BACKLOG statuses updated (fixed bugs → `done (vX.Y — verified by owner)`).
- [ ] `RELEASE-NOTES-vX.Y.md` written at the repo root.
- [ ] Run the local release sanity check:
```sh
scripts/verify_sparkle_setup.sh X.Y BUILD
```
- [ ] Commit everything: `git add -A && git commit -m "vX.Y: <headline>"`

## 2. Version bump (if not already done)
- [ ] `MARKETING_VERSION` = X.Y and `CURRENT_PROJECT_VERSION` = build number,
      across ALL build configs in `EXP [design].xcodeproj/project.pbxproj`.
- [ ] Preferred helper:
```sh
scripts/set_release_version.sh X.Y BUILD
```
- [ ] Verify:
```sh
grep MARKETING_VERSION "EXP [design].xcodeproj/project.pbxproj" | sort -u
grep CURRENT_PROJECT_VERSION "EXP [design].xcodeproj/project.pbxproj" | sort -u
```

## 3. Merge to `main` and tag
```sh
git checkout main
git merge --no-ff dev -m "Release vX.Y"
git tag -a vX.Y -m "EXP [design] vX.Y"
git push origin main
git push origin vX.Y
```

## 4. Build & publish the app
- [ ] Archive in Xcode → Distribute App ▸ **Direct Distribution** (signs with
      Developer ID, notarizes, AND staples). Export the .app only when Xcode
      reports it stapled.
- [ ] Confirm the exported app can reach Sparkle's appcast from inside the app
      sandbox:
```sh
codesign -d --entitlements :- "EXP [design].app" 2>/dev/null | \
  plutil -p - | \
  grep '"com.apple.security.network.client" => true'
```
- [ ] Zip with **ditto** — NOT `zip -r` (Sparkle.framework contains symlinks;
      flattening them breaks the code signature and Sparkle will refuse the
      update). Strip export-location metadata, verify the signed app, then zip
      AFTER stapling:
```sh
xattr -cr "EXP [design].app"
codesign --verify --deep --strict --verbose=2 "EXP [design].app"
spctl -a -vvv -t install "EXP [design].app"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "EXP [design].app" EXP-design-vX.Y.zip
CHECK_DIR="$(mktemp -d)"
ditto -x -k EXP-design-vX.Y.zip "$CHECK_DIR"
codesign --verify --deep --strict --verbose=2 "$CHECK_DIR/EXP [design].app"
spctl -a -vvv -t install "$CHECK_DIR/EXP [design].app"
rm -rf "$CHECK_DIR"
```
- [ ] This ONE zip is used everywhere (GitHub asset + `sparkle-releases/` for
      the appcast). Byte-identical copies only — never re-zip.
- [ ] Create the release (CLI):
```sh
gh release create vX.Y \
  --title "EXP [design] vX.Y — <headline>" \
  --notes-file RELEASE-NOTES-vX.Y.md \
  "path/to/EXP-design-vX.Y.zip"
```
  …or upload the zip on the Releases page and paste the notes body.
- [ ] Confirm the download link on the tester page (`expdesign.app/download`).
- [ ] Website content sync (`website/scripts/sync-content.mjs`) picks up the new
      phase statuses / roadmap. The website's current-version pill is parsed
      from a heading shaped like `## vX.Y — shipped (YYYY-MM-DD)`, so update
      `docs/ROADMAP.md` when the release is actually live. Run `npm run build`
      from `website/` to verify.

## 4.5 Update the Sparkle appcast (auto-updates)
- [ ] Keep a local `sparkle-releases/` folder OUTSIDE the repo holding every
      release zip (generate_appcast reads the whole folder and carries prior
      entries forward).
- [ ] Run the helper against the notarized/stapled zip:
```sh
scripts/generate_sparkle_appcast.sh X.Y BUILD path/to/EXP-design-vX.Y.zip
```
  The helper copies the zip into `SPARKLE_RELEASES_DIR` (default:
  sibling `../sparkle-releases/` next to this repo), refuses to overwrite a non-identical zip,
  seeds/reuses that folder's `appcast.xml`, writes the matching HTML release
  note, runs Sparkle's `generate_appcast --versions BUILD --maximum-deltas 0`,
  and verifies the generated URL/signature/build shape. Reusing the local appcast
  matters because GitHub release asset URLs include the tag; old entries must
  keep their old `releases/download/vX.Y/` URL while the new entry gets the
  current prefix. Deltas are deliberately disabled until the release flow uploads
  and verifies them too. The helper also unzips the exact archive and runs
  strict deep code-signing plus Gatekeeper checks, so forbidden extended
  attributes on nested Sparkle helpers are caught before upload.
- [ ] Manual equivalent, if the helper ever needs bypassing: drop
      `EXP-design-vX.Y.zip` in the local release folder, make sure that same
      folder contains the previous `appcast.xml`, then run Sparkle's tool
      (found in the SPM artifacts under DerivedData, or a Sparkle release
      download's `bin/`). Use `--versions BUILD` so only the new build gets the
      current GitHub tag prefix:
```sh
generate_appcast \
  --versions BUILD \
  --maximum-deltas 0 \
  --download-url-prefix "https://github.com/tracyapps/EXP-design/releases/download/vX.Y/" \
  --release-notes-url-prefix "https://expdesign.app/" \
  sparkle-releases/
```
  (`--download-url-prefix` applies to the NEW entry; GitHub asset URLs embed
  the tag, so pass the current release's prefix each time.)
- [ ] Release notes: `generate_appcast` picks up an HTML file named like the
      zip (`EXP-design-vX.Y.html`) in the same folder — convert the release
      notes so the update dialog shows what changed. The helper generates this
      from `RELEASE-NOTES-vX.Y.md`.
- [ ] Deploy the website; verify `curl -s https://expdesign.app/appcast.xml`
      shows the new version + `sparkle:edSignature`.
- [ ] Signing sanity: the zip must be the SAME notarized archive uploaded to
      GitHub (byte-identical), or the EdDSA signature won't match. If replacing
      a bad asset, move the stale local copy in `sparkle-releases/` aside first,
      regenerate the appcast from the cleaned zip, then replace the GitHub
      release asset with the same cleaned archive.
- [ ] End-to-end sanity: install the previous network-enabled public build, choose
      **Check for Updates…**, confirm the update prompt appears, install,
      relaunch, and confirm **About EXP [design]** shows X.Y / BUILD.
      Before testing, verify the installed baseline app itself can launch
      Sparkle's installer service:
```sh
scripts/verify_installed_update_baseline.sh
```
      The helper auto-discovers a single installed copy under `/Applications`
      or `~/Applications`; pass an explicit path only if there are multiple
      copies or the app lives somewhere else.
      This matters because Sparkle's installer launches from the CURRENT app. A
      new release zip can be perfectly clean while the already-installed app is
      missing `SUEnableInstallerLauncherService`, the `-spks` / `-spki` sandbox
      exceptions, or has forbidden `com.apple.FinderInfo` metadata. Any of those
      can cause "An error occurred while launching the installer" after download.

## 5. Open the next cycle
- [ ] Back on `dev`, bump to the next `MARKETING_VERSION` / build.
- [ ] Add the `vX.(Y+1) scope` section to `docs/ROADMAP.md`.
