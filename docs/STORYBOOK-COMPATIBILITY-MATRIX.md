# Storybook static-build compatibility matrix

Measured evidence for E2c. A row means EXP imported the named **published static
artifact** through `index.json` + `iframe.html`; it does not claim compatibility
with every release in the same major version or with repository source/build
execution.

Last measured: 2026-08-05.

## Measured builds

| Published build | Framework / renderer | Builder | Storybook | Index | Runtime success phase | Representative result | Status |
|---|---|---|---|---|---|---|---|
| GitLab UI owner-supplied published build | `@storybook/vue-webpack5` / Vue 3 | `@storybook/builder-webpack5` | 7.6.24 | v4; 530 stories + 119 docs | `completed` | 8/8 non-empty artboards; 52 text layers; 6 editable SVGs; portal modal, play function, screen-reader-only text, and external SVG sprite covered | Pass |
| [CZI Science Design System](https://chanzuckerberg.github.io/sci-components/) deployment branch [`af4f1a7`](https://github.com/chanzuckerberg/sci-components/commit/af4f1a7bf3adf2ffa0dcc250ee9a9cd6f22a458a) | `@storybook/react-vite` / React | `@storybook/builder-vite` | 10.5.2 | v5; 202 stories, no docs entries | `finished` | 16/16 Phone + Web 1280 artboards; 130 painted text layers; 4 editable SVGs; 180 semantic roles; 82 retained ARIA attributes | Automated corpus pass; owner visual acceptance complete before the generic clipping correction |
| [Dell Design System Angular v3.0.1](https://angular.delldesignsystem.com/3.0.1/) | `@storybook/angular` / Angular 17 (compatible with Angular 17–20) | `@storybook/builder-webpack5` | 8.6.18 | v5; 46 stories + 113 docs | `completed` | 12/12 Phone + Web 1280 artboards; 52 painted text layers; 6 editable SVG masks; 32 semantic roles; 32 retained ARIA attributes; 2 hidden accessibility-text layers | Automated corpus pass; owner visual acceptance complete |
| [Brave Leo (Nala)](https://nala.s.brave.dev/) main deployment at [`b949916`](https://github.com/brave/leo/commit/b9499167c436347f844097520282c590be1f449f) | `@storybook/svelte-vite` / Svelte 5.55.7 | `@storybook/builder-vite` / Vite 6.4.3 | 8.6.18 | v5; 104 stories + 31 docs | `finished` | 16/16 Phone + Web 1280 artboards; 32 painted text layers; 18 editable SVG masks; 28 semantic roles; 14 retained ARIA attributes; 2 editable shadows | Automated corpus pass; owner visual acceptance complete |
| [Kintone UI Component](https://kintone-labs.github.io/kintone-ui-component/) published branch [`77c9855`](https://github.com/kintone-labs/kintone-ui-component/commit/77c9855ac944b44ea539ea5190585c4bae18c26f) | `@storybook/web-components-vite` / light-DOM custom elements | `@storybook/builder-vite` | 10.3.5 | v5; 106 stories, no docs entries | `finished` | 16/16 Phone + Web 1280 artboards; 113 painted text layers; 18 editable SVGs; 134 semantic roles; 78 retained ARIA attributes; 6 editable shadows | Automated corpus pass; owner visual acceptance complete |

The CZI artifact is a particularly useful contrast because it is a real
React/TypeScript + Vite deployment, published from its `gh-pages` branch. EXP
clones or receives that already-built branch for testing; it does not install
dependencies or execute the repository build.

The Dell row is the first Angular evidence and the first Storybook 8 artifact.
The versioned deployment reports Storybook 8.6.18, Angular renderer, webpack 5,
TypeScript, and npm directly in `project.json`; Dell's public Angular guidance
states that the components are built with Angular 17 and compatible with Angular
17–20. Its static source repository is not public, so the immutable test identity
is the versioned v3.0.1 URL plus the pinned SHA-256 receipts for `index.json`
(`9dd74882…d0a00b`) and `project.json` (`eebc54b6…d2fd1`), generated
2026-07-14T20:39:03Z. EXP downloads only the already-built public artifact.

The Brave Leo row adds Svelte 5 and Svelte CSF v4 on Vite 6. The public root is
deployed from the successful non-PR `main` workflow at commit `b949916`; the
bounded fetcher mirrors only same-origin published static resources and pins the
catalog (`c4d1029e…d691ae5`) and project (`c4f2dc4f…54e28`) receipts. It does
not clone or build Leo.

The Kintone row adds Storybook's Web Components renderer and Vite framework at
10.3.5. Its public `gh-pages` branch is a generated static artifact pinned to
commit `77c9855`; EXP clones only that already-built branch, checks the catalog
(`6bf58b10…5b0788`) and project (`1f480f3f…0c6c9d`) receipts, and executes no
package or build command. Kintone's Lit base class deliberately renders into the
custom-element host instead of attaching a shadow root, so this row measures
standards-based custom elements with light-DOM internals. It does **not** claim
open- or closed-shadow-root traversal.

## Differences converted into compatibility rules

1. **Successful runtime phases are generation-dependent.** Storybook 7.6.24
   settles at `completed`; Storybook 10.5.2 settles at `finished`. EXP accepts
   both terminal phases and continues to reject `aborted`, `errored`, and
   `error`.
2. **`#storybook-root` is not guaranteed to generate a box.** The Storybook 10
   React build can leave the root at 1408 × 0 while visible descendants have
   real geometry. Readiness now uses a bounded (5,000-element) visible-descendant
   union only when the populated root itself has zero width or height. Empty and
   hidden roots still fail rather than becoming one-pixel artboards.
3. **Builder package versions are optional in `project.json`.** The Storybook 10
   build names `@storybook/builder-vite` but omits a separate builder entry from
   `storybookPackages`. When that happens, EXP records the published top-level
   `storybookVersion` (10.5.2), not the unrelated index schema version (5).
4. **The catalog may contain no `docs` entries.** The CZI v5 index contains 202
   story entries and no docs entries. Discovery and selection remain based on
   entry `type`, not an assumed story/docs ratio.
5. **A Storybook viewport is a minimum canvas, not merely a body measurement.**
   Preview bodies commonly shrink-wrap a 32px button or 72px accordion. EXP now
   keeps the selected Storybook render height as the artboard minimum while still
   expanding for genuinely taller content. This rule is Storybook-specific;
   ordinary local HTML retains its measured-content-height contract.
6. **A transparent preview body does not mean a transparent browser canvas.**
   Storybook's default canvas is visibly white even when `html`/`body` have no
   authored fill. EXP now retains that opaque white backdrop instead of exposing
   its dark workspace through the unused viewport.
7. **Generated text and fallback-font metrics are visible fidelity.** CSS
   `::before`/`::after` content is captured when it paints text, background,
   border, outline, or shadow. Static generated content inside flex containers is
   positioned from its laid-out siblings and resolved margins; this keeps the
   toggle's `Off` label beside its thumb instead of underneath it. CSS `outline`
   becomes an editable outside stroke (a separate nonzero `outline-offset` is
   reported as an approximation). Native text boxes are checked using the same
   fallback font and finite TextKit layout EXP draws: single lines widen to their
   native metrics, while multiline boxes make a small bounded width correction
   when that preserves the browser line count and otherwise grow in height. CSS
   line-height itself remains unchanged. Fixed px/em line boxes now center their
   extra leading around the native font box when painted, matching CSS baseline
   placement without rewriting (for example) an authored `26px` value as a guessed
   multiplier. CSS `normal` remains EXP Auto and uses the installed font's native
   metrics; Auto is not an alias for the hidden `1.3×` editing seed.
8. **Percentage radii are geometry, not unsupported decoration.** Per-corner
   percentage radii now resolve against the box's smaller dimension. The CZI
   toggle's 16 × 16 thumb therefore retains its authored 50% radius as an editable
   8px circle instead of becoming a square. Oversized numeric radii use the same
   CSS overlap normalization in live canvas, shadow/mask, raster/PDF, SVG, and
   Convert to Path geometry: the toggle's authored 20px radius on a 62 × 24 box
   paints as the legal 12px capsule without rewriting the editable source value.
9. **Authored viewport overflow is retained, not “repaired” into a new design.**
   The published StackedBarChart default story fixes its `width` arg at `360px`.
   At Phone, Storybook centers a 61px intrinsic wrapper while its 360px child
   overflows that wrapper, placing rendered content 133px beyond the right edge.
   EXP now reports the measured overflow with exact fidelity and retains the
   source geometry. A responsive rewrite requires a responsive source story or an
   explicit later editing action; import does not invent one.
10. **Browser clipping determines whether descendants are painted.** A descendant
    can expose a client rectangle while a zero-height or scroll-port ancestor clips
    it completely. EXP now intersects descendants with `hidden`, `clip`, `scroll`,
    and `auto` overflow ancestors before mapping them. This removes Dell's collapsed
    accordion bodies and unpainted CZI scroll/sprite content without discarding 1×1
    accessibility-only text, which retains its existing hidden-layer treatment.
11. **Published builds can retain deploy-root assets.** Dell requests
    `/dds-icons.svg` from inside its versioned Storybook folder. The ephemeral
    loopback server now admits only an existing root-level file from the selected
    catalog through that absolute-root form; nested paths still require the random
    import route, traversal remains rejected, and remote resources remain blocked.
    The pinned fetcher includes the sprite, so its HTTP error body cannot become
    editable canvas text.
12. **Pseudo-element transforms affect their reconstructed paint bounds.** Since
    pseudo-elements expose no DOM box API, EXP applies their computed transform
    matrix around the resolved transform origin to the reconstructed rectangle.
    This keeps Dell's translated 20×20 switch thumb centered inside its 40×24
    control. The transform is still reported because EXP does not claim it as an
    editable transform property.
13. **A CSS mask is visible geometry, not its underlying fill box.** For a bounded
    `data:image/svg+xml` mask, EXP decodes and sanitizes the SVG, applies the
    resolved background color, and imports the result as editable vector geometry.
    Dell's six Phone/Web accordion carets therefore remain caret paths instead of
    20×20 dark rectangles. Non-data, multi-layer, oversized, or undecodable masks
    retain the box fallback and now produce an explicit fidelity report.
14. **Angular requires no framework-specific mapper.** Dell's Storybook 8.6.18
    artifact passed discovery, runtime readiness, initial-args capture, editable
    DOM mapping, accessibility preservation, and Phone/Web viewport capture through
    the framework-neutral seam. The owner-discovered fixes above are browser-paint
    rules shared by every framework; no Angular-specific branch was added. This is
    evidence for this published Angular 17 build, not a blanket claim about every
    Angular or Storybook release.
15. **A terminal phase is a runtime contract, not a Storybook-major shortcut.**
    Dell Storybook 8 settles at `completed`, while Leo Storybook 8 settles at
    `finished`. EXP's bounded allow-list is intentionally based on the observed
    terminal phase rather than inferring one phase from a generation number.
16. **Published version fields can legitimately disagree.** Leo's generated
    `project.json` reports top-level `storybookVersion` 8.6.14 while its
    `storybook` and `@storybook/svelte-vite` packages report 8.6.18, and it omits
    a separate builder-package version. EXP retains those published claims:
    framework 8.6.18 and the top-level 8.6.14 builder fallback. It does not
    normalize provenance into a cleaner but invented version.
17. **A local CSS mask URL is editable source, not a solid box.** Leo constructs
    URLs such as `/icons/close.svg` at runtime, then paints the SVG silhouette
    with the element's resolved background color. The isolated server now admits
    an existing nested root-relative file only inside the user-selected package;
    standardized-path prefix checks still reject traversal and outside files.
    The capture sanitizes a bounded local SVG mask, applies the computed paint,
    and passes it through the native SVG importer. Missing, remote, multi-layer,
    or non-SVG masks retain the explicit unsupported fallback.
18. **A Web Components renderer does not imply one encapsulation model.**
    Kintone's published custom elements override Lit's render root to use the
    element itself, so their visible descendants are ordinary light DOM. EXP
    retains the `kuc-*` hosts as editable groups and maps their descendants through
    the same browser-paint seam used for every other framework; it adds no
    Web-Components-specific mapper. This is evidence for light-DOM custom elements,
    not shadow-root support. A separate real fixture is required before EXP claims
    traversal of open roots, slots, or any fallback for opaque closed roots.

## React + Vite representative corpus

The opt-in regression covers accordion, button, dialog, input toggle,
pre-composed table, tabs, heatmap, and stacked bar chart stories at Phone
(393 × 852) and Web 1280 (1280 × 800), matching the owner acceptance import.
All non-table artboards equal those requested viewport sizes. The table expands
to its measured 393 × 1113 and 1280 × 1061 content. The 16-artboard pass retains
130 painted text layers with zero native TextKit overflow, four editable SVGs,
seven editable shadows, two editable CSS outlines, 180 semantic roles, and 82
structured ARIA attributes.
All eight behavior contracts retained bounded `initialArgsJSON`; framework,
renderer, builder, Storybook version, package manager, index entries, and
resource hashes remained receipt-only provenance.

Honest fidelity limits reported by that corpus:

- Inter was not installed, so 130 text layers used the reported system fallback;
  58 weight/style requests used the closest installed face. Correct line-box
  placement cannot make the fallback glyph shapes identical to the source webfont;
  installing the same licensed font before import remains the exact path.
- 14 CSS transforms retained their browser-measured bounds without reconstructing
  editable transforms.
- Four `rowgroup` roles were preserved as unsupported tokens because EXP has no
  native role for them yet; two host-role combinations remained outside the
  importer’s verified ARIA-in-HTML host set.
- Two unequal per-side borders became editable uniform borders, and 12 CSS background
  images retained their resolved background colors but are not yet editable.
- Twelve non-data CSS mask images remain unsupported and are now named explicitly
  rather than silently presenting their underlying box paint as exact.
- Six finite animations were advanced to their final rendered state at each
  viewport in one story.
- The browser rendered at 2× device scale; geometry remains in CSS pixels.

These are mapper/native-model fidelity limits, not React/Vite or Storybook 10
catalog/runtime failures. No SVG was rasterized in this corpus.

## Angular + webpack representative corpus

The opt-in Dell regression covers Accordion, Button, Card/Metrics Card, Modal,
Switch, and the Sign-in pattern at Phone (393 × 852) and Web 1280 (1280 × 800).
All 12 artboards retain the requested viewport dimensions and opaque browser
canvas. The pass maps 52 painted text layers with zero native TextKit overflow,
six editable SVG-mask carets, 32 semantic roles, 32 structured ARIA attributes,
and two clipped accessibility
labels as hidden layers. Every story retains bounded `initialArgsJSON`, while the
framework, renderer, builder, Storybook version, package manager, v5 index entries,
and resource hashes remain receipt-only provenance.

Honest fidelity limits reported by this corpus:

- The published CSS requests remote Roboto resources. Local Storybook import blocks
  remote subresources by design, so 14 text layers use the reported system fallback
  and 19 weight/style requests use the closest installed face.
- Six icon-font surfaces use an unavailable `dds-icons` font and therefore report
  fallback rather than pretending the glyphs are exact.
- Six unequal per-side borders become editable uniform borders, and two CSS
  pseudo-element transforms affect reconstructed paint bounds but are not retained
  as editable transforms.
- Ten explicit role/host combinations remain outside EXP's verified
  ARIA-in-HTML host set. The role tokens are retained, but conformance is not claimed.
- The browser rendered at 2× device scale; geometry remains in CSS pixels.

These are native-model or isolated-local-import fidelity limits, not Angular,
webpack, Storybook 8 catalog, or runtime failures.

An additional owner-evidence regression imports ContentCard, Button, and
InputToggle at EXP's exact Tablet preset (834 × 1194). It asserts the ContentCard
paragraph keeps its authored 24px
line-height with no excluded native characters; Button's 24px inline line box is
vertically centered within its 32px control; and the toggle's `Off` label sits
beside the thumb inside a 62 × 24 control with an editable outside outline. This
subset exists because the original eight-story structural corpus did not contain
the multiline ContentCard/control-line-box failures and its earlier toggle
assertion checked text presence without checking painted position.

## Svelte + Vite representative corpus

The opt-in Brave Leo regression covers Alert, Button, Checkbox, Dialog, Input,
SegmentedControl, Tabs, and Toggle stories at Phone (393 × 852) and Web 1280
(1280 × 800). All 16 artboards retain the requested viewport dimensions and
opaque browser canvas. The corrected pass maps 32 painted text layers with zero
native TextKit overflow, 18 editable SVG masks, 28 semantic roles, 14 structured
ARIA attributes, and two editable shadows. Every story retains bounded
`initialArgsJSON`; Svelte/Vite,
renderer, package-manager, v5 index entries, consumed resource hashes, and the
receipt-only DOM bindings remain structured provenance.

Honest fidelity limits reported by that corpus:

- Each selected story paints 8px beyond both horizontal viewport edges; EXP
  reports and retains that authored geometry rather than inventing a reflow.
- 22 CSS transforms retain their browser-measured bounds without becoming
  editable transforms.
- 20 font weight/style requests use the closest installed face.
- Two multi-shadow surfaces retain the first editable shadow, and two unequal
  per-side borders become editable uniform borders.
- WebKit rendered at 2× device scale; geometry remains in CSS pixels.

These are native-model fidelity limits, not Svelte, Vite, Svelte CSF v4, or
Storybook catalog/runtime failures. No Svelte-specific importer branch was added.

## Web Components + Vite representative corpus

The opt-in Kintone regression covers Button, Checkbox, Dialog, Dropdown,
Readonly Table, Switch, Tabs, and Text stories at Phone (393 × 852) and Web 1280
(1280 × 800). All 16 artboards retain the requested viewport dimensions and
opaque browser canvas. The pass maps 113 painted text layers with zero native
TextKit overflow, 18 editable SVGs, 134 semantic roles, 78 structured ARIA
attributes, and six editable shadows. Every story retains bounded
`initialArgsJSON`; framework, renderer, builder, package-manager, v5 catalog,
consumed resource hashes, and receipt-only DOM bindings remain structured
provenance. The imported hierarchy retains the `kuc-*` custom-element hosts as
editable groups.

Honest fidelity limits reported by that corpus:

- Kintone renders its component internals into light DOM. This corpus does not
  exercise or establish open/closed shadow-root or slot traversal.
- Four `rowgroup` roles remain preserved unsupported tokens because EXP has no
  native role for them, and 11 authored `presentation` roles on `<li>` hosts are
  retained as source data while EXP uses the conforming implicit host role.
- Fourteen unequal per-side borders become editable uniform borders.
- One selected story extends 23px beyond the Phone viewport; EXP reports and
  retains that authored geometry instead of inventing a reflow.
- Two multi-shadow surfaces retain the first editable shadow.
- WebKit rendered at 2× device scale; geometry remains in CSS pixels.

These are native-model or explicitly unmeasured encapsulation limits, not Web
Components, Vite, or Storybook catalog/runtime failures. No Web-Components-
specific importer branch was added.

## Reproduction

Use the published deployment branch only—do not build the repository:

```bash
fixture_dir="$(mktemp -d /tmp/exp-sci-storybook.XXXXXX)"
git clone --depth 1 --single-branch --branch gh-pages \
  https://github.com/chanzuckerberg/sci-components.git "$fixture_dir"
EXP_STORYBOOK_REACT_VITE_FIXTURE="$fixture_dir" \
  scripts/verify_storybook_package_import.sh
```

Set `EXP_STORYBOOK_REACT_VITE_STORY_ID` to one catalog id to diagnose a single
story. The regression intentionally asserts the measured 10.5.2 contract; if
the public deployment advances, inspect and record the new commit and results
before updating the assertion or this matrix.

For the versioned Dell build:

```bash
fixture_dir="$(scripts/fetch_dell_angular_storybook_fixture.sh)"
EXP_STORYBOOK_ANGULAR_WEBPACK_FIXTURE="$fixture_dir" \
  scripts/verify_storybook_package_import.sh
```

Set `EXP_STORYBOOK_ANGULAR_WEBPACK_STORY_ID` to one catalog id to diagnose a
single story. The fetcher pins both catalog and project receipts and stops if the
published v3.0.1 contract changes; it downloads static output only, including the
build's deploy-root `dds-icons.svg` dependency.

For Brave Leo's published Svelte + Vite build:

```bash
fixture_dir="$(scripts/fetch_brave_leo_svelte_storybook_fixture.sh)"
EXP_STORYBOOK_SVELTE_VITE_FIXTURE="$fixture_dir" \
  scripts/verify_storybook_package_import.sh
```

Set `EXP_STORYBOOK_SVELTE_VITE_STORY_ID` to one catalog id to diagnose a
single story. The fetcher pins the catalog/project receipts, allows only bounded
same-origin files from the published static artifact, and stops when the
deployment contract changes.

For Kintone's published Web Components + Vite build:

```bash
fixture_dir="$(scripts/fetch_kintone_web_components_storybook_fixture.sh)"
EXP_STORYBOOK_WEB_COMPONENTS_VITE_FIXTURE="$fixture_dir" \
  scripts/verify_storybook_package_import.sh
```

Set `EXP_STORYBOOK_WEB_COMPONENTS_VITE_STORY_ID` to one catalog id to diagnose a
single story. The fetcher clones only the already-built `gh-pages` branch, pins
its deployment commit plus catalog/project receipts, enforces bounded artifact
size/count, and runs no package installation or build.

## Next rows

The owner visually approved the corrected CZI Phone/Web and focused Tablet
artboards on 2026-08-04 before the later generic overflow-clipping correction.
The owner visually approved the corrected Dell Angular corpus on 2026-08-04.
The owner visually approved the corrected Brave Leo Svelte + Vite corpus on
2026-08-04 after the generic file-backed SVG-mask correction.
The owner visually approved the Kintone Web Components + Vite corpus on
2026-08-05, closing the modern-framework matrix. The expected absence of
reconstructed editable component states is tracked as separate future research,
not an import-fidelity failure in this scope.
Remaining non-gating compatibility work:

1. Representative older Angular and AngularJS artifacts as explicit non-gating
   compatibility work, selected from evidence rather than assumed support.
2. A real published Web Components fixture with open shadow roots and slots,
   before claiming that separate encapsulation contract.

Unrestricted URL import, repository build execution, full argTypes ingestion,
and code write-back remain outside this matrix.
