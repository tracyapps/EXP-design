# EXP v2.8 — owner release checks

**Owner acceptance recorded November 9, 2026 — 2.8 / build 19.** The owner
reports that all checks in this checklist pass, explicitly including package/token
import fidelity, multiple shadows, gradients and the November 6 saved-color/
gradient editing follow-up. This is owner-reported hands-on evidence; it does not
invent individual automation receipts or simulated power-loss/cloud-sync results.
The previous Full Keyboard Access environment limitation remains retained unless
specifically superseded by an enabled-system result. Publication and the installed
Sparkle update/relaunch are separate gates in RELEASE-CHECKLIST-v2.8.md.

Prepared November 4 for testing beginning November 5, with November 6 follow-ups.

The October 29 crash/paint-editor/eyedropper fixes and November 3 shadow-picker fix
were already owner-accepted. Section B is a short regression pass on the combined
build, not a claim that those earlier acceptances were missing.

## A. Start here

1. Run the **EXP [design]** scheme in Xcode. About should say **2.8 / build 19**.
   Keep the installed public v2.7 available separately if you want the downgrade
   export check. Do not replace it with an unsigned test build.
2. The test kit is in `output/release-review/` beside this project's sources.
   It contains `EXP-release-review.design`, an equivalent `.designpkg`, three
   preview PNGs, `HTML-import/`, `Token-library/` and a newer-version warning file.
3. Duplicate the kit's test document in Finder and open the duplicate from EXP.
   Use the document's named artboards and Layers names to locate each case.
   These fixtures are disposable; no personal/client document is needed.
4. Keep this checklist open. Mark each case PASS / FAIL / NOT RUN and note the
   build/date. If a case fails, record the exact action and message; leave its
   dependent checks pending. Screenshots are useful for visual differences.

If the kit needs regenerating, from the project folder run:

```sh
bash scripts/generate_release_review.sh
```

The generator refuses to overwrite an existing output folder, so it cannot erase
your test edits. To choose a fresh destination, run:
`bash scripts/generate_release_review.sh /tmp/EXP-review-fresh`.

## B. Previously accepted fixes — combined-build smoke pass

- [x] **Shadow focus crash.** Artboard 01 → select **Six shadows — focus and
  swatch repro**. Open one shadow color, focus its HEX field and type a valid
  color. Click another shadow's swatch directly. Repeat across all six, including
  Alpha/RGB/code fields. Expected: fields commit normally, popovers exchange,
  no AppKit exception or crash. Undo should restore the changed color.
- [x] **Popover lifetime.** Open the gradient or mesh picker, click a focusable
  segmented control, dismiss it and click its original floating panel. Repeat
  several times. Expected: no crash and the panel still responds.
- [x] **Editor scope.** With the gradient picker open, drag its canvas handles;
  repeat for mesh points. Expected: the editor stays open during those edits.
  Select a different layer, switch tools or click an unrelated panel control.
  Expected: it closes. Switch to another app: it does not cover that app.
- [x] **Font focus.** Select **Font field — change size…**, edit the font size,
  then open the family picker directly. Expected: no crash; typing, selecting
  and dismissing still work.
- [x] **Source-editor focus.** Open the image component source from artboard 03.
  Edit a field, then open the component-state **Custom…** popover. Expected:
  no crash, fields commit, Cancel returns to the source editor and its controls
  still respond. Repeat a paint-picker open/close in that window.
- [x] **Empty path.** Artboard 02 → in Layers, select **Empty path — select via
  Layers** (it is deliberately invisible). Open Fill/gradient controls, switch
  selection and export the artboard. Expected: no crash or invented artwork.
- [x] **Folder eyedropper.** Select **Plain folder — eyedropper target**, press
  **i** and sample the teal rectangle on board 01. Expected: the visible direct
  child and deep nested child recolor. **Locked child** remains blue. Reveal
  **Hidden child** in Layers after sampling: it remains violet; hide it again.
  Undo and Redo should each act as one operation. Type `i` in a layer rename or
  text/code field: it types a letter rather than activating the eyedropper.

## C. FEAT-082 — owner-accepted November 9

Use a new document so the category count is unambiguous.

- [x] File → **Import Library Tokens…** → choose the kit's **Token-library**
  folder. Preview reports **27 tokens / 10 colors** and identifies `tokens.css`.
  Confirm Import. No source files should change.
- [x] In Design Language, inspect **Start 2.0** in list view. Source variable
  names are visible. `color-bg` retains its alias and dark value; swatches with
  dark values have the small dark corner chip.
- [x] Expand its non-color tokens. Spacing/font/shadow names are retained;
  unsupported expressions/aliases are marked read-only, not silently flattened.
- [x] Export Design Language CSS. It retains `--color-accent` and
  `--color-accent-strong`, not newly generated variable names.
- [x] In Settings → Document → Design Language, resize Settings from a corner.
  Double-click the `color-accent` swatch. The picker starts with the current
  color. Try Reset and Cancel, then reopen and save a new value. Undo from the
  document restores the original swatch. Redo restores the edit.
