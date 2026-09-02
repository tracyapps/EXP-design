---
name: glassmorphic
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
Frosted translucency over rich backgrounds: blurred surface layers, light borders, floating hierarchy. Ask-for-it cues: "glassmorphism", "frosted", "vibrancy", "translucent".

## Type pairing
- Clean sans (SF/Inter category) with strong weights for legibility ON translucent surfaces; avoid thin weights over active blur — they shimmer.
- Size hierarchy moderate; white text with soft shadow only when the backing is uncontrolled (otherwise keep text on the most opaque layer).

## Palette anchors
- The BACKGROUND carries color: rich gradients/imagery (2–3 hues); glass layers are white or tinted at low opacity (e.g. white 10–30%) with the blur doing the work.
- Text near-white on dark backings, near-black on light; one accent for actions, bright enough to survive the blur.
- Surfaces get a 1pt inner light border (white ~30–50%) to catch the edge.

## Spacing density
- Medium-airy: 12/16/20 inside cards, 24–32 between floating layers; glass panels need breathing room or the blur layers stack into mush.

## Shape and corners
- Continuous, generous radii (16–24pt) — the blur needs soft rounded forms to read as intended; avoid sharp corners (they fight the softness of the blur).

## Shadow and texture
- Soft, large, low-opacity ambient shadows for float (e.g. 0 16 40 at 15–20%); optional subtle inner highlight; the blur radius itself is the texture — no noise.
- Layer discipline: one background artboard layer, glass panels above; IF every layer is glass THEN hierarchy collapses — keep at most 2 depth levels of glass.

## Motion temperament
- Floaty and smooth: 250–350ms, gentle ease, parallax on the backing (not the glass); backdrop changes animate slowly.

## Where it works / where it fails
- Works: media/creative apps, OS-style control surfaces, hero moments, short-lived overlays, dark showcase sites.
- Poor fit: dense data tools (blur under grids hurts legibility and performance), long reading, accessibility-critical flows (backing contrast is never fully controllable — let measured pairs decide text placement).

## Adapting to existing tokens
- IF the document is flat/light THEN propose glass for one layer only (a player bar, a header) over a tinted backdrop — not the whole board; tradeoff: the signature look weakens, usability strengthens.
- IF tokens have no alpha convention THEN define surface opacities explicitly (e.g. 24% white + blur) as the token set; tradeoff: new tokens to maintain.
- IF contrast over the backing can't be guaranteed THEN text sits on a more opaque local layer (say so, and let get_design_facts measure the real pair once it ships).
