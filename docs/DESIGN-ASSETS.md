# EXP [design] — Design Asset Guide

How to make and hand off interface assets (icons, buttons, cursors, colors) so
they drop into the app with zero rework. Written for **this** codebase: SwiftUI
chrome + AppKit/Core Graphics canvas, Xcode 26.3, macOS 26 SDK, semantic colors,
full light/dark + accessibility support.

> TL;DR — **Vector + template + semantic color is the default for everything.**
> Design monochrome, on the pixel grid, name it in lowercase dot-notation, hand me
> an SVG (icons) or @1×/@2× PDF/PNG (cursors), and tell me the hotspot + where it's
> used. I wire it into `Assets.xcassets` and reference it in code.

---

## 1. Guiding principles

1. **SF Symbols first.** Every icon in the app today is an SF Symbol
   (`Image(systemName:)`). Only make a custom icon when no SF Symbol fits. Custom
   icons should look like they belong in the SF Symbols set (same weight, optical
   size, stroke feel) so the toolbar/inspector stays visually consistent.
2. **Template (tintable), not baked color.** Icons and cursors are single-color
   *template* assets. The app tints them at runtime (accent color, secondary
   label, disabled, hover). Never bake brand color into an icon — it won't adapt to
   light/dark, the accent color, or disabled states.
3. **Vector, not raster, wherever possible.** SVG/PDF scale to any Retina factor
   and any future display. Reserve raster (PNG @1×/@2×) for cursors only (NSCursor
   prefers a concrete bitmap + hotspot) and for the app icon.
4. **Semantic color, never hex.** Colors come from system semantic roles or named
   Color Sets that have light + dark variants. The canvas already follows every
   macOS appearance + accessibility setting; assets must too.
5. **Accessibility is a requirement, not a pass.** Every actionable asset needs a
   label, AA contrast, a ≥ 28×28 pt hit target even if the glyph is smaller, and
   sensible behavior under Reduce Transparency / Increase Contrast / Reduce Motion.

---

## 2. Icons

### 2a. When to use what

| Need | Use | Reference in code |
|---|---|---|
| A glyph that exists in SF Symbols | **SF Symbol** | `Image(systemName: "trash")` |
| A glyph close to SF but missing (a tool, a unique action) | **Custom SF Symbol** (`.svg` symbol template) | `Image(systemName: "tool.pen")` |
| A small illustrative/branded mark, multicolor badge, empty-state art | **Vector image set** (SVG, template or original) | `Image("emptyState.layers")` |

Prefer a **custom SF Symbol** over a plain image set for anything that sits next to
real SF Symbols (toolbar, inspector buttons) — it inherits font weight, optical
sizing, baseline alignment, and the `imageScale`/`symbolRenderingMode` machinery for
free.

### 2b. Format & canvas

- **Custom SF Symbols:** export from the official **SF Symbols app** template
  (File ▸ export template, edit the `Regular-M` layer, keep the guides). Deliver the
  edited **`.svg`**. This is the only reliable way to get correct baseline,
  cap-height, and the 9 weight×scale slots. If you only do the `Regular-M` slot,
  Xcode interpolates the rest — fine for v1.
- **Plain vector image sets:** **SVG** (preferred) or **PDF**, single artboard,
  `viewBox` tight to the artwork, no clip masks you don't need.
- **Stroke vs fill:** match SF Symbols — most are filled paths, not open strokes.
  If you draw with strokes, **outline them** before export (so scaling doesn't
  change visual weight). The canvas already has "Convert to Outlines" — use it.
- **Color:** monochrome black on transparent. Set the asset to render as a
  **Template Image** (see 2d) so the app tints it.

### 2c. Sizes & optical grid

Design on the SF Symbols grid (or a simple **point grid**) so glyphs align with the
system set. Target *point* sizes in this app:

| Context | Point size | Notes |
|---|---|---|
| Toolbar / tools strip | 16–18 pt | matches the current tool icons |
| Inspector buttons (align, effects, etc.) | 13–15 pt | drawn in a 24×20 pt button frame |
| Inline affordances (chevrons, +, trash) | 11–13 pt | `.font(.caption)`-ish |
| Empty-state / illustration | 32–64 pt | image set, can be multicolor |

Rules of thumb: build on a **16 or 24 pt** bounding box, keep **1.5–2 pt** apparent
stroke weight at 16 pt, align to whole points, and leave ~1 pt internal padding so
the glyph doesn't touch its frame. Test at 100% **and** Retina.

### 2d. Adding to the project

1. Drop the file into **`EXP [design]/Assets.xcassets`** as a new **Image Set** (or
   **Symbol Set** for custom SF Symbols).
2. In the asset's attributes: **Render As → Template Image** (tintable) for UI
   glyphs; **Original** only for multicolor art. **Resizing → Preserve Vector Data**
   so it stays crisp when scaled in SwiftUI.
