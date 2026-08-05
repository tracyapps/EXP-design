# EXP Handoff Package and `design.json` Schema

Status: v1.5 first public spine. The package is intentionally readable: a
folder with the `.exph` extension, not a proprietary blob.

## Package Layout

```
Example.exph/
|-- manifest.json
|-- design.json
|-- tokens.json
|-- html/
|   |-- styles.css
|   `-- <artboard-name>--<artboard-uuid>.html
`-- README.llm.md
```

- `manifest.json`: package version, generator info, entry list, byte counts,
  SHA-256 checksums, summary counts, and fidelity notes.
- `design.json`: the EXP document payload encoded from `Document`.
- `tokens.json`: the document Design Language as W3C Design Tokens JSON.
- `html/styles.css`: shared generated CSS for all artboard pages.
- `html/*.html`: one standalone, deterministic entry point per artboard. v2.0
  B1 uses absolute geometry as its honest baseline; each layer carries its EXP
  identity, and repeated component children use instance-qualified DOM ids.
- `README.llm.md`: plain-language orientation for people and local agents.

## `tokens.json`

EXP writes document colors, gradients, and type styles using W3C Design Tokens
Community Group-style `$type` / `$value` objects. The Design Language import
sheet also reads this shape back in from pasted JSON or a `.json` file.

The importer is intentionally tolerant for interop:

- Nested token groups are accepted.
- Group-level `$type` is inherited by child tokens.
- Colors accept strings (`#RRGGBB`, `rgb()`, `hsl()`, `oklch()`) or component
  objects for `srgb`, `hsl`, `oklch`, and `lch`.
- Gradients accept an array of stops or an object containing `stops` /
  `colorStops`.
- Typography accepts common keys such as `fontFamily`, `fontSize`,
  `lineHeight`, `letterSpacing`, `textAlign`, and `textDecoration`.

## Versioning

- `manifest.json.expHandoffPackage`: the package-envelope version. v1.5 writes
  `1`; v2.0 B1 keeps that additive envelope version and adds HTML/CSS entries.
- `design.json.schemaVersion`: the public document schema version. v1.5 wrote
  `1`; v1.6 writes `2`. Version history:
  - `1` — v1.4 baseline shape.
  - `2` — v1.6 adds the component contract spine: `sources[].states`
    (named component states as override-diffs; see Component States below),
    `nodes[].relationships`, and `nodes[].publicProps`. A v2 reader can read
    a v1 file by treating `states`, `relationships`, and `publicProps` as
    empty/default. Saving in v1.6+ migrates a file's declared version to `2`.
  - `3` — v2.1 stores independent canvas `pages[]`, each with its own artboards,
    nodes, guides, and root relationships.
  - `4` — v2.2 adds hidden `codeBridges[]` provenance/receipt data and persistent
    top-level `nodes[].artboardID` membership. Missing `artboardID` is migrated from
    the legacy >50% geometry rule; nested nodes inherit their top-level container.
- `design.json.formatVersion`: the internal EXP model migration version. Treat
  this as implementation detail unless you are opening the file in EXP.

Policy: readers should accept known fields, ignore unknown fields, and treat
unknown enum values as unsupported rather than corrupt. EXP already decodes its
native document model this way where old/new files need tolerance.

## Manifest Entries

Each `manifest.json.entries[]` object describes one package file:

- `path`: relative package path.
- `role`: EXP's purpose label for the file.
- `mediaType`: MIME-style content type.
- `schemaVersion`: integer schema version when the entry has one, otherwise
  omitted.
- `bytes`: byte length of the written file.
- `sha256`: lowercase hexadecimal SHA-256 digest of the written file.

The manifest summary additionally reports `semanticHTMLPages`,
`semanticHTMLNodes`, and `semanticHTMLOmittedWallNodes`. Wall-only nodes remain
in `design.json`; they are not silently assigned to an artboard page.

`fidelity.semanticHTMLRequirements[]` is the structured B2 handoff list for
facts EXP cannot safely infer. Each item identifies its artboard/node/component
source, assigned role, requirement key, and a human-readable detail. Typical
examples are a missing heading level, link destination, checked/selected value,
range values, or unresolved relationship target.

## `design.json` Top Level

`design.json` is a JSON object with these stable top-level keys:

- `schemaVersion`: integer public schema marker.
- `formatVersion`: integer internal model marker.
- `pages`: array of canvas-page objects. Each page contains `artboards`, top-level
  `nodes` in back-to-front z-order, `guides`, and `anchoredRelationships`.
- `sources`: array of component source definitions.
- `codeBridges`: optional v2.2 source receipts/bindings for code imports. It contains
  no credentials; service credentials belong in Keychain.
- `designLanguage`: native EXP design-language data. `tokens.json` is the
  standards-shaped companion for downstream token pipelines.