- [x] Right-click the accent in the Design Language panel and choose **Edit Color…**.
  Double-clicking there still applies the color to the selected layer. In Settings,
  right-click a swatch for **Edit Color…** or **Copy Value**. The `color-bg` alias
  remains read-only and shows a lock in Settings.
- [x] In Settings, sort by Name, Value and Category. Click each heading again to
  reverse direction. Switch the Value menu between HEX and RGB/A and copy a value
  into a text field. Check that the full value pastes, including transparency.
- [x] With the accent edit saved, import the same folder again. The preview
  says the local edit is kept. Confirm and verify the edit survives. Undo works
  for imports and refreshes. The source CSS still contains the original value.
- [x] Save as `.design`, close and reopen. Names, aliases, dark values and your
  local edit remain. Repeat through a package copy once section E passes.
- [x] VoiceOver reads a token row's name, kind/value and read-only state.

Detailed original acceptance: COMPONENT-SYNC-v2.8.md → Owner verification.

### November 6 follow-up checks

- [x] Open Settings using Command-comma and drag a corner wider and taller.
  Close and reopen it from the Design Language Settings button. Check the Sanaa
  and Handoff Settings buttons too if you use detached panels.
- [x] Save a solid, a linear gradient and a Mesh paint in Design Language. The
  panel should show one entry under Colors and two under Gradients. Right-click
  either gradient for **Edit Gradient…**. Settings swatches open the same editor.
- [x] In the saved-gradient editor, change a stop, its position and the angle.
  For a radial gradient, also change center/radii. For Mesh, change a point
  color and radius. Try Reset and Cancel, then reopen and Save. Document Undo
  restores the entire previous paint in one step. Double-click in the panel
  continues to apply the saved paint to a selected layer.
- [x] Select the long gradient or Mesh CSS value in Settings. It stays within
  its column. Copy still includes the whole value, and the neighboring Category
  and Delete controls remain usable.

November 6 automated evidence covers native window resizing, opening solid,
linear and Mesh editors, long-value clipping during selection, and detached-panel
Settings routing. Both UI tests passed. The Mesh rendering/round-trip suite also
passed, including the new saved-library grouping assertions. Native receipts and
the inspected screenshot are in `output/a11y/design-language-20261106/native/`.

## D. Import fidelity — tonight's changes

- [x] Open **HTML-import/index.html** in a browser as the visual reference.
  In EXP use File → **Import HTML/CSS…** on that same file; select a desktop
  viewport. The HTML is already built; no install/build commands are needed.
- [x] **Outer shadows:** first sample has both red and blue shadows, with red
  above blue in overlapping areas. Inspect the shape's Effects list: two editable
  outer shadows, not a screenshot or one collapsed effect.
- [x] **Mixed stack:** second sample has two inset shadows and one outer shadow.
  Red is above blue inside. Counts, colors, offsets, transparency and ordering
  remain after saving/reopening. The fixture uses zero inset spread intentionally;
  nonzero inset-spread export remains the separately recorded BUG-055 limitation.
- [x] **Shadow roots:** both component cards retain their internal surfaces,
  buttons and text. First says **Assigned label / Assigned body**; second says
  **Fallback label / Fallback body**. Each has **Fallback detail / Nested leaf**.
  Text is editable, appears once and is placed like the browser.
- [x] Search Layers/text for **Unassigned ghost** and **Hidden shadow ghost**.
  Neither appears as visible imported artwork. There are two distinct component
  button nodes; selecting/editing one does not select/edit the other.
- [x] Open the Import Report. It identifies static shadow/slot capture and
  unavailable closed-root/ElementInternals evidence. It must not claim live
  component behavior or a complete accessibility relationship reconstruction.
- [x] Save/reopen, then export PNG, SVG and Semantic HTML. Compare against EXP
  and the reference. Record any difference and the export's fidelity report.
  Browser button toggling demonstrates source behavior only; EXP remains static.

## E. Opt-in package storage — owner-accepted November 9

The new **`.designpkg`** is a macOS document package containing model JSON and
assets. Existing `.design` / `.exp` files keep their JSON format. The package
storage version is 1; the document model remains schema 6. The public v2.7 app
cannot open a package; use **Save a Legacy JSON Copy…** for it.

- [x] Open the kit's ordinary `.design`. Make a small edit and Save. It remains
  a regular JSON file and reopens normally. No automatic conversion occurs.
- [x] File → **Save a Package Copy…**, choose a new name. Finder reveals the
  saved copy. The original document stays open and unchanged by the copy action.
  Open the new `.designpkg` explicitly before continuing these checks.
- [x] Finder treats `.designpkg` as one document; double-click opens EXP.
  If it appears as a plain folder or has no association after Xcode Run, record
  that rather than treating the Finder gate as passed. Quick Look should show
  the first artboard, as it does for `.design`.
