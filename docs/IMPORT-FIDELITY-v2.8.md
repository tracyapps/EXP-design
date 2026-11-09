# v2.8 — import fidelity and document stability

Owner direction, November 4, 2026: the earlier crash/paint-editor/eyedropper fixes
are verified. Include the identified import-fidelity improvements in this release;
address necessary file-format upgrades early with compatibility and regression
coverage. Prepare EXP for sharing at design meetups and networking events over
the next one to three releases. Public v2.7 artifacts stay immutable.

**November 9 acceptance:** the owner reports all of TESTING-v2.8-RELEASE.md
passes, explicitly including package/token fidelity, shadows, gradients and the
latest saved-paint editor. This closes hands-on feature acceptance. The owner
requests releasing this tested slice with the crash fixes. Component-contract/
changeset/full-refresh work stays queued after this release. Fresh regression,
recovery and distribution evidence is tracked in RELEASE-CHECKLIST-v2.8.md.
Physical write reduction, sudden power loss and cloud-sync durability are not
established by that sign-off or the codec tests.

## Release work, in order

| Slice | Observable result | Current evidence / remaining work |
| --- | --- | --- |
| Existing crash repairs | Paint/font popovers, empty paths, editor dismissal and eyedropper folders work reliably | Owner-verified November 4; preserve these working-tree changes |
| FEAT-082 acceptance | Real source token names, aliases/dark values, designer edits and save/reopen remain intact | Automated 18-check suite retained; owner-accepted November 9 |
| BUG-083: CSS shadow stacks | Every supported shadow becomes editable, in the correct paint order | Implemented; all 10 mapper checks pass; visual/export owner-accepted November 9 |
| Component capture | Open shadow roots and slotted content retain visible appearance without omissions or duplicate content | Implemented; production WebKit fixture covers assigned/fallback text, nested roots, scoped repeated IDs and native button semantics |
| Asset storage | Repeated small edits avoid serializing/writing unchanged image payloads | Opt-in .designpkg implemented; wrapper reuse, disk round trip, corruption rejection and actual v2.7 JSON consumer pass; native package checklist owner-accepted November 9; physical-write measurement remains unclaimed |
| Pattern cache | Cache admission/misses do not add unnecessary navigation work | Profile real UI and representative densities before changing thresholds |
| Existing component-sync slices | Contracts, variants, reviewable changesets and refresh retain identity | Continue FEAT-083→085 sequentially under COMPONENT-SYNC-v2.8.md |

### Shadow-stack contract