3. Reference it:
   - Custom SF Symbol: `Image(systemName: "tool.pen")`
   - Image set: `Image("toolStrip.pen")` then `.renderingMode(.template)` if needed.
4. It then tints automatically via `.foregroundStyle(...)` / `.tint(...)` exactly
   like the SF Symbols already in use.

---

## 3. Naming conventions

Lowercase, **dot-separated**, `group.specifier.variant` — the SF Symbols style — so
custom assets read consistently next to system ones and sort sensibly.

| Asset kind | Pattern | Examples |
|---|---|---|
| Custom SF Symbol | `group.name[.variant]` | `tool.pen`, `tool.node`, `align.center.vertical`, `effect.innershadow` |
| Vector image set | `area.name[.state]` | `toolStrip.pen`, `inspector.gradient`, `emptyState.layers` |
| Cursor | `cursor.name[.variant]` | `cursor.pen`, `cursor.eyedropper`, `cursor.resize.diagonal` |
| Color set | `PascalCase` semantic role | `CanvasBackground`, `GuideTint`, `SelectionStroke` |
| Multi-state pairs | suffix the state | `.on` / `.off`, `.active` / `.idle`, `.disabled` |

Conventions:
- **Describe the meaning, not the picture** (`align.center.vertical`, not
  `lines-with-bar`) so swapping the artwork later doesn't orphan the name.
- Use the **singular** (`guide`, not `guides`).
- Keep tool icon names matching the `Tool` enum where possible (`tool.pen`,
  `tool.rectangle`, `tool.ellipse`, `tool.line`, `tool.text`, `tool.select`,
  `tool.node`).
- **Never** put light/dark or size in the name — those are variants *inside* the
  asset (slices / appearances), not separate files.

---

## 4. Buttons & controls (match these so new UI is seamless)

The inspector/panel system already has consistent metrics. New controls should reuse
them rather than invent sizes:

| Token | Value | Where |
|---|---|---|
| Icon button frame | **24 × 20 pt**, `.buttonStyle(.bordered)` | align row, effects, B/I/U |
| Active/toggle highlight | `accentColor.opacity(0.25)` rounded-5 fill | bold/align active state |
| Numeric field width | 40–56 pt, `.roundedBorder`, `.monospacedDigit`, trailing | X/Y/W/H, size, gutter |
| Section header | `.font(.caption).foregroundStyle(.secondary)` | "Effects", "Layout Grids" |
| Card / row background | `Color.primary.opacity(0.04)`, corner radius 6 | effect rows, grid rows |
| Standard horizontal padding | **12 pt** | every inspector section |
| Row vertical gap | 6–8 pt | `VStack(spacing:)` |
| Divider | SwiftUI `Divider()` between sections | inspector |

When proposing a new panel, deliver it as a **redline/spec** in these tokens (or just
say "matches the Effects section") and I can build it directly. Buttons themselves are
system `.bordered`/`.borderless` styles — you supply the **icon**, not a full button
bitmap.

---

## 5. Cursors

Custom cursors are AppKit `NSCursor(image:hotSpot:)`. Today the app uses system
cursors (`NSCursor.openHand`, `.closedHand`, `.crosshair`, `.resize*`, etc.) chosen in
`desiredCursor(at:flags:)`. Add custom ones only where the system set has no good fit
(pen, eyedropper, the rotate cursor).

**Deliverables per cursor:**
- **Artwork:** vector **PDF** (preferred, scales to Retina) *or* PNG at **@1× and
  @2×**. Native cursor size is **16–24 px**; design within a **32 × 32** box with the
  art centered so the hotspot has room.
- **Hotspot:** the active point in **@1× pixels from the top-left** (e.g. pen tip =
  `(3, 2)`; crosshair center = `(8, 8)`). **This is mandatory** — give it to me with
  the asset.
- **Style:** black fill + **1 pt white outline/halo** so the cursor reads on any
  background (this is why system cursors have a white edge). Template tinting does
  *not* apply to cursors — they're full bitmaps — so bake the black+white in.
- **Naming:** `cursor.pen`, `cursor.eyedropper`, `cursor.resize.diagonal`.

**How it's wired** (so you know what I do with it): the image goes in the asset
catalog, then `NSCursor(image: NSImage(named: "cursor.pen")!, hotSpot: NSPoint(x: 3, y: 2))`,
returned from `desiredCursor`. Provide a **light and dark** variant only if the plain
black+white version doesn't read in dark mode (usually the white halo is enough).

---

## 6. Colors

The app is strictly semantic + appearance-aware. Two sources:

1. **System semantic roles** (use first): `Color.primary`, `.secondary`,
   `Color.accentColor`; AppKit `NSColor.controlAccentColor`, `.separatorColor`,
   `.secondaryLabelColor`, `.windowBackgroundColor`, `.underPageBackgroundColor`,
   `.systemRed`, etc. These already track light/dark, accent, and Increase Contrast.
