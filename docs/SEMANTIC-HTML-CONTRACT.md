# Semantic HTML Export Contract

Status: v2.0 Chunks B0–B4 implemented and verified.
`SemanticHTMLContract.swift` is the executable source of truth; this document
explains the decisions that B1–B4 implement.

## Release Boundary

- **v2.0 exports** semantic HTML/CSS from EXP's structured document model.
- **v2.2 imports** rendered HTML/CSS and Storybook back into EXP. Import reuses
  this mapping in reverse, but additionally needs a browser engine to resolve
  computed styles, layout, fonts, and generated content.
- v2.0 does not claim arbitrary HTML round-tripping. DTCG token import is its
  honest existing “back in” path.

## Non-Negotiable Rules

1. Prefer native HTML when the model can emit it honestly. Do not add a
   redundant `role` when the element already has the correct implicit role.
2. Never invent an accessible name, URL, checked/selected state, range value,
   heading level, relationship, or interaction implementation.
3. Missing facts remain visible as fidelity requirements in the package. A
   plausible-looking lie is worse than an explicit handoff task.
4. Generate no JavaScript. EXP exports the component contract—role, state,
   relationships, tokens, notes—not an implementation that can rot.
5. Every node keeps a stable `data-exp-id`. Names and layer order are not
   identity.
6. Escape all text/attributes and make notes safe for HTML comments. No model
   string is interpreted as markup, CSS, script, or a URL.