Source: [CSS Backgrounds §6.1](https://www.w3.org/TR/css-backgrounds-3/#shadow-layers).
CSS lists shadows front-to-back. EXP's canvas/raster renderer and SVG merge paint
in array order within each shadow kind. Import must reverse CSS order within
each kind, keep outer shadows below the box and inset shadows above its background,
and preserve offsets, blur, positive/negative spread, color and alpha. No schema
change is needed: a node already has an effects array.

`bash scripts/verify_rendered_html_shadows.sh` now passes all 10 checks.
It checks single/minimal shadows, multiple rgba colors,
paint-order representation, mixed outer/inset shadows, transparent effects,
report counts and document save/reopen. November 4 baseline: three checks pass,
seven failed because the importer kept only the first shadow. The original
`verify_rendered_html_importer.sh` remains a separate baseline check.

After the mapper passes, add browser/native visual comparisons for overlapping
colored outer and inset shadows, including nonzero inset spread (BUG-055 is an
existing export limitation). Verify PNG/SVG/semantic Handoff behavior and report
remaining approximations accurately. Parser tests alone do not prove rendering.

### Component-capture contract

Source: [DOM shadow trees and slots](https://dom.spec.whatwg.org/#shadow-trees).
Test the rendered composed tree, including default/named slots, fallback content,
text-only assignments, nested hosts, hidden content and generated pseudo-elements.
Assigned content must appear once, at its rendered location, with stable scoped
identity. Retain existing node/resource limits and network/trust rules. Do not
execute repository builds or bypass closed roots. Closed roots require an honest
unsupported report or explicitly labeled bounded fallback, not invented layers.

Before any semantics changes, recheck WAI-ARIA/ARIA in HTML/APG as required by
WORKING-AGREEMENT.md; IDs inside shadow scopes cannot be treated as global DOM IDs.
Exercise the existing Web Components and Lit fixtures plus an independently
authored fixture through production WebKit capture and native mapping. The
seven-format comparison page's equal working/control files are not round-trip
proof. React/Vue/Svelte/Angular prop inference remains FEAT-087's separate adapter.

## Asset-storage migration — early release work

### Confirmed current boundary

- `ExpDocument.fileWrapper` pretty-prints and encodes the entire Document as one
  regular JSON file on each save. `ImageContent.data` and bridge `preservedData`
  are embedded base64. The model is schema 6; bridge schema 1 is independent.
- `ExpDocument` expects regular-file contents; the exported document UTI conforms
  to JSON. `EXPThumbnail/ThumbnailProvider.swift` reads the URL as JSON directly.
- Handoff `design.json`, clipboard/agent fragments and tests use Document Codable.
  Preserve that self-contained interchange contract even if native storage changes.
- Newer-version warning retains original **Data**, not a directory tree. A package
  needs equivalent exact-copy protection. Older public versions cannot warn about
  a future package because they cannot open it; do not claim downgrade support.

### Implemented opt-in storage, November 4

New UTI `tapps.exp-design.package`, extension `.designpkg`, conforms to
`com.apple.package`. It is registered in the app and Quick Look extension.
File → Save a Package Copy… writes a separate package off the main actor and
reveals it in Finder. Open that copy to continue editing in the new format.
File → Save a Legacy JSON Copy… exports a standalone `.design` for older EXP.
Copy actions refuse the currently represented source destination. Normal saves
retain the selected content type; existing `.design` files remain JSON.

`NativeDocumentStorage.swift` is shared with EXPThumbnail. A version-1
`package.json` checksums `document.json`, whose Codable Data values use explicit
`$expAsset`/byteCount references. An `assets/` directory stores raw bytes under
SHA-256 names, deduplicated across all Codable data fields (including component,
pattern and connector data). The in-memory model and standalone JSON stay schema 6.
Custom data encoding avoids constructing base64 for package saves; hashing still
reads the assets. Existing unchanged asset FileWrappers are reused. This is not
yet measured physical-disk or full-app autosave performance evidence.

The reader validates model/asset hashes, filenames, reference lengths, required
features and bounded sizes before returning an editable Document. It preflights
references even in legacy optional fields that otherwise swallow decode errors,
so a missing connector asset cannot silently discard the bridge. It rejects
asset symlinks, missing assets and unknown storage versions/features. Newer-model
warning copies preserve the original FileWrapper tree rather than re-encoding it.

Fresh checks include on-disk write/reopen/move, byte-identical legacy model
round-trip, unchanged-wrapper reuse, preserved original JSON after separate-copy
write/failure, corrupt/unsafe references and decoding/re-encoding the exported
JSON with the immutable **v2.7** sources. The owner accepts the native package checklist November 9. A separate fresh
AppKit/codec fault probe passes disposable process interruption, actual full
volume Save/Autosave, retry and denied-write retention. This does not simulate
hardware power failure/cloud sync or claim measured physical write reduction;
RELEASE-CHECKLIST-v2.8.md records the exact evidence boundary.

### Architecture and remaining integration gates

Use a self-contained macOS document package with readable model JSON and an assets
directory. Store identical binary payloads once under content hashes. Reuse unchanged
asset FileWrappers during saves; keep all assets within the package so moving or
sharing a document cannot detach its images. Avoid adjacent sidecar folders and
zipped containers that still rewrite every payload. Apple documents package saves
and reuse of existing wrappers in [FileDocument](https://developer.apple.com/documentation/swiftui/filedocument)
and [fileWrapper(configuration:)](https://developer.apple.com/documentation/swiftui/filedocument/filewrapper(configuration:)).
The opt-in architecture is implemented; actual bytes written remain unmeasured,
and the safe-writer tests below establish only their bounded failure scenarios.

Keep the in-memory Document API and standalone JSON encoding compatible. Prefer
a dedicated storage codec for references/assets rather than changing ImageContent
decoding everywhere. Version the storage envelope separately; do not assume a model
schema bump alone makes asset references safe. Share the codec with thumbnails.
Inventory nested pages, source components, pattern artwork and preserved bridge
resources so externalization neither loses nor silently duplicates payloads.

Validate the new package UTI/extension separately from the existing JSON type;
validate Finder/Open/Save/drag/Quick Look registration before selecting the final
extension. A folder with a .design suffix is not sufficient registration evidence.
Retain reading and writing legacy .design/.exp JSON. Existing files must not convert
silently on autosave; provide explicit Save As/upgrade to a separate destination,
preserve the original, and offer self-contained legacy JSON export for older EXP.
On new-format open, reject missing, malformed, hash-mismatched or unsafe references
with a clear error before enabling edits. Never replace an unreadable asset with
empty bytes and then overwrite the original.

### Required compatibility and regression matrix

| Boundary | Required evidence |
| --- | --- |
| Legacy open/save | Representative shipped-version JSON files, including .exp, open unchanged; editing/undo/save/reopen preserves IDs, images, sources, patterns, tokens and bridges |
| Upgrade / rollback | Upgrade writes a separate package; original byte hash unchanged; legacy export opens in v2.7 with its supported features and all image bytes |
| Save / autosave | Cold save, repeated metadata edits, image replacement/deletion, Save As, rename/move, duplicate document and two windows |
| Asset reuse | Byte hashes before/after; unchanged asset wrappers reused; measured write volume and encoding time materially reduced on an image-heavy real file |
| Undo / versions | Image delete→save→undo→save, Revert and restored document versions recover assets; do not prune payloads needed by the snapshot being written |
| Interrupted writes | Failure at model/asset write and commit leaves an old or new complete readable document; original never partially upgraded; low-disk and denied-write errors retain recoverable work |
| Corruption / boundaries | Missing asset, invalid hash/path, absolute/traversal path, symlink, oversized metadata/assets, unknown envelope version and unrecognized required fields fail safely |
| OS integration | Finder association, Open/Recent/Save/Save As, Quick Look and thumbnails for both formats in a built app |
| Interchange | Handoff design.json, existing JSON consumers, clipboard and agent payloads still carry self-contained data; no filesystem-only reference leaks |
| Copy / sharing | Exact original package copy for newer-version protection, Finder copy/archive/reopen, moved package and backups work without its original path |

The codec can be characterized before integration; a shipping format requires
the real SwiftUI document save/recovery paths too. Source-only tests or smaller
output bytes are not durability proof. Measure CPU/memory and filesystem write
volume separately, using document copies and no sync-service manipulation.

## Owner acceptance recorded November 9

Follow COMPONENT-SYNC-v2.8.md → “Owner verification (FEAT-082)”: import the Start
theme, inspect names/dark values/read-only rows, export CSS, change a color and
re-import to ensure the local edit survives, undo, save/close/reopen, then check
VoiceOver and the exact-original-copy newer-version warning. Owner reports the full checklist passes, including the November 6 paint-editor
follow-ups. This acceptance is distinct from automated and signed-release proof.
