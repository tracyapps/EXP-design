# EXP [design] — Visual Handoff & Token Sheet

A working template for handing visual redesigns to implementation. Fill in the
**New** columns, annotate screenshots against these token names, and spec
components with all their states. Values are in **points** (1 pt = 1 px @1x).

> Current values are best-effort from the code as of Session 118 — correct any
> that are off; they're just a starting point, not gospel.

---

## 0. How to use this doc

1. Edit the **token tables** first (Section 2) — this is the design *system*. Use
   the role names (e.g. `panel.bg`) in your screenshot callouts so everything maps.
2. For each component, copy the **component template** (Section 4) and fill it in,
   including every interactive **state**.
3. For anything translucent/glassy, use the **material vocabulary** (Section 3) so
   it's unambiguous which technique to build.
4. Hand off: token sheet + annotated full-app "north star" + component specs.

Implementation note: app **chrome** (panels, inspector, toolbar, tools strip,
trays, menus, buttons) is SwiftUI → materials/glass are easy. The **canvas**
(artboards, shapes, rulers, handles) is hand-drawn Core Graphics → no backdrop
blur; flag any glass that sits *on the canvas* as it needs a different approach.

---

## 1. Foundations

| Thing | Current | New |
|---|---|---|
| Appearance | follows system light/dark (semantic colors) | |
| Base unit | 2 / 4 / 8 / 12 / 16 spacing rhythm | |
| Primary type | system font | |
| Accent | system accent (`controlAccentColor`) | |
| Corner language | mixed 4–8 (see radii) | |

---

## 2. Tokens

### 2.1 Color roles
Give hex + opacity. Note **light** and **dark**, or write "system: <name>" to inherit.

| Role | Current (approx) | New — Light | New — Dark |
|---|---|---|---|
| `window.bg` | system window background | | |
| `panel.bg` | system background | | |
| `panel.section.label` | secondary label | | |
| `divider` | `separatorColor` | | |
| `row.hover` | `primary @ 0.06` | | |
| `row.selected` | accent fill | | |
| `field.bg` | system control / rounded-border | | |
| `text.primary` | primary label | | |
| `text.secondary` | secondary label | | |
| `text.tertiary` | tertiary label | | |
| `accent` | system accent | | |
| `accent.subtle` | accent @ ~0.12–0.25 | | |
| `selection.stroke` | accent | | |
| `dropline` | accent | | |
| `padding.overlay` | teal @ 0.22 | | |
| `margin.overlay` | orange @ 0.18 | | |

### 2.2 Spacing
| Token | Current | New |
|---|---|---|
| `space.xxs` | 2 | |
| `space.xs` | 4 | |
| `space.sm` | 6 | |
| `space.md` | 8 | |
| `space.lg` | 12 | |
| `space.xl` | 16 | |
| panel padding (h) | 12 | |
| section gap | 8 (+4 above headers) | |

### 2.3 Radii
| Token | Current | New |
|---|---|---|
| `radius.row` | 6 | |
| `radius.field` | rounded-border (system) | |
| `radius.dropInto` | 4 | |
| `radius.button` | (design) | |

### 2.4 Stroke
| Token | Current | New |
|---|---|---|
| `stroke.hairline` | 1 | |
| `stroke.selection` | 1.5 | |
| `dropline` | 2 (capsule, inset 6) | |

### 2.5 Type scale
| Token | Current | Size / Weight (New) |
|---|---|---|
| `type.sectionLabel` | `.caption` secondary | |
| `type.fieldLabel` | `.callout` secondary | |
| `type.body` | `.callout` | |
| `type.rowTitle` | 12 medium | |
| `type.rowSub` | 10 secondary | |
| `type.micro` | `.caption2` | |

### 2.6 Elevation / shadows
Spec as `x / y / blur / spread / color@opacity`.

| Token | Current | New |
|---|---|---|
| `shadow.panel` | — | |
| `shadow.popover` | system | |
| `shadow.dragging` | — | |

### 2.7 Layout metrics
| Thing | Current | New |
|---|---|---|
| left dock width | 264 | |
| right dock width | 332 | |
| tools strip width | (fixed) | |
| ruler thickness | 20 | |
| default window | 1500 × 950 | |
| anchor handle size | (handleSize) | |
| grab radius | (handleGrab) | |

---

## 3. Material vocabulary (use these exact terms)

Pick the bucket and give the noted detail — that tells me precisely what to build.

| Term | What it is | What to specify |
|---|---|---|
| **Translucent flat** | solid color < 100% opacity, **no blur** | `rgba()` + what it sits over |
| **Material / frosted glass** | real backdrop blur + optional tint (NSVisualEffectView / SwiftUI `Material`) | thickness: `ultraThin / thin / regular / thick` + tint color@opacity |
| **Vibrancy** | labels/icons that blend into a material | just say "vibrant labels" |
| **Liquid Glass** | macOS 26 native dynamic glass (real API, not faked) | say "Liquid Glass" + optional tint |
| **Gloss / sheen** | gradient highlight overlay on a fill | base fill + `linear-gradient(white 0.X → 0 over top N%)` + optional inner shadow |
| **Shadow** | drop/inner shadow | `x / y / blur / spread / color@opacity` |
| **Stroke** | border | width + color@opacity + inside/center/outside |

Reference shortcuts that communicate intent instantly: "like Control Center,"
"like the Sketch inspector," "like Finder's sidebar," "like a Sequoia toolbar."

---

## 4. Component spec template

Copy this block per component. Always include states.

```
### <Component name>
Reference: <real-world example, optional>
Anatomy: <parts — e.g. icon + label + chevron>

Layout:
  size / min-size:
  padding:           (t r b l)
  gap:
  radius:
  alignment:

Surface (use Section 3 vocabulary):
  fill:
  border:
  sheen/overlay:
  shadow:

Content:
  label type / color:
  icon size / color:

States:
  default:    <deltas from above>
  hover:
  pressed:
  selected:
  disabled:
  focus (keyboard):

Motion (optional): <duration / easing on hover/press>
Accessibility: <contrast target, focus ring, hit target ≥ 24>
```

### Worked example — Primary button (edit to taste)
```
Surface: Liquid Glass, tint accent@0.14 · radius 8
Border:  1px white@0.15
Sheen:   linear-gradient(white 0.20 → 0 over top 40%)
Shadow:  0 1 2 0 black@0.25
Label:   13pt semibold, vibrant
Padding: 8 14 8 14
States:
  hover:    tint accent@0.20
  pressed:  tint accent@0.28, sheen off, shadow 0 0 1 0 black@0.2
  disabled: tint @0.06, label text.tertiary, no sheen/shadow
  focus:    2px accent focus ring, 2px offset
```

---

## 5. Handoff checklist
- [ ] Token sheet filled (colors light+dark, spacing, radii, type, materials)
- [ ] One annotated full-app "north star" screen
- [ ] Component specs with **all states**
- [ ] Materials named with Section-3 terms (no guessing blur vs flat)
- [ ] Any **canvas-overlay** glass explicitly flagged
- [ ] Measurements in points; callouts reference token names
```

This file is the spec. I'll keep the implemented code matching the **New**
columns; if a value isn't filled in, I'll keep the current value.
