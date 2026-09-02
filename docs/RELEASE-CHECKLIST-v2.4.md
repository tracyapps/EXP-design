# EXP [design] v2.4 / build 15 release checklist

The exact path from the owner-accepted v2.4 source to the public GitHub,
Sparkle, and website release. Stop at the first failure; never tag, upload, or
deploy around a failed gate. This adapts the proven v2.3 release path for v2.4.

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

### Wave A — carry-in slice (committed `a803df0`) — ✅ owner-verified 2026-08-27

- [x] BUG-049 — point-edit bounds, hit-testing, and shadow paint bounds.
- [x] BUG-050 — immediate arrow nudge from Layers, docked and floating.
- [x] BUG-051 — tray palette ordering across displays, both activation routes.
- [x] BUG-052 — Reveal in Layers / Expand · Collapse All against the live panel.
- [x] FEAT-047 — Auto-select on and off, including buried-layer drag and undo.
- [x] FEAT-027 — recursive Convert to Outlines / Convert to Path / Outline Stroke.

### Wave B — Sanaa core

First live FEAT-048 gate run 2026-08-26 was **partial/failed**: the disabled phase
created a probe artboard, the enabled happy path created its expected artboard,
and the original shell verifier miscounted both because it counted JSON-RPC
envelope ids and did not parse escaped tool payloads. The verifier is repaired;
the rebuilt rerun passed all **11/11 automated cases**. Owner manual MCP approval,
per-document consent, applied change, and named one-step undo/redo passed
2026-08-26. The final owner pass confirmed a real-client three-artboard batch,
save/reopen, Quick Look, PNG/SVG/Handoff HTML fidelity, appearance, and VoiceOver.
Both FEAT-048 gates are complete.

FEAT-049's canvas-only Codex route, success-backed receipts, Select/Go commands,
highlight/Reduce Motion behavior, and VoiceOver announcement implementation are
built as of 2026-08-26. Automated packaged IPC is **7/7** with **4/4** negative
trust/protocol gates, a signed Debug build verifies deeply, and both the sandboxed
EXP→helper→Codex stream and app-facing transcript/clear probes pass. The unchecked
lines below deliberately remain owner/distribution gates.

First owner canvas pass found the Codex MCP server's `auto` approval mode could
silently reject a read in the headless runtime. It now uses `approve` only for the
exact seven-tool EXP allowlist; EXP still owns every write gate. Fresh packaged and
signed-sandboxed `list_artboards → get_artboard` regressions pass with no prompt.
Connection/setup now lives in Settings ▸ Sanaa, with direct Handoff/Sanaa panel
links, per-client canvas status, and optional account/plan/rate-limit/token-activity
details sourced from Codex app-server. The packaged 7/7 contract now also repeats
an explicit account-status refresh and received all three optional detail surfaces
on the owner's signed-in Codex account.

- [x] FEAT-048 — socket create/undo, the full gate matrix, and a real-client batch
      that saves, reopens, and exports identically to hand-drawn content.
- [x] FEAT-048 — with Sanaa disabled, EXP shows no trace of it anywhere.
- [x] FEAT-049 — bundled Sanaa Runtime passes signing/notarization and restricted
      IPC gates; Codex account/setup, Send, streamed reply, Stop, reconnect/resume,
      signed-out/host-missing failures, and canvas-only tool allowlist are proven.
- [x] FEAT-049 — conditional Sanaa panel, transcript order/scrolling, explicit
      tool/update receipts, highlights, announcements, Reduce Motion variant,
      Settings connection/usage layout, jump links, and multi-client status.
      **Owner-verified 2026-08-27**: started a design from a blank canvas through
      Sanaa and edited every piece it drew once content existed on the canvas.
- [x] FEAT-050 — placement sheets, enablement matrix, keyboard and VoiceOver.
      Built 2026-08-31; Debug build + prompt contract probe pass. **Owner signed
      off the complete feature 2026-09-02 and chose broad public testing over
      further speculative pre-release edge-case work.**

