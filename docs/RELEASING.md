# EXP [design] — Releasing the App

This repo is a **monorepo**: the macOS app (`EXP [design]/` + `.xcodeproj`), the
website (`website/`, auto-deployed by Vercel), the design system (`design/`), and
docs (`docs/`) all live together. **Releasing the app is a separate track from the
website** — it does not go through Vercel. This is the runbook.

## TL;DR — the release loop
1. Bump the version (in the Xcode project).
2. Archive → sign (Developer ID) → **notarize** → staple → package as a `.dmg`.
3. Tag `app-vX.Y.Z`, create a **GitHub Release**, attach the `.dmg`.
4. Point the website's Download button at the new release, commit to `website/`
   → Vercel redeploys the site with the new version.

The website and the app never block each other: app artifacts live on GitHub
Releases; the site only changes when you touch `website/`.

---

## One-time setup
- **Apple Developer Program** ($99/yr) — required for the Developer ID certificate,
  notarization, and (if you ever want it) TestFlight. This is the unlock that lets
  the app run on other people's Macs without Gatekeeper blocking it.
- In Xcode ▸ Settings ▸ Accounts, sign in; create a **Developer ID Application**
  certificate (Xcode can do this). Note your **Team ID**.
- Create a **notarization credential** once so `notarytool` can run headless:
  ```sh
  # App Store Connect ▸ Users and Access ▸ Integrations ▸ create an API key (Developer role)
  xcrun notarytool store-credentials EXP-NOTARY \
    --key ~/path/AuthKey_XXXX.p8 --key-id XXXXXXXX --issuer <issuer-uuid>
  ```
- (Recommended, one-time cleanup before the first public build) the bundle id is
  currently the auto-generated `tapps.EXP--design-`. Since there are no users yet,
  now is the free moment to set a clean, permanent id (e.g. `app.expdesign.mac`) in
  the target's Signing & Capabilities. Changing it AFTER release is disruptive.

## Bump the version
Two numbers, both in the Xcode project (Target ▸ General, or the `.pbxproj`):
- **MARKETING_VERSION** = the human version, e.g. `0.2.0` (this is what the in-app
  Feedback reporter shows).
- **CURRENT_PROJECT_VERSION** = the build number, bump every upload, e.g. `2`.

Keep a short **CHANGELOG** (a `## 0.2.0` section here or in a `CHANGELOG.md`) — it
becomes the GitHub Release notes.

---

## Cut a release — the easy path (Xcode, recommended to start)
1. Xcode ▸ **Product ▸ Archive** (Release config).
2. In the Organizer: **Distribute App ▸ Direct Distribution** (Developer ID).
   Xcode 26 signs AND submits for **notarization** in this flow; wait for the
   "Ready to distribute" / notarized state.
3. **Export** the `.app` (or let Xcode export a notarized copy).
4. Package a disk image and staple the ticket:
   ```sh
   # nice DMG (brew install create-dmg) — or just zip it
   create-dmg "EXP-design-0.2.0.dmg" "path/to/EXP [design].app"
   xcrun stapler staple "EXP-design-0.2.0.dmg"
   xcrun stapler validate "EXP-design-0.2.0.dmg"   # should say "The validate action worked!"
   ```
5. Publish the GitHub Release (below).

## Cut a release — the scriptable path (CLI)
```sh
SCHEME="EXP [design]"
VER="0.2.0"
xcodebuild -scheme "$SCHEME" -configuration Release \
  -archivePath "build/EXP.xcarchive" archive

xcodebuild -exportArchive -archivePath "build/EXP.xcarchive" \
  -exportPath "build/export" \
  -exportOptionsPlist "docs/ExportOptions-DeveloperID.plist"   # method: developer-id, teamID, signingStyle: automatic

# notarize the app (or the dmg), then staple
ditto -c -k --keepParent "build/export/EXP [design].app" "build/EXP.zip"
xcrun notarytool submit "build/EXP.zip" --keychain-profile EXP-NOTARY --wait
xcrun stapler staple "build/export/EXP [design].app"

# package + staple the DMG
create-dmg "build/EXP-design-$VER.dmg" "build/export/EXP [design].app"
xcrun stapler staple "build/EXP-design-$VER.dmg"
```
(You can commit a small `docs/ExportOptions-DeveloperID.plist` so the export is
repeatable — ask me and I'll generate it once you have your Team ID.)

## Publish the GitHub Release
```sh
git tag app-v0.2.0            # PREFIX app tags so they're distinct from any site work
git push origin app-v0.2.0
gh release create app-v0.2.0 "build/EXP-design-0.2.0.dmg" \
  --title "EXP [design] 0.2.0" --notes-file CHANGELOG-0.2.0.md
```
GitHub Releases don't trigger Vercel, so this publishes the app without redeploying
the site.

## Update the website download link (the only step that redeploys the site)
- Point the Download button at the release asset. Either a **stable "latest" URL**:
  `https://github.com/tracyapps/EXP-design/releases/latest/download/EXP-design-<ver>.dmg`
  (note: the filename must be predictable, so keep the naming pattern), or update the
  version/URL in `website/` directly.
- Commit that change under `website/` → **Vercel auto-builds and deploys** the site.

---

## Monorepo + Vercel notes
- Vercel builds from `website/` (`vercel.json`: `cd website && npm run build`), but by
  default it **rebuilds on every push to the production branch**, even app-only commits.
  To skip needless site builds, set an **Ignored Build Step** (Vercel ▸ Project ▸
  Settings ▸ Git) so it only builds when `website/` changed:
  ```sh
  # exit 1 = build, exit 0 = skip
  git diff --quiet HEAD^ HEAD -- website/ ; [ $? -eq 1 ]
  ```
- Tag convention: **`app-vX.Y.Z`** for app releases keeps them clearly separate from
  anything web-related and makes an automated release workflow easy to target.

## Later: automate with GitHub Actions (optional)
A workflow on `app-v*` tags can archive → sign → notarize → package → create the
Release on a macOS runner. It needs three repo **Secrets**: the Developer ID cert
(`.p12`, base64), its password, and the notary API key. It's a real setup step but
fully repeatable. Say the word and I'll scaffold `.github/workflows/release-app.yml`
with placeholders + notes.

## Distribution options recap
- **Developer ID + notarized DMG on GitHub Releases** (this doc) — best for a direct-
  download research app; friends download from the site/Release.
- **TestFlight** (App Store Connect) — alternative/additional for testers; auto updates
  + crash reports + built-in feedback, but a separate build/distribution path. Same
  $99 Developer Program prerequisite.
