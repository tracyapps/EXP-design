# EXP [design] — Design System

A design-token system and UI kit for **EXP [design]** — a native macOS design
app that *gets out of your way*. Built for UX/UI designers, by a UX/UI designer
frustrated with the expensive big-tech tools. This system finalizes the visual
language for the SwiftUI app: **macOS-native light/dark, Core Liquid Glass
(thin → thick), SF Pro / SF Compact in light & ultralight weights, SF-Symbols
iconography, and a purple-tinted `#181819` base.** The goal: even the pickiest
designer says *"oh, that's cool."*

> The center **canvas is intentionally undesigned** — it belongs to the user's
> artboards. Its tokens are isolated under `--canvas-*`; change them sparingly
> and on purpose (see colors.css).

---

## Sources this was built from

- **Codebase** (read-only, mounted): `EXP [design]/` — a full Xcode project.
  Swift 6.2 / SwiftUI (chrome) + AppKit/Core Graphics (canvas), Xcode 26.3,
  macOS 26 SDK. Ground-truth UI lives in `EXP [design]/EXP [design]/UI/`
  (`MainWindow.swift`, `ToolsStrip.swift`, `LayersPanel.swift`,
  `Typography.swift`) and `…/Model/AppState.swift` (the `Tool` enum + state).
- **Docs**: `EXP [design]/docs/` — `DESIGN-ASSETS.md` (icon/cursor/color handoff
  rules), `VISUAL-HANDOFF.md` (the token sheet this CSS implements),
  `ROADMAP.md`, `WORKING-AGREEMENT.md`. These are the authoritative spec; the
  token values here come from them.
- **Logo**: `EXP[design]-icon.png` → copied to `assets/exp-logo.png`.
- **Screenshots**: ~20 in `uploads/` — the current app plus the owner's in-flight
  redesign (the dark "Untitled / Properties" three-pane shell is the north star).

Numbers (paddings 12, radius 6, row 28, etc.) are copied from the source, not
snapped to a grid. Where the source uses 5, 6, or 12 px, this system uses 5, 6,
12 — never a rounded 4/8.

---

## Font substitution ⚠

The brand type is **SF Pro / SF Pro Display / SF Compact** — these *are* the
macOS system fonts, present on every target machine, so the tokens reference them
via the native font stack rather than bundling webfonts (Apple's license forbids
redistribution). On non-Apple browsers the stack degrades to the platform UI
font. **If you need pixel-identical SF rendering off-Apple, upload the licensed
SF font files and add `@font-face` rules** — the token names won't change.
The compiler flags these as "missing @font-face"; that is expected here.

---

## CONTENT FUNDAMENTALS — how EXP writes

The voice is a working designer talking to a working designer: **plain, lower-key,
confident, a little dry.** It never sells.

- **Casing — lowercase by default.** UI labels and the brand's own voice run
  lowercase: `align`, `distribute`, `selection`, `artboard`, the `[design]`
  mark. Lowercase is the house style; it reads calm and modern. Exceptions that
  earn capitals: **panel titles are UPPERCASE** (`LAYERS`, `PROPERTIES`), proper
  control names follow macOS conventions (`Inspector`, `Blend`, `Opacity`,
  `New Artboard`), and the `EXP` wordmark is caps.