2. **Named Color Sets** in `Assets.xcassets` for anything app-specific (a guide tint,
   a canvas chrome color). **Always provide a light *and* a dark appearance slice**,
   and ideally a **High Contrast** slice. Reference via `Color("GuideTint")` /
   `NSColor(named: "GuideTint")`.

**Accent color:** `AccentColor.colorset` is currently empty (the app uses the user's
system accent — the macOS-correct default). Only fill it in if EXP needs a fixed brand
accent; if so, add light/dark/high-contrast variants and confirm AA contrast on both
backgrounds.

**Current ad-hoc colors worth promoting to named sets during the panel pass:**
- Guide line: cyan `sRGB(0, 0.66, 0.93)` → `GuideTint`
- Measurement overlay: `systemRed` → `MeasureTint`
- Default layout-grid fill: translucent red `rgba(1,0,0,0.1)` → `LayoutGridTint`
- Selection chrome: `controlAccentColor` (keep semantic)

**Hard rules:** never ship a raw hex in code; never assume a white background (the
artboard is white by default but the *app chrome* follows dark mode); every
foreground/background pair must hit **WCAG AA (4.5:1 text, 3:1 large/UI)** in both
appearances.

---

## 7. Spacing & metrics already in use

Reuse these constants so assets and new panels line up with the existing canvas:

| Constant | Value |
|---|---|
| Selection handle size / grab radius | 8 pt / 12 pt |
| Rotate knob offset | 22 pt above top-mid |
| Ruler thickness | 20 pt |
| Guide hit tolerance | 4 pt |
| Snap threshold | 6 / zoom (doc pts) |
| Inspector section padding | 12 pt horizontal |
| Card corner radius | 6 pt |

---

## 8. Accessibility checklist (every actionable asset)

- [ ] **Label:** an `.accessibilityLabel` / `help(...)` describing the *action*
      ("Align left edges"), not the picture. Icon-only buttons need a tooltip too.
- [ ] **Contrast:** glyph vs its button/background ≥ **3:1** in light *and* dark;
      text ≥ **4.5:1**. Re-check under Increase Contrast.
- [ ] **Hit target:** actionable area ≥ **28 × 28 pt** even when the glyph is 14 pt
      (pad the button, don't enlarge the icon).
- [ ] **State is not color-only:** active/selected must differ by more than hue
      (fill, outline, checkmark) — important for color-vision differences.
- [ ] **Reduce Transparency:** translucent fills (grid tints, card backgrounds) need
      an opaque fallback.
- [ ] **Reduce Motion:** any animated asset/cursor needs a static equivalent.
- [ ] **Template tinting:** confirm the icon still reads when tinted secondary/
      disabled (low contrast), not just at full accent.
- [ ] **Inclusive language** in names and labels ("source", never "master").

---

## 9. Handoff — how to give me assets so they drop in

Put deliverables in a predictable spot and I'll integrate + reference them in code.

**Folder:** create `design-assets/` at the repo root (staging area, not the asset
catalog). Inside, group by kind:

```
design-assets/
  icons/        tool.pen.svg, align.center.vertical.svg, ...
  cursors/      cursor.pen.pdf (+ optional @2x.png), ...
  colors/       colors.md   (name → light hex, dark hex, high-contrast hex)
  illustrations/ emptyState.layers.svg
  ASSETS.md     the manifest (below)
```

**Manifest (`design-assets/ASSETS.md`)** — one row per asset so nothing is ambiguous:

| name | kind | file | render-as | used where | hotspot | a11y label |
|---|---|---|---|---|---|---|
| `tool.pen` | sf-symbol | icons/tool.pen.svg | template | tools strip | — | "Pen tool" |
| `cursor.pen` | cursor | cursors/cursor.pen.pdf | bitmap | pen tool drag | 3,2 | — |
| `GuideTint` | color | colors/colors.md | — | guides | — | — |

With that, integration for me is mechanical: import into `Assets.xcassets`, set
render mode / vector-preserve, and swap the `Image(systemName:)` / `NSCursor` /
`Color(...)` call sites. **The cleanest workflow as we redo panels:** hand me a batch
in `design-assets/` + an updated `ASSETS.md`, and I'll wire the whole set in one pass
and report any that need a missing variant (e.g. a dark slice).

---

## 10. Quick reference

- **Icon:** SVG, monochrome, template, dot-named, 16/24 pt grid, outline strokes.
- **Cursor:** PDF or @1×/@2× PNG, black+white baked, hotspot in @1× px, 32-px box.
- **Color:** named Color Set with light + dark (+ high-contrast); never hex in code.
- **Button:** you supply the icon; the app supplies the system button style/size.
- **Name:** lowercase dot-notation, meaning-based, no size/appearance in the name.
- **Deliver:** `design-assets/<kind>/` + `ASSETS.md` manifest with hotspots + labels.