These rules follow the current [ARIA in HTML author requirements](https://www.w3.org/TR/html-aria/),
[WAI-ARIA 1.2](https://www.w3.org/TR/wai-aria/), and the
[WAI-ARIA Authoring Practices Guide](https://www.w3.org/WAI/ARIA/apg/). APG is
implementation guidance, not a normative specification; its public interaction
patterns are the downstream implementation reference.

## Identity

- Artboard DOM id: `exp-artboard-<artboard-uuid>`.
- Ordinary node DOM id: `exp-<node-uuid>`.
- Resolved component child DOM id:
  `exp-<instance-uuid>-<source-child-uuid>`.
- `data-exp-id` always contains the underlying EXP UUID. A resolved source child
  additionally carries `data-exp-instance-id`; this preserves source identity
  without creating duplicate DOM ids across repeated instances.
- Relationships inside a component instance resolve their target through the
  same instance-prefixed DOM-id function.
- Artboard filename: `<sanitized-name>--<full-artboard-uuid>.html`. The UUID
  prevents collisions; changing a human name is allowed to change the filename,
  while in-document identity remains stable.

## Artboards, Ownership, and Order

- One standalone HTML document is emitted per artboard, plus shared
  `styles.css`.
- A top-level node belongs to the artboard returned by EXP's existing
  `Document.owningArtboard` rule. Wall-only nodes are not silently assigned to a
  page; the manifest reports them as omitted from HTML.
- The artboard is the positioned root and owns its background paint.
- Plain groups use Layers-panel order (frontmost first) for DOM reading order.
  Explicit CSS `z-index` preserves the independent back-to-front paint order.
  Because EXP has no separate accessibility reading-order model yet, the
  manifest labels this order as inferred.
- Auto-layout groups use their visual primary-axis order—the same ordering the
  reflow engine uses—and emit flex containers with matching direction, packed
  gap/primary alignment or space-between distribution, and cross-axis alignment.
- Base-invisible nodes remain addressable but receive the native `hidden`
  attribute, keeping them out of the accessibility tree. State-only visibility
  is represented in the state's CSS selector.

## Accessible Names and Relationships

- A component source's `accessibleNameLayerID` resolves to the corresponding
  instance-prefixed child DOM id and emits `aria-labelledby` on the component
  root.
- EXP never copies a layer's current text into an invented `aria-label`; keeping
  the id relationship preserves live text overrides and translation.
- Node relationships map exactly:
  - `controls` → `aria-controls`
  - `labelledby` → `aria-labelledby`
  - `describedby` → `aria-describedby`
- A missing/deleted/out-of-scope target emits no broken ARIA attribute and adds
  an `unresolvedRelationship` fidelity item.
- Roles that require naming remain emitted, but receive a visible
  `accessibleName` requirement when no valid name source exists.

## Native/ARIA Role Mapping

“Requirement” means information a developer/agent still needs; EXP does not
fabricate it. Explicit roles are emitted only where native HTML cannot safely
contain arbitrary component artwork or lacks required model data.

| EXP role | Host | Explicit role | Requirement(s) |
|---|---|---|---|
| banner | `header` | — | — |
| navigation | `nav` | — | — |
| main | `main` | — | — |
| complementary | `aside` | — | — |
| contentinfo | `footer` | — | — |
| search | `search` | — | — |
| form | `form` | — | accessible name |
| region | `section` | — | accessible name |
| button | `button type="button"` | — | downstream action |
| link | `a` | `link` | destination (`href`) |
| checkbox | `button type="button"` | `checkbox` | checked state |
| radio | `button type="button"` | `radio` | checked state |
| switch | `button type="button"` | `switch` | checked state |
| textbox | `div` | `textbox` | name + text-input implementation |
| searchbox | `div` | `searchbox` | name + text-input implementation |
| slider | `div` | `slider` | name + min/max/current values |
| spinbutton | `div` | `spinbutton` | name + min/max/current values |
| progressbar | `div` | `progressbar` | name + min/max/current values |
| tooltip | `div` | `tooltip` | `aria-describedby` relationship |
| tablist | `div` | `tablist` | accessible name |
| tab | `button type="button"` | `tab` | selected state + controlled panel |
| tabpanel | `section` | `tabpanel` | labelled-by relationship |
| menu | `div` | `menu` | downstream APG behavior |
| menubar | `div` | `menubar` | downstream APG behavior |
| menuitem | `button type="button"` | `menuitem` | downstream action/APG behavior |
| listbox | `div` | `listbox` | accessible name + APG behavior |
| option | `div` | `option` | selected state |
| radiogroup | `div` | `radiogroup` | accessible name |
| toolbar | `div` | `toolbar` | accessible name |
| dialog | `div` | `dialog` | accessible name + focus implementation |
| alertdialog | `div` | `alertdialog` | accessible name + focus implementation |
| alert | `div` | `alert` | — |
| heading | `div` | `heading` | heading level |
| list | `div` | `list` | authored list-item structure |
| listitem | `div` | `listitem` | owning list |
| img | `div` | `img` | accessible name/alternative text |
| figure | `figure` | — | — |
| table | `div` | `table` | name + row/cell structure |
| separator | `div` | `separator` | — |
| group | `div` | `group` | — |

Context can change native landmark semantics—for example, a nested `header` is
not always a banner. B2 performs the ancestry check and emits an explicit role
only when necessary to preserve the assigned EXP contract.

## Component States

- `hover` → `:hover`
- `pressed` → `:active`
- `focus` → `:focus-visible`
- `disabled` → `:disabled` on native controls and
  `[aria-disabled="true"]` otherwise
- custom state → `[data-state="<escaped original name>"]`

An instance with an active custom state carries `data-state`. A disabled native
control receives the native `disabled` attribute; ARIA fallback controls receive
`aria-disabled="true"`. Checked/selected state is not inferred from visual state
names because EXP does not yet model those values.

## Notes and Safety

- Artboard notes appear in a sanitized adjacent HTML comment and, in preview
  mode, an escaped notes sidebar.
- `--` inside a note becomes an em dash so it cannot terminate a comment; a
  trailing hyphen receives a safe trailing space.
- `<`, `>`, `&`, quotes, and apostrophes are escaped in their appropriate text
  or attribute context.
- There are no script tags, inline event attributes, generated `javascript:`
  URLs, or remote dependencies.

## B0 Golden Fixture

`scripts/verify_semantic_html_contract.sh` compiles the model and executable
contract headlessly. Its fixed-id fixture covers:

- artboard notes containing HTML/comment-hostile text;
- a reusable Design Language color and type style;
- a free-positioned layer and an auto-layout group;
- a categorized Button component with accessible-name source;
- conventional and custom component states;
- a placed instance with an active state;
- a typed ARIA relationship;
- repeated-instance DOM-id uniqueness;
- complete role-mapping coverage, deterministic filenames, escaping, and
  document encode/decode.

B1 replaces contract-only assertions with golden HTML/CSS/package output while
retaining this fixture as the shared input.

## B1 Implemented Baseline

`SemanticHTMLExporter.swift` now adds `html/styles.css` plus one standalone HTML
document per artboard to every Handoff Package. The B1 output includes stable
identity, artboard ownership, absolute geometry, basic shape/text/image styling,
resolved component visuals, safe notes, base visibility, and deterministic DOM
order. Hidden component layers remain addressable with `hidden`; wall-only nodes
remain in `design.json` and are counted as HTML omissions in the manifest.

Vector paths remain real geometry: each EXP path emits an inline, decorative SVG
with its cubic Bézier/multi-contour data, fill, stroke, alpha, and local gradient
definition. It is never approximated as a filled rectangular CSS box. CSS linear
gradients convert EXP's y-down angle convention to CSS's angle convention
(`css = exp + 90°`, normalized to one turn).

`scripts/verify_semantic_html_package.sh` verifies the real package writer,
entry byte counts and SHA-256 hashes, duplicate-safe resolved instance ids,
plain/auto-layout reading order, hostile HTML/CSS strings, and omission reporting.
It also verifies flex declarations, flex-item geometry, exact paint-token
fallbacks, and reusable type-style classes.

## B2 Implemented Semantics

Categorized component instances now use the executable native/ARIA mapping.
Configured accessible-name layers emit instance-qualified `aria-labelledby`;
typed node relationships emit `aria-controls`, `aria-labelledby`, or
`aria-describedby` only when the target exists in the same artboard page.
Missing targets and role-required facts are listed in both
`manifest.json.fidelity.semanticHTMLRequirements` and `README.llm.md`.

Component state visuals emit per-instance CSS selectors: `:hover`, `:active`,
`:focus-visible`, native/ARIA disabled selectors, and custom `data-state`.
Active custom/disabled states receive the matching HTML attribute. State text
overrides are reported as downstream requirements because CSS cannot change DOM
text content. No script or inline event code is generated.

The first real-document feedback pass also fixed a missing closing parenthesis
in generated `rgb()` values and expanded the README from note-presence markers
to the complete blockquoted artboard-note text.

## B3 Implemented Layout and Token Fidelity

Managed auto-layout groups now emit CSS flexbox. Horizontal/vertical direction,
packed gap and primary alignment, space-between distribution, cross-axis
alignment, and managed padding map directly from EXP's layout model. Their
children become fixed-size flex items; free-positioned groups and layers retain
the explicit absolute geometry baseline.

The handoff stylesheet reuses the Design Language's existing deterministic CSS
identity. Every saved paint is declared as a custom property. A fill, stroke,
text color, artboard background, or auto-padding surface that exactly equals a
saved paint emits `var(--token-name, literal-fallback)`. When duplicate names
exist, the same stable suffixing is used for declaration and lookup. Exact
whole-text matches emit the saved `.type-<name>` class; mixed rich text stays
explicit rather than receiving a misleading paragraph-level style link.

Standalone SVG export uses the identical color-token lookup for fills and
strokes, embeds the matching custom properties, and retains a literal fallback
on every use. `scripts/verify_svg_token_bridge.sh` covers a semi-transparent
token and proves alpha is applied exactly once. The Design Language CSS copier
and semantic exporter now also share the renderer-correct EXP-to-CSS gradient
angle conversion.

## B4a Text Content Semantics

Type Styles describe reusable presentation and their categories remain visual
organization. They do not determine document hierarchy. Text layers store an
independent `contentRole`: Plain text, Paragraph, or Heading 1–6. Plain text
emits `<span>`, paragraphs emit `<p>`, and headings emit native `<h1>`…`<h6>`.
Export never infers a heading level from font size, weight, layer/style name, or
category. Missing and unknown future values decode as Plain text.

This closes `headingLevel` only with authored information. A component
categorized Heading resolves `aria-level` when its explicitly headed descendants
agree on one level; its descendant renders as a plain span inside that semantic
host to avoid a duplicate nested heading. Missing or ambiguous levels continue
reporting the requirement—EXP does not fabricate one.

## B4b Verification and Fidelity Reporting

`scripts/verify_semantic_html_package.sh` now performs both a byte-for-byte
repeat export and reviewed SHA-256 golden comparisons for the fixture HTML, CSS,
manifest, and README. A separate generated document sends all 40 curated ARIA
roles through the real exporter, rather than only checking the mapping table.
The fixture additionally covers an out-of-artboard relationship target and
enabled unsupported effects on both a top-level node and repeated component
children.

Every fidelity issue carries a category (`semanticRequirement` or
`visualFallback`), artboard/node/source identity, and instance identity when the
affected layer came from a component. Enabled effects are reported once per
exported occurrence. Other known non-exact paths—mask silhouettes, unsupported
polygon strokes, non-horizontal line approximation, non-native stroke alignment,
managed margins, and unknown embedded-image formats—are also structured issues.
They remain preserved losslessly in `design.json`.

Native Button hosts render their visual descendants with phrasing elements, so
their component artwork does not create an invalid HTML content model. List and
List Item use explicit ARIA on flow-safe `div` hosts until nested semantic
components can provide real list ownership in v2.1; the missing structure is
reported rather than inventing `<li>` elements from visual layers. Pages declare
`lang="und"`, because EXP does not yet model document language.

The 2026-07-22 browser pass loaded the fixed fixture in both Firefox and WebKit.
The accessibility tree read Heading 2 → Button → Button → Paragraph → Heading 3;
full-keyboard navigation followed the same frontmost-first Button order with a
visible focus outline. DOM checks found no duplicate ids, unresolved emitted
ARIA references, block/interactive Button descendants, scripts, inline event
handlers, console errors, or horizontal overflow. Computed geometry and paints
matched the fixture in light and dark schemes; `prefers-contrast: more` activated
the stronger artboard/focus treatment. The official W3C Nu validator returned no
errors (only the expected informational note that this isolated fixture begins
at Heading 2). The browser screenshot was visually reviewed for shape, gradient,
path, type, and component placement; its deliberately omitted shadow/blur are
present in the manifest as visual fallbacks.
Lists, labels, block quotes, and code remain later discovery so the first model
addition stays small and testable.