- **Person.** Product/system copy is impersonal and instructional ("the tool
  should get out of the way," "follow all system accessibility settings").
  Tooltips name the *action*, not the picture: "Align left edges," not
  "lines with a bar." Owner-facing docs use first person ("I'll wire it in").
- **Tone.** Honest about limits, allergic to hype. Tooltips are terse and carry
  the shortcut: `Select (V)`, `Zoom out (⌘-)`. Section labels are single words
  (`Effects`, `Stroke`, `Align`).
- **Emoji:** none. Not in product, not in chrome. Iconography is SF Symbols.
- **Placeholders have personality** but stay neutral: `a text layer.`,
  `some shape. huzzah`, `another long layer name that…`, `awesome document #5`.
  Truncation uses an ellipsis char `…`, mid-word, never three dots.
- **Numbers** are bare and unitless inline (`393 × 852`, `100`, `12 × 11 · 8
  layers`); units sit quietly inside fields (`°`, `%`).
- **Inclusive language is a hard rule** — "source," never "master."

Vibe in one line: *quiet precision.* The interface whispers so the work can talk.

---

## VISUAL FOUNDATIONS

**Appearance.** macOS-native, fully appearance-aware. **Dark is the design home**
(the owner works in dark); light is a faithful mirror. Every surface, text tier,
and material has both. Force a scope with `.exp-dark` / `.exp-light` on a parent.

**Color.**
- *Base:* the owner's signature `#181819` — a near-black with a whisper of purple
  (hue ~280, near-zero chroma). The neutral ramp (`--n-0…900`) carries that faint
  tint so the whole chrome feels cool-violet rather than flat gray.
- *Interactive accent:* **macOS system blue** (`--accent` — `#0a84ff` dark /
  `#007aff` light). Selection, active tool, focus rings, primary buttons, the
  segmented "on" state. It tracks the user's system accent in the real app.
- *Brand accent:* the logo's **neon lime** (`--brand-lime #4ce62e`). A *spice,
  not a sauce* — the wordmark's `[design]` bracket, a focus glow, a single "live"
  status dot. Never a large fill or a button. Blue owns interaction; lime owns
  identity.
- *Semantic:* system green/red/orange + a guide-cyan/teal (the canvas GuideTint).
- *Hierarchy from opacity:* text is tiered by alpha — 100 / 62 / 42 / 28 % —
  matching the app's "15pt 70%, 12pt 60%" spec, as much as by size.

**Type.** SF Pro (UI), SF Pro Display (large/airy), **SF Compact** (the condensed
voice — layer names, dense labels, ruler numerals), SF Mono (digits). The brand
default weight is **light/ultralight** — chrome should feel lightweight and
modern; **medium** is the one emphasis weight (active layer name, primary button,
artboard name). Scale lives at 10–15px for chrome; display goes to 64. Uppercase
panel titles are tracked `+0.06em`.

**Materials — Liquid Glass.** The chrome is real backdrop blur + a thin tint + a
lit top edge + a soft shadow. Two core thicknesses per the brief — **thin**
(toolbars, trays, the tools rail), **medium** (docks, popovers — the default
panel) — plus **thick** (modals / the floating component editor) for maximum
separation. Compose `.glass-edge` for the lit rim + sheen. Reduce-Transparency
swaps to opaque plates automatically. The extra "thickness" reads as hierarchy:
deeper panels = more blur + more tint + a heavier shadow.

**Elevation.** Layered drop shadows: `--shadow-1` (rows) → `2` (chips) →
`panel` (docks) → `popover` (menus) → `modal` (editor) → `drag`. Glass also
carries an inner top-lip highlight + a bottom seat so panels look like physical
slabs.

**Borders & strokes.** Hairlines are `separatorColor` analogs (white @ ~9% dark).
Glass gets a brighter lit rim (white @ 12%). Selection stroke is **1.5px** accent;
hairline **1px**; dropline **2px**. Fields use an inset 1px shadow + 1px border.

**Radii.** Deliberately small and varied: drop 4 · field 5 · row/card/tool 6 ·
control 7 · button 8 · panel 12. Pills for badges. Cards are a 6px rounded
`white @ 4%` fill with a soft border — no heavy shadow, no colored left-border.

**Spacing.** 2 / 4 / 6 / 8 / 12 / 16 / 24 / 32. Panels pad **12** horizontal;
rows gap **6**; sections gap **8** (+4 above a header). Layer rows are **28** tall.

**Layout.** Fixed left tools rail (44), left dock 264, right dock 332, ruler 20,
default window 1500 × 950 (min 900 × 600). The canvas takes all leftover space and
letterboxes the artboard on the dark wall.

**Motion.** Restrained and macOS-ish: `--ease-standard` ease-out for most state
changes (120–180ms); a gentle `--ease-emphasis` overshoot only on toggles
(switch knob). No bounce on content, no infinite loops. Hover is a soft wash
(white 6%), active a stronger wash (10%) or accent-subtle; press shrinks ~1.5%
and drops the shadow. Respects Reduce Motion.

**Imagery.** The product has none of its own — it's a tool; the imagery *is* the
user's artboards (full-bleed, any color). Marketing surfaces use the ink plate +
lime mark over a dark, slightly-violet field.

---

## ICONOGRAPHY

- **In the app:** **SF Symbols**, exclusively, in **solid / hierarchical**
  rendering — `Image(systemName:)`, tinted at runtime (accent / secondary /
  disabled), never baked color. Custom glyphs are authored as SF Symbol templates
  so they inherit weight, optical size, and baseline. Naming is lowercase
  dot-notation (`tool.pen`, `align.center.vertical`). No emoji, ever. Tool glyphs
  map to the `Tool` enum: `cursorarrow`, `beziercurve`, `rectangle`, `circle`,
  `triangle`, `line.diagonal`, pen, `textformat`.
- **In this web system (substitution ⚠):** SF Symbols can't ship to the browser,
  so cards/kits use **[Phosphor Icons](https://phosphoricons.com/)** via CDN —
  the closest match to SF Symbols' filled/hierarchical feel (rounded terminals,
  a `fill` weight for active glyphs, `regular` for idle). Loaded as a web font
  from `unpkg.com/@phosphor-icons/web`. The `Icon` / `IconButton` components wrap
  it; `weight="fill"` ≈ SF "hierarchical, solid." **Flag:** if you need exact SF
  parity in a deliverable, render in the real app or export SF Symbol SVGs — tell
  the owner. SF→Phosphor map (partial): cursorarrow→`cursor`,
  beziercurve→`bezier-curve`, line.diagonal→`line-segment`, pen→`pen-nib`,
  textformat→`text-t`, eye→`eye`/`eye-slash`, lock→`lock-simple`(`-open`),
  chevron→`caret-*`, plus→`plus`, sidebar→`sidebar-simple`.
- **Logo:** `assets/exp-logo.png` — white `EXP.` set tight, the lime `[design]`
  bracket, on the `#121212` ink plate. The only place lime carries weight.

---

## Index / manifest

**Root**
- `styles.css` — the entry point consumers link (import manifest only).
- `tokens/` — `colors.css`, `typography.css`, `spacing.css`, `glass.css`.
- `assets/` — `exp-logo.png`.
- `SKILL.md` — Agent-Skill front matter for Claude Code use.

**Foundations** (`guidelines/`, shown as Design-System cards)
- Colors: neutrals · surfaces · accent · semantic · text tiers
- Materials: liquid-glass thicknesses · elevation
- Type: families · scale · chrome roles · weights
- Spacing: scale · radii
- Brand: logo lockup · brand lime

**Components** (`components/`, namespace `window.EXPDesignDesignSystem_fb82b2`)
- `controls/` — Button, IconButton, SegmentedControl, Switch, Checkbox, Slider, Icon
- `inputs/` — TextField, NumericField, Select, ColorWell
- `structure/` — Panel, SectionHeader, Divider, LayerRow, ToolStrip
- `feedback/` — Badge, Tooltip

**UI kit** (`ui_kits/exp-editor/`)
- `index.html` — the interactive three-pane editor (tools · layers · canvas ·
  inspector). Click tools, select layers, edit the inspector, toggle panels,
  switch light/dark. Composed from the component primitives.

---

## Using it

Consumers link one file:

```html
<link rel="stylesheet" href="styles.css">
<!-- icons (substitute) -->
<link rel="stylesheet" href="https://unpkg.com/@phosphor-icons/web@2.1.1/src/regular/style.css">
<link rel="stylesheet" href="https://unpkg.com/@phosphor-icons/web@2.1.1/src/fill/style.css">
```

Then read components from the namespace after loading `_ds_bundle.js`:
`const { Button, Panel, LayerRow } = window.EXPDesignDesignSystem_fb82b2;`.
Put `.exp-dark` (or `.exp-light`) on a parent to pick the appearance.
