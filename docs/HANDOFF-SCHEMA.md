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
- `design.json.schemaVersion`: the public document schema version. v1.5 writes
  the current `Document.schemaVersion` (`1`).
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

## Fidelity Contract

The v1.5 package preserves native EXP document data and design tokens. It does
not yet emit semantic HTML/CSS, so consuming tools should not pretend the
package is production markup. Later interop chunks add derived HTML/CSS and
import reports without changing the role of `design.json` as the neutral spine.
