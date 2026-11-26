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
- [x] Freeze the reviewed source from the owner’s archive session, including
  new Swift sources and website assets. The release source snapshot is
  `9e1c443b24f35ca96fda547e26533f70c2d1edc5` on `release/v2.9`.
  The owner archived from the working tree before this snapshot was committed.
- [x] The owner archived and exported the validated app to
  `../releases/v2.9/EXP [design].app`. Xcode recorded Developer ID distribution as
  uploaded and ready. The archive and export share Mach-O UUIDs for the app,
  thumbnail extension, helper and Sanaa runtime on both architectures. The
  app and thumbnail report 2.9 / 20.
- [x] The Developer ID export carries a stapled notarization ticket. The
  strict signature, entitlement, font payload, universal architecture and ZIP
  extraction checks pass. The ZIP is **13,882,125 bytes**, SHA-256
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

- [x] Upload the exact ZIP to the [GitHub release draft](https://github.com/tracyapps/EXP-design/releases/tag/untagged-34b8d1ecf485ce7b6bf0).
  GitHub reports the same size and SHA-256. The draft targets the frozen
  release source commit. A local copy is in `output/release-review/v2.9/`.
- [x] The owner signed the ZIP in Terminal. The Ed25519 signature independently
  verifies against the app’s `SUPublicEDKey`. The build 20 feed entry uses that
  signature, the ZIP byte count, and the exported app’s version and minimum OS.
  All six prior feed entries are preserved byte for byte.
- [x] Published [v2.9 on GitHub](https://github.com/tracyapps/EXP-design/releases/tag/v2.9)
  on November 25. The public tag points to the frozen source. The public ZIP
  download matched the exact signed ZIP before the website deployment.
- [ ] Verify the live feed and the Design Language section and News story.
  Confirm a previously installed v2.8 updates through **Check for Updates**.