Schema 1‖2 single-canvas files may instead carry root `artboards`, `nodes`, `guides`,
and `anchoredRelationships`; EXP migrates those into one page on open.

### Code-bridge receipts (schemaVersion 4)

Each `codeBridges[]` entry is hidden provenance, not canvas content or executable
code. `source` records the connector and, where a published artifact supplies it,
framework/build-tool/version/package-manager identity. `resources[]` carries
relative paths, hashes, MIME/role data, and bounded preserved source bytes;
`bindings[]` associates EXP ids with source-owned external ids/DOM paths and starts
with no writable properties. `behaviorContracts[]` stores bounded component/story
contracts. Storybook contracts may include `initialArgsJSON`, a JSON-safe snapshot
of published initial args; functions, DOM objects, cycles, excessive depth/count,
and values over 64 KB are omitted. `project.json` is retained and hashed when the
static build publishes it. None of these fields grants code execution or write-back.

## Identity Rules

Every artboard, node, component source, design-language asset, category, and
type style has a UUID `id`. Use ids as the only reference currency. Names are
for humans and may change; z-order is meaningful for drawing, not identity.

Component instances reference `sources[].id` through their `sourceID`. Artboard
notes live on the owning artboard. Component ARIA categories live on
`sources[].a11y.role`.

Top-level `nodes[].artboardID` is an explicit UUID reference to an artboard on the
same canvas page. `null`/omitted means Wall. EXP uses hysteresis when geometry is
edited: an unattached layer enters above 50% overlap, an attached layer stays while
any positive visible geometry overlaps, and it detaches at zero overlap. Unmanaged
groups resolve membership from current descendants; masks resolve from their crop.

## Node Behavior Contract (schemaVersion 2)

Every node may carry behavior-contract metadata used by semantic export and
future code/Storybook import:

- `relationships`: typed id-to-id links from this node to another node.
  Supported relationship `kind` values are `controls`, `labelledby`, and
  `describedby`; semantic HTML export maps them to `aria-controls`,
  `aria-labelledby`, and `aria-describedby` using the target node ids.
- `publicProps`: flags for overridable fields that should become public
  component props / Storybook args downstream. v1.6 models `text` and `fill`,
  matching the current bounded override vocabulary. Omitted or false fields are
  private/local EXP overrides.

These fields do not store implementation code. Relationships plus
`sources[].a11y.role` identify the public WAI-APG pattern; downstream codegen
regenerates behavior from that contract.

In generated HTML, categorized component instances use their native HTML host
when the mapping is unambiguous (`nav`, `header`, `button`, and so on), or an
explicit ARIA role otherwise. Accessible-name layers and typed relationships
resolve through stable DOM ids. States export as `:hover`, `:active`,
`:focus-visible`, native/ARIA disabled selectors, or custom `data-state` values.
EXP generates no JavaScript.

## Text Content Semantics (schemaVersion 2)

Text node content carries `contentRole` independently from its reusable Type
Style. Supported values are `plain`, `paragraph`, and `heading1` through
`heading6`. Semantic HTML emits plain text as `<span>`, paragraphs as `<p>`, and
headings as the corresponding native `<h1>`…`<h6>` element. Missing or unknown
future values decode as `plain`; exporters never infer hierarchy from visual
font properties or style/category names.

A component source categorized `heading` resolves its host `aria-level` from an
unambiguous authored descendant text role. Missing or conflicting levels remain
visible as a `headingLevel` fidelity requirement.

## Component States (schemaVersion 2)

`sources[].states` is an array of named visual states — the first leg of the
component contract (states / behavior / motion). Each entry:

- `id`: UUID.
- `name`: display/export name. Conventional names (`hover`, `pressed`,
  `focus`, `disabled`) are intended to map to CSS pseudo-classes on semantic
  export; any other name maps to `data-state="name"`.
- `overrides`: the visual diff against the base state — the SAME shape as
  instance `overrides` (text/fill overrides targeting node ids inside the
  source).
- `layerVisibility`: per-state layer visibility diffs, same shape as instance
  `layerVisibility` (e.g. a focus ring visible only in `focus`).
- `enterTransitionToken` (optional): name of the DTCG transition token used to
  enter the state. Reserved; not yet written by any UI.

States never contain implementations (no JS, no event wiring). Behavior is
implied by `a11y.role` plus the public WAI-APG pattern for that role, so
downstream tools regenerate interaction code from the contract instead of
round-tripping it.

## Fidelity Contract

The v1.5 package preserves native EXP document data and design tokens. It does
not yet emit semantic HTML/CSS, so consuming tools should not pretend the
package is production markup. Later interop chunks add derived HTML/CSS and
import reports without changing the role of `design.json` as the neutral spine.
