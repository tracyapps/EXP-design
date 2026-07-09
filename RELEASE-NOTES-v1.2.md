# EXP [design] — v1.2

**Build 3 · macOS · 2026-07-08**

This release adds **texture effects** and a big round of **canvas editing
precision**, plus a smoother, quieter canvas and cleaner SVG output for asset
work. Your existing `.design` files open unchanged.

---

## New

### Noise & Dissolve effects
Two new stackable texture effects you can add to any shape, text, or group:

- **Noise** — grain/texture with adjustable amount, frequency, octaves, seed
  (with a shuffle die), monochrome toggle, and its own blend mode.
- **Dissolve** — a threshold-based erosion that eats away at the shape (and its
  shadows) for a distressed / weathered look.

They're built on the same `feTurbulence` algorithm browsers use, so they
**round-trip through SVG** — export a shape with noise/dissolve and it renders
the same in a browser; paste that SVG back in and the effects reattach as
editable effects. The inspector keeps things tidy: a **Simple** row (Type,
Amount, Blend) by default, with Frequency / Octaves / Seed / Mono tucked into an
**Advanced** accordion that remembers whether you left it open.

### Precise, ink-based hit-testing
Clicks now land on the **actual drawn shape**, not its rectangular bounding box.
The transparent areas of an overlapping shape no longer swallow clicks meant for
the shape underneath — so drawing overlapping forms (think tree branches) finally
behaves the way you'd expect. Filled shapes hit anywhere inside; unfilled or open
paths hit along the stroke.

### Editing inside rotated & flipped groups
You can now **move, resize, and rotate** a child inside a flipped or rotated
group and have it track your cursor correctly, with the selection box and outline
sitting on the shape instead of its mirror. Pen point editing and line endpoints
inherit the same fix.

### Better pen targeting
Adding or removing points now favors the **selected** shape when your cursor is
on its ink, and new points land **exactly on the curve** (measured along the real
bézier, not the straight chord between anchors) — so the outline doesn't distort
when you add a point.

### Hover field tips
Inspector controls now show a **help bubble** on hover — a title plus a short
explanation — starting with the effects and shadow fields. The same text is
exposed as a **VoiceOver hint**, and the bubble is smart about screen edges so it
never gets clipped by a panel or the top of the display.

### Transparent SVG export by default
SVG export no longer draws a background rectangle behind your shapes — output is
**transparent by default**, which is what you want for game assets and layered
comps. Need a real background? Add a shape layer. (PNG and PDF export are
unchanged.)

---

## Fixed

- **Gradients & shadows no longer darken during pan/zoom or drag** (BUG-003).
  Saturated, semi-transparent gradients and shadows kept their color while you
  moved around the canvas or dragged another shape.
- **Panel actions work when panels float as their own windows.** Align /
  distribute, the bold/italic text-style buttons, and Zoom to Fit no longer
  dead-end when you've popped a panel onto another monitor.
- **Shapes no longer walk sideways** when dragging a point grows the bounding box
  of a rotated or flipped path.
- **Duplicated text keeps its case transform** (e.g. uppercase) instead of
  reverting to "As typed."
- **Auto-padding components reflow correctly** while you edit text — the frame
  re-hugs as you type instead of waiting for a commit.

---

## Improved

- **Noise/dissolve stay smooth on pan & zoom.** Texture generation moved off the
  drawing path (parallelized across cores and run in the background), so scrolling
  a canvas full of textured boards no longer stutters — the grain fills in a beat
  later instead of freezing the gesture.
- **Smarter group selection.** Once you're editing inside a group, canvas clicks
  stay at that level instead of jumping back out; Shift-click toggles sibling
  children; and ⌘A expands the current selection level (group children → artboard
  contents → all artboards).
- **Design Language panel:** recent colors now read as smaller history chips, so
  they stay visually subordinate to your saved swatches.

---

## Known issues

- The centered document title's rename/location popover still anchors to the left
  (BUG-004).
- Rich text (multi-style within one text box) has one open editor bug.
- A **group** nested inside a rotated/flipped group is still move-only (single
  shapes resize/rotate fine).

---

## Accessibility

Field tips carry VoiceOver hints, and the app continues to follow all system
appearance and accessibility settings (light/dark via semantic colors). The
artboard stays white by design — you're designing a screen, not theming the tool.