### Wave C — vector toolset, and the export fidelity bug

Run `docs/EXPORT-FIDELITY-TEST-FIXTURES.md` first — it is self-contained and needs
no code change. Both fixes are BUILT 2026-08-27 (BUG-053 in full — see its BACKLOG
implementation notes, including two measured-and-fixed PDF Porter-Duff defects —
plus BUG-054's silent fail-open); `scripts/verify_effect_export_coverage.sh` is
their automated gate and currently passes all 8 checks. The owner accepted both
fixes 2026-09-01.

- [x] BUG-057 — on a page with loose shapes, text, and a group on the wall,
  toolbar Add, paste, command Duplicate, and a Sanaa same-page variation place
  new artboards beyond the loose material with normal spacing. Confirm copied
  boards keep their relative layout, Undo is one step, hidden wall layers do not
  block placement, and drawing an artboard around loose work still encloses it
  intentionally. **Owner-verified 2026-08-31: all paths pass.**

- [x] BUG-053 — Fixture A run; `noise` and `dissolve` render in PNG, JPG, and PDF
  as they do on canvas and in SVG. The hard-edged dark rectangle in the owner's
  original file is accounted for, not just gone. Re-export the original light-leak
  file against the canvas screenshot. **Owner verified resolved 2026-09-01.**
- [x] BUG-054 — Fixture B run; a blur renders at the same model-space radius on
  canvas at every zoom and in export at every scale, and an unrenderable blur
  degrades in resolution rather than in radius, never silently. NOTE: the
  degrade-not-drop half was fixed 2026-08-27. **Owner verified the shipped
  behavior resolved 2026-09-01; no residual release gate remains.**
- [x] BUG-056 release decision — the original opaque/stepped falloff plus layered
  opacity/texture defects are fixed. The owner accepted the remaining colored
  annulus around unusually layered radial glows as an edge case and deferred its
  focused fixture/root-cause work to v2.5 on 2026-08-31. Disclose the limitation
  in release notes; it is not a v2.4 release gate.

- [x] FEAT-025 — owner verified 2026-08-25 (core behaviour + the flagged
      select-and-drag change), then reconfirmed for release 2026-09-01.
- [x] FEAT-025 regression — direct-select moves whole objects in one undo step; anchors and
      handles still win; Option-drag, snapping, nested and rotated ancestors, locked
      objects, and click-without-drag all still behave. BUG-028 is NOT claimed fixed.
      Look hard at the changed behaviour: pressing a DIFFERENT object now selects
      AND drags in one gesture. **Owner reconfirmed working 2026-09-01.**
- [x] FEAT-029 — owner verified 2026-08-25 (drawing, corners, fast strokes, live
      preview), then reconfirmed for release 2026-09-01.
- [x] FEAT-029 regression — pencil output is an ordinary, fully point-editable path; anchor
      count is sane; the fidelity slider makes an obvious difference at both ends;
      one stroke is one undo step; a click leaves nothing behind. Watch the
      proximity close (12pt / 8 samples) — most likely thing to feel wrong.
      **Owner reconfirmed working 2026-09-01.**
- [x] FEAT-028 live-text stroke — owner verified working 2026-09-01. Preserving
      the stroke through Convert to Outlines was never implemented and is now an
      unplanned optional follow-up rather than part of the closed feature or a
      v2.4 gate.
- [x] FEAT-030 handle pairing — owner verified 2026-08-26 (pen tool feel + the
      behaviour option). Covers PAIRING only.
- [x] FEAT-030 release decision — owner reconfirmed the feature resolved 2026-09-02;
      the accepted derived-handle + Option workflow makes separate explicit
      balanced/smooth/corner conversion commands unnecessary for v2.4.
- [x] BUG-048 — owner verified 2026-09-02 that dash behavior works and exported SVG
      renders correctly in Preview and browsers. Illustrator's differing result is
      downstream interoperability, not an EXP release defect.
- [x] BUG-034 release decision — Stage 2 is removed from v2.4 and parked at the
      lowest priority with no planned release or retry date. Stage 1's truthful
      disclosure remains. Do not re-enter the risky renderer work unless the owner
      explicitly reprioritizes it.
- [x] BUG-055 release decision — logged 2026-08-26, NOT fixed and not scoped into v2.4. Listed here
      only so the release notes do not imply shadow spread is now uniformly
      correct: SVG export still drops INNER-shadow spread that canvas and PNG
      render.

### Wave D — Sanaa companion

- [x] FEAT-051 — copy-first guided setup from Settings and Sanaa's empty state.
      The fresh built UI's accessibility tree was walked through with in-app
      Codex, Claude Desktop, and neither on 2026-09-02; each path is honest about
      credentials, connection scope, verification, and what to install. Claude
      Code and generic MCP reuse the already-verified copied setup formats.
- [x] FEAT-052 release decision — optional in-app canvas avatar deferred from
      v2.4 by owner decision 2026-09-01; no implementation or test gate remains.
- [x] FEAT-053 — machine-readable agent etiquette guide is bundled, exposed as
      both `exp://sanaa/guide` and `get_sanaa_guide`, and required by the packaged
      runtime before writes. Focused source/resource/runtime gate passes. The
      owner's real critique, direction, repetitive-work, completion, variation,
      and exact-action sessions supply the cold-agent behavior evidence.
- [x] FEAT-054 — guidance pack v2.0.0: 24 served modules and the changelog are
      byte-identical in source/bundle/live reads; INDEX stays load-on-demand;
      directions/procedural/bulk/applied-a11y/style-grounding cold-agent cases
      behave as specified; one non-Codex client and owner appearance pass.
      **24/24 live resource/tool reads, packaged Codex, and owner-tested
      behavior/appearance pass 2026-08-31. The facts-backed critique behavior
      passed the owner's purpose-built mockup on 2026-09-02, including gradient
      contrast.** A provider-neutral MCP socket client (outside the bundled Codex
      adapter) passed all 24 resource/tool reads and error cases on 2026-09-02.
- [x] FEAT-055 — computed facts stay measured, bounded, criteria-cited, and
      explicit about `notAssessed`; both tool allowlists and negative trust gates.
      Saved-document golden/no-write, source registration, adjacent regressions,
      fresh Debug/Release builds, rebuilt-app live route, packaged Codex, and
      owner artboard/selection behavior all pass. **Owner verified 2026-09-01;
      closed.**
- [x] FEAT-050 amendment — Critique this… and Design directions… starters use
      the facts and guidance modules without auto-sending or changing consent.
      **Built 2026-09-01:** both menu surfaces are reordered; the two read-only
      drafts require live-scope confirmation, facts before analysis, and bounded
      task guidance, and explicitly forbid `apply_edits`. Fresh unsigned
      universal Debug/Release builds + expanded prompt probe pass. **Owner-verified
      2026-09-02 on the real critique mockup: every intentionally planted issue
      was caught, including gradient contrast; the owner rated the
      critique/guidance pass “perfect.”**
- [x] BUG-058 — with Sanaa and other trays overlapping the Inspector, every custom
      colour/paint/font/state-name/gradient-stop popover and EXP field tip stays above
      all trays; native menus/dropdowns/context menus do too. Escape/outside-click,
      keyboard focus, glued trays, deactivation, and two-display behavior are unchanged.
      Source gate + Debug/Release builds pass; **owner verified resolved 2026-09-02.**
- [x] BUG-059 — an active full-response reader rises above floating trays and
      returns below them when inactive. Focused response-window gate passes;
      owner verified the overlapping response experience resolved 2026-09-02.
- [x] FEAT-061 — every assistant reply has a compact rendered preview and Open full
      response; the normal resizable reader renders/selects/copies Markdown, reuses one
      window per reply, updates while streaming, opens only web/mail links externally,
      restores focus, and closes on session disable. Run narrow/single-window,
      malformed/long/short response, VoiceOver, and appearance gates. Debug parser/link
      probe and Debug/Release builds pass; **owner verified the real report/read/action
      experience 2026-09-02 as passing or exceeding every test.**
- [x] FEAT-056 — structured critique report: numbered rail, stable human aliases with
      hidden full IDs, exact Show on canvas, Explore-to-composer without auto-send,
      stale/deleted/multi-document handling, VoiceOver order, and zero writes.
      **Owner verified 2026-09-02: report passed with flying colors, one-click
      actions were easy, and Show on canvas worked correctly.**

### Accessibility (WORKING-AGREEMENT: verified, not remembered)

- [x] Every new control has a VoiceOver label, hint, and sensible focus order.
- [x] Every new command is fully keyboard-operable with no pointer-only path.
- [x] Light, dark, increased contrast, reduced transparency, and Reduce Motion.
- [x] Any export-semantics change re-verifies the ARIA/WCAG contract in full.

Owner acceptance through 2026-09-02 covers the shipped Sanaa, vector, popover,
reader, and appearance paths. The final setup sheet was additionally walked from
the fresh built app's accessibility tree across its three distinct branches; its
controls use semantic system surfaces and expose labels/hints. The full semantic
HTML contract/package suites pass after the reviewed manifest-only rebaseline.

## 1. Freeze and verify the accepted source

- [x] Every wave gate in §A below is green.
- [x] Anything cut from v2.4 is explicitly deferred in ROADMAP/BACKLOG, not silently dropped.
- [x] `RELEASE-NOTES-v2.4.md` describes shipped behavior and honest limits.
- [x] `MARKETING_VERSION = 2.4` and `CURRENT_PROJECT_VERSION = 15` in every config.
- [x] Working tree contains only intended v2.4/release changes.

Verification snapshot, 2026-09-02: every scripted regression below passes. The
handoff manifest was re-reviewed under Xcode 26.3 / Swift 6.2: semantic HTML, CSS,
README, fidelity rows, entry hashes, counts, and deterministic repeat output remain
correct; Foundation's deterministic JSON key order was the only byte change, and
the manifest golden is explicitly rebaselined. The Sanaa setup, etiquette,
provider-neutral knowledge, saved/live facts, response/action, transient-window,
and packaged-runtime gates pass. Clean unsigned universal Debug and optimized
Release builds plus the production website build pass. The appcast correctly
remains without v2.4 until the notarized zip exists.

Run:

```sh
cd "$ROOT"
test "$(git branch --show-current)" = "main"
test -f RELEASE-NOTES-v2.4.md
test -f docs/RELEASE-CHECKLIST-v2.4.md

scripts/set_release_version.sh "$VERSION" "$BUILD"
scripts/verify_backlog_ids.sh
scripts/verify_nested_component_graph.sh
scripts/verify_anchored_relationships.sh
scripts/verify_canvas_pages.sh
scripts/verify_xd_importer.sh
scripts/verify_figma_importer.sh
scripts/verify_semantic_html_contract.sh
scripts/verify_semantic_html_package.sh
scripts/verify_svg_token_bridge.sh
scripts/verify_effect_export_coverage.sh
scripts/verify_codepen_package_import.sh
scripts/verify_rendered_html_importer.sh
scripts/verify_rendered_html_webkit.sh
scripts/verify_storybook_package_import.sh
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
(cd website && npm run build)

DERIVED_DATA="$(mktemp -d /private/tmp/exp-v2-4-release-build.XXXXXX)"
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

- [x] Create/open/edit/save/reopen, pan/zoom/select/move/resize, undo/redo/export.
- [x] Workspace presets and connected-panel glue/pop-apart across displays.
- [x] Font search/filters/height, text memory, keyboard, and VoiceOver.
- [x] Line caps/markers and SVG browser rendering.
- [x] Gradient endpoints/stops, selected-stop and Inspector-angle sync.
- [x] Compact/Standard/Large type, contrast, Case, tooltips, effect disclosures.
- [x] Owner's configured test suite is green.

Final owner record, 2026-09-02: all tested behavior passed or exceeded the
owner's checks. FEAT-050/056/061, BUG-048/058/059, and FEAT-030 received explicit
final signoff; earlier wave receipts above cover the remaining paths. The owner
authorized the release push and chose broad public testing over speculative
additional FEAT-050 edge-case work.

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
  "$ARCHIVE_PATH/Products/Applications/EXP [design].app" "$VERSION" "$BUILD"
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
scripts/verify_release_candidate.sh "$CLEAN_APP" "$VERSION" "$BUILD"

ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "$CLEAN_APP" "$ZIP_PATH"

CHECK_DIR="$(mktemp -d)"
ditto -x -k "$ZIP_PATH" "$CHECK_DIR"
scripts/verify_release_candidate.sh "$CHECK_DIR/EXP [design].app" "$VERSION" "$BUILD"
rm -rf "$CHECK_DIR" "$CLEAN_DIR"
shasum -a 256 "$ZIP_PATH"
```

The zip is immutable: the same bytes back Sparkle's signature, the GitHub asset,
and the public download.

## 7. Generate and commit release metadata

```sh
cd "$ROOT"
SPARKLE_RELEASES_DIR="$SPARKLE_DIR" \
  scripts/generate_sparkle_appcast.sh "$VERSION" "$BUILD" "$ZIP_PATH"
scripts/verify_sparkle_setup.sh "$VERSION" "$BUILD"
cmp -s "$ZIP_PATH" "$SPARKLE_DIR/EXP-design-v$VERSION.zip"

RELEASE_DATE="$(date +%F)"
RELEASE_DATE="$RELEASE_DATE" perl -0pi -e '
  s{^## v2\.4 — "Sanaa, and a vector toolset that grows up" \(in development\)$}
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
  --title "EXP [design] v2.4 — Meet Sanaa." \
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
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$LIVE_APPCAST"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$LIVE_APPCAST"
grep -q "releases/download/v$VERSION/EXP-design-v$VERSION.zip" "$LIVE_APPCAST"
grep -q 'sparkle:edSignature=' "$LIVE_APPCAST"
rm -f "$LIVE_APPCAST"

curl -fsSIL "https://github.com/tracyapps/EXP-design/releases/download/v$VERSION/EXP-design-v$VERSION.zip" >/dev/null
curl -fsSI "https://expdesign.app/EXP-design-v$VERSION.html" >/dev/null
gh release view "v$VERSION" --json tagName,name,isDraft,isPrerelease,assets,url
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

- [x] Notarized/stapled universal app exported from Organizer.
- [x] Shipping ZIP passed direct and unzip-roundtrip release-candidate checks.
- [x] ZIP SHA-256:
      `9174ea9686ff20ab81a3c39ed7175cff0df3d0ed4a3c3fc36b1a08b44fe6b389`.
- [x] Annotated tag `v2.4` points at release-metadata commit `90903de`.
- [x] GitHub release is public and its downloaded asset matches the local ZIP.
- [x] Production appcast, v2.4 HTML notes, and Sanaa homepage story are live.
- [ ] Public v2.3 → v2.4 Sparkle update proof is green.

## Next development cycle

- [x] Opened v2.5 development at `MARKETING_VERSION 2.5` /
      `CURRENT_PROJECT_VERSION 16` across the app, thumbnail extension, and
      bundled runtime configurations on 2026-09-02. This does not alter the
      immutable v2.4/build 15 release artifacts or public appcast entry.
