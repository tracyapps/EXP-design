# Release checklist (reusable)

The repeatable path from a green build on `dev` to a tagged GitHub Release.
GitHub auth is off-box, so the owner runs every `git`/`gh` step.

## v1.4 copy/paste path
Use this section for the v1.4 release. The project is already set to
`MARKETING_VERSION 1.4` / build `6`; rerun the prep commands anyway because
they are cheap and catch drift.

Assumption: Xcode exports the notarized/stapled app to:

```text
../releases/v1.4/EXP [design].app
```

The Sparkle archive folder lives next to this repo:

```text
../sparkle-releases/
```

### 0. Prep / verify before Xcode archive
```sh
cd "/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"

VERSION="1.4"
BUILD="6"
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
Export the stapled app to ../releases/v1.4/
```

Important: Sparkle runs inside the sandboxed app, so the exported app must have
outbound network permission. The preflight script checks the Xcode build setting,
and the post-export step below checks the signed app entitlement, strict nested
code signatures, and Gatekeeper assessment.

### 1. Verify and zip the exported app
Run this after Xcode has exported the app:

```sh
cd "/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"

VERSION="1.4"
BUILD="6"
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
`EXP-design-v1.4.html`, updates `website/public/appcast.xml`, disables delta
updates, and verifies the URL/build/signature shape.

```sh
cd "/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]"

VERSION="1.4"
BUILD="6"
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

VERSION="1.4"
ZIP_PATH="../releases/v$VERSION/EXP-design-v$VERSION.zip"

gh release create "v$VERSION" \
  --title "EXP [design] v$VERSION" \
  --notes-file "RELEASE-NOTES-v$VERSION.md" \
  "$ZIP_PATH"
```

If using GitHub in the browser, upload this exact same file:

```text
../releases/v1.4/EXP-design-v1.4.zip
```

Do not re-zip. Sparkle's signature is for that exact archive.

### 4. Deploy + verify
```sh
cd "/Users/tapps/Library/CloudStorage/Dropbox/work/custom-work-tools/apps/EXP [design]/website"
npm run build
```

After deploying the website:

```sh
curl -s https://expdesign.app/appcast.xml | grep -E "1.4|sparkle:edSignature|releases/download/v1.4"
curl -I https://expdesign.app/EXP-design-v1.4.html
```

Final human test for v1.4:

```text
1. Start from the already-installed public v1.3 build.
2. Choose Check for Updates….
3. Confirm Sparkle shows v1.4, installs it, and relaunches.
4. Confirm About EXP [design] shows 1.4 / build 6.
```

This is the first real network-enabled updater proof: v1.3 can fetch the
appcast, so v1.3 -> v1.4 should validate the full prompt -> install -> relaunch
path.

### 5. After v1.4 is live
Back on `dev`, open the next cycle:

```sh
scripts/set_release_version.sh 1.5 7
grep MARKETING_VERSION "EXP [design].xcodeproj/project.pbxproj" | sort -u
grep CURRENT_PROJECT_VERSION "EXP [design].xcodeproj/project.pbxproj" | sort -u
```

Then update `docs/ROADMAP.md` if the v1.5 section needs adjustment, commit on
`dev`, and keep release artifacts out of the repo.

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

## 5. Open the next cycle
- [ ] Back on `dev`, bump to the next `MARKETING_VERSION` / build.
- [ ] Add the `vX.(Y+1) scope` section to `docs/ROADMAP.md`.
