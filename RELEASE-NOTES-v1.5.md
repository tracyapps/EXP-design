# EXP [design] v1.5

Build 7. This is the first interop and handoff release: a smaller foundation
release that makes EXP documents easier to inspect, share, and prepare for
future semantic HTML/CSS export.

## Highlights

- **Handoff Package export.** File -> Export Handoff Package... writes an
  inspectable `.exph` folder containing `manifest.json`, `design.json`,
  `tokens.json`, and `README.llm.md`.
- **Document schema notes.** The first public handoff schema document explains
  package layout, versioning, identity rules, manifest fields, and fidelity
  expectations.
- **Design Tokens JSON import/export.** The Design Language transfer sheet now
  reads and writes W3C Design Tokens-style JSON for colors, gradients, and type
  styles.
- **Tolerant token import.** Pasted or file-imported token JSON accepts nested
  groups, inherited `$type`, common color string formats, component color
  objects, gradient stops, and typography keys.
- **Component instance navigation.** Components-panel rows can page through
  instances with previous/next controls. Paging selects the active instance and
  only recenters the canvas when the instance is off-screen.
- **Package integrity.** Handoff package manifests include byte counts and
  SHA-256 checksums for each exported payload.

## Fixes

- Enlarged the component instance pager hit targets so the chevrons are easier
  to click.
- Made instance paging respect the currently selected instance when choosing
  previous/next.
- Avoided jarring camera jumps when paging between instances that are already
  visible in the canvas viewport.

## Update Notes

- v1.5 is a spine release. It preserves native EXP document data and design
  tokens, but it does not yet emit production semantic HTML/CSS.
- After publishing, test from installed v1.4 with Check for Updates -> install
  -> relaunch, then confirm About EXP [design] shows 1.5 / build 7.
- Known carry-overs remain intentionally deferred: full semantic HTML/CSS
  export, Figma/XD import, component states/relationships, the Components panel
  grid view, and richer code/storybook import.
