---
name: exp-design
description: Use this skill to generate well-branded interfaces and assets for EXP [design] — a native macOS design app (Liquid Glass, macOS light/dark, SF Pro / SF Compact, SF-Symbols iconography, purple-tinted #181819 base). Use for production SwiftUI/CSS work or throwaway prototypes, mocks, and slides. Contains the design tokens, type, colors, materials, logo, and a full UI-kit of React component recreations.
user-invocable: true
---

Read the `readme.md` file within this skill first — it carries the full design
guide: content voice, visual foundations, iconography, and the file index. Then
explore the other files as needed.

- **Tokens** live in `styles.css` → `tokens/*.css` (colors, typography, spacing,
  glass/elevation). Link `styles.css` and use the CSS custom properties; never
  hardcode hex. Put `.exp-dark` or `.exp-light` on a parent for appearance.
- **Components** are React (`components/<group>/<Name>.jsx`), exported on
  `window.EXPDesignDesignSystem_fb82b2` after loading `_ds_bundle.js`. Each has a
  `.d.ts` (props) and `.prompt.md` (usage). Compose them — don't re-implement.
- **UI kit** `ui_kits/exp-editor/index.html` is the interactive product
  recreation — read it to match the real editor's layout and behavior.
- **Materials:** the brand is Liquid Glass. Use `.glass-thin` / `.glass-medium` /
  `.glass-thick` + `.glass-edge`; reserve heavy effects for real panels.
- **Iconography:** SF Symbols in the app; **Phosphor Icons** (CDN web font) is the
  web substitute — `weight="fill"` for active glyphs. Load the Phosphor CSS.
- **Brand lime** is a spice, not a sauce: the mark, a focus glow, one status dot.
  Blue owns interaction. No emoji. Lowercase copy; UPPERCASE panel titles.

If creating visual artifacts (slides, mocks, throwaway prototypes), copy the
assets you need out and produce static HTML files for the user to view. If
working on production code, copy assets and apply the rules here to design as an
expert in this brand.

If the user invokes this skill without other guidance, ask what they want to
build or design, ask a few focused questions, then act as an expert designer who
outputs HTML artifacts *or* production code, depending on the need.
