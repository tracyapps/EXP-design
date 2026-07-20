# EXP Handoff Package and `design.json` Schema

Status: v1.5 first public spine. The package is intentionally readable: a
folder with the `.exph` extension, not a proprietary blob.

## Package Layout

```
Example.exph/
|-- manifest.json
|-- design.json
|-- tokens.json
`-- README.llm.md
```

- `manifest.json`: package version, generator info, entry list, byte counts,
  SHA-256 checksums, summary counts, and fidelity notes.
- `design.json`: the EXP document payload encoded from `Document`.
- `tokens.json`: the document Design Language as W3C Design Tokens JSON.
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
  `1`.
- `design.json.schemaVersion`: the public document schema version. v1.5 wrote
  `1`; v1.6 writes `2`. Version history:
  - `1` — v1.4 baseline shape.
  - `2` — v1.6 adds the component contract spine: `sources[].states`
    (named component states as override-diffs; see Component States below),
    `nodes[].relationships`, and `nodes[].publicProps`. A v2 reader can read
    a v1 file by treating `states`, `relationships`, and `publicProps` as
    empty/default. Saving in v1.6+ migrates a file's declared version to `2`.
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

## `design.json` Top Level

`design.json` is a JSON object with these stable top-level keys:

- `schemaVersion`: integer public schema marker.
- `formatVersion`: integer internal model marker.
- `artboards`: array of artboard objects.
- `nodes`: array of top-level document nodes in z-order, back to front.
- `sources`: array of component source definitions.
- `guides`: array of document guide objects.
- `designLanguage`: native EXP design-language data. `tokens.json` is the
  standards-shaped companion for downstream token pipelines.

## Identity Rules

Every artboard, node, component source, design-language asset, category, and
type style has a UUID `id`. Use ids as the only reference currency. Names are
for humans and may change; z-order is meaningful for drawing, not identity.

Component instances reference `sources[].id` through their `sourceID`. Artboard
notes live on the owning artboard. Component ARIA categories live on
`sources[].a11y.role`.

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