- [x] Artboard 03: both images and the component instance match the original.
  Open the image component source and inspect the image pattern in the pattern
  library. Their artwork is also intact.
- [x] Rename a layer and Save several times. Move an image, Save, Undo, Save,
  close/reopen. Duplicate and delete an image; Undo; Save. Expected: no missing
  images, broken source/pattern links or changed appearance.
- [x] Save, close the package and reopen it from Finder. Repeat in a second
  window. Check Undo/Redo in each editing context and ordinary document routing.
- [x] Copy/move the closed package to a different folder and open it. It must
  not need the original location or neighboring files.
- [x] From the package, File → **Save a Legacy JSON Copy…** under a different
  name. Open the exported `.design` in current EXP and, if available, public
  v2.7. All supported artwork/images remain. Never point this copy action at
  the document already open; it should ask for a different destination.
- [x] On a disposable package, try File → Revert To → Browse All Versions
  after multiple saved edits (if macOS offers versions). Restored artwork and
  images must be complete. Mark NOT RUN if no saved versions are available.
- [x] Use a copy of a real image-heavy document for Save a Package Copy and
  repeated edits. Note any stalls and diagnostic logs. Automated wrapper reuse
  does not by itself establish reduced physical disk writes or smooth autosave.

Missing/corrupt asset, unsafe path, unsupported package version and failed-copy
write cases run automatically. The original codec suite does not simulate power loss or cloud sync. November 9
adds a separate AppKit safe-writer fault probe: disposable process interruption
at partial/complete staging, actual full-volume Save/Autosave, retry, and denied
writes all pass (RELEASE-CHECKLIST-v2.8.md). The owner separately accepts this
native workflow checklist; physical hardware failure/cloud sync remain unclaimed.

## F. Newer-version warning and accessibility

- [x] Open **Newer-version-warning.design**. It is a deliberately marked future
  file with otherwise ordinary artwork. Warning appears once and offers **Keep
  a Copy of the Original…**. Save that copy separately. In Terminal, `cmp` with
  the supplied file should report no differences. Continue opens the document.
  Do not use this file as the main editing fixture.
- [x] Repeat the main workflow with light/dark appearance and your interface
  text-size setting. Color fields, effect rows and menus remain legible/unclipped.
- [x] Keyboard and VoiceOver: reach the import/copy menu commands, dismiss
  dialogs, edit a color and return to the canvas without trapped or lost focus.
  Respect Reduce Motion / Increase Contrast / Reduce Transparency preferences.
- [ ] Full Keyboard Access was unverified in v2.7 because macOS would not enable
  it. Retain that observation; if available now, test it and record the result.

## Automated checks and results

From the project folder:

```sh
bash scripts/check_release_review.sh
```

This runs focused importer/shadow/WebKit/storage/token/manifest checks, Handoff
and effect-export regressions, Mesh rendering/grouping, SVG token and source-bounds checks, a Debug
app/thumbnail build, whitespace and backlog-ID validation. It keeps going after
a failure and exits nonzero if any step fails. Full logs and `summary.txt` are
stored under `output/release-review-checks/run-…/`. No hosted services or owner
files are changed. Existing compiler warnings remain visible in the logs.

November 4 automated run: **13/13 steps PASS**, receipt
`output/release-review-checks/run-WyRnWX/summary.txt`. This includes the app and
thumbnail Debug build. The final storage refinements were followed by fresh
passing storage/v2.7 checks and app/thumbnail build; see `storage-final.log` and
`app-and-thumbnail-final.log` in that same folder. Finder metadata and arbitrary
string-valued connector metadata also survive the storage regression fixtures.
The project currently builds in Swift **5 language mode**
with a newer toolchain; compiler actor-isolation warnings remain, including the
storage boundary's use of the existing Document Codable conformance outside the
main actor. Strict Swift 6 language-mode conformance is not established by this
build. Review that model isolation debt before claiming strict-concurrency closure.

The checked boxes above record the owner’s November 9 report. Automated results
remain separate. Owner results:

| Case | PASS / FAIL / NOT RUN | Notes / exact repro |
| --- | --- | --- |
| B — existing repairs, combined build | PASS | November 9 combined-checklist sign-off; earlier fixes already accepted |
| C — FEAT-082 tokens and saved-paint follow-ups | PASS | Explicit November 9 token and color/gradient editing sign-off |
| D — import visual/edit/export behavior | PASS | November 9, explicitly includes multiple shadows and gradients |
| E — package save/reopen/Finder/versions | PASS | November 9 overall checklist sign-off; no separate version-recovery receipt supplied |
| F — newer-file copy and accessibility | PASS, retained FKA limitation | November 9 overall sign-off; earlier inability to enable Full Keyboard Access is not silently erased |

Hands-on feature acceptance is closed. Fresh regression, recovery and signed
artifact evidence, publication, and installed-app verification are tracked in
RELEASE-CHECKLIST-v2.8.md.
