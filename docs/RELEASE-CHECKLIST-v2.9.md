# EXP [design] v2.9 / build 20

The owner approved the native Design Language features on November 25, 2026.
Color modes, linked spacing and dimension tokens, the live Guide and its
exports, Table / Code, and Find in Document are the release focus.
Script-font clipping and text box trim move to a follow-up together.

## Release candidate

- [x] Confirm project, thumbnail and runtime versions at 2.9 / 20. Sparkle
  preflight passes with public v2.8 still in the checked-in feed.
- [x] Design-token suite passes all 46 checks. Canvas and interface checks
  pass. Website production builds pass against the current feed and a local
  v2.9 feed fixture. React render checks confirm that the homepage and News
  switch to the v2.9 story at build 20 and the screenshot files are valid WebP.
- [ ] Check the release feature on a desktop and phone-width browser. Local
  Chromium could not register its Mach port from the restricted session.
- [ ] From a normal macOS session, run `scripts/check_release_review.sh`.
  WebKit, storage, effect export, Mesh and SVG tests failed the same way on the
  v2.8 tag in the restricted session. Xcode stopped before compiling because
  SwiftPM could not write `ManifestLoading/sparkle.dia`.
- [ ] Freeze the reviewed working source, including new Swift sources and
  website assets. Record the commit used to build the archive.
- [x] The owner archived and exported the validated app to
  `../releases/v2.9/EXP [design].app`. Xcode recorded Developer ID distribution as
  uploaded and ready. The archive and export share Mach-O UUIDs for the app,
  thumbnail extension, helper and Sanaa runtime on both architectures. The
  app and thumbnail report 2.9 / 20.
- [x] The Developer ID export carries a stapled notarization ticket. The
  strict signature, entitlement, font payload, universal architecture and ZIP
  extraction checks pass. The archive is **13,882,125 bytes**, SHA-256
  `db2cc3ee3fe48a5d2bfcca79060fd1ae55a1f1de2c296953274f928beea5620e`.
  The extracted notarization ticket matches the export byte for byte. This
  session couldn't independently rerun Gatekeeper or `stapler validate`; the
  same OS service errors occurred for the previously validated v2.8 app.

From the repo root, with the notarized app exported to `../releases/v2.9/`:

```bash
set -euo pipefail
stage="$(cd ../releases/v2.9 && pwd)"
app="$stage/EXP [design].app"
zip="$stage/EXP-design-v2.9.zip"
test ! -e "$zip"
bash scripts/verify_release_candidate.sh "$app" 2.9 20
bash scripts/verify_font_distribution.sh "$app"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$app" "$zip"
roundtrip="$(mktemp -d)"
ditto -x -k "$zip" "$roundtrip"
bash scripts/verify_release_candidate.sh "$roundtrip/EXP [design].app" 2.9 20
wc -c < "$zip"
shasum -a 256 "$zip"
```

## Publication and installed update

- [ ] Sign the verified ZIP with Sparkle. The packaged signer reports
  `100001` when trying to access the Keychain in this session. Run
  `sign_update -p <verified-zip>` from the owner’s Terminal and independently
  verify the public signature against the app’s `SUPublicEDKey`.
- [ ] Use a fresh `SPARKLE_RELEASES_DIR` and run
  `scripts/generate_sparkle_appcast.sh 2.9 20 <verified-zip>` from the repo root.
  Check the feed against its prior version, keeping all older items, and
  verify the Ed25519 signature against the shipped Sparkle public key.
- [ ] Publish the verified ZIP on GitHub at `v2.9`, using the archive’s source
  commit for the tag. Verify the public download’s size and digest before
  deploying the revised appcast and notes to expdesign.app.
- [ ] Verify the live feed and the Design Language section and News story.
  Confirm a previously installed v2.8 updates through **Check for Updates**.
