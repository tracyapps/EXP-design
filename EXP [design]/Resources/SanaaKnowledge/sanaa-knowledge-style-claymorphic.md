---
name: claymorphic
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
Soft, tactile, toy-like depth: puffy rounded surfaces, pastel-on-pastel, inner highlights, friendly and physical. Ask-for-it cues: "claymorphic", "clay", "soft 3D", "playful but calm".

## Type pairing
- Rounded or friendly sans (SF Rounded, Nunito, Quicksand category) with medium weights; chunky sizes for headings, generous body sizes — thin faces vanish against soft surfaces.
- Mild size contrast; sentence case; labels can be slightly tracked-out.

## Palette anchors
- Pastel base with a deeper backdrop: background mid-tone (e.g. #EEF1F8 or a soft tinted ground), cards slightly lighter than ground, accents saturated-but-soft (#7C9EFF, #FFB27A families).
- Depth comes from two tones of the SAME hue per element (base + highlight/shade), not from new hues; 3–4 hues total.
- Text stays high-contrast against pastel (deep slate #2B3144 family rather than pure black).

## Spacing density
- Plump: 16/20/24 paddings inside elements, 24–32 between cards; elements look pillow-like, so they need room to read as soft.

## Shape and corners
- Very rounded: 16–28pt radii on cards, fully-round controls; edges defined by an inner top-light highlight and bottom shade (the "clay" light model), often via subtle inner shadows/gradient fills.

## Shadow and texture
- Soft dual shadows: a diffuse drop shadow below + a tight inner highlight at the top edge; no hard borders; textures stay matte (noise at most 2–3%).
- Depth is consistent: one light source, every raised element lit the same way.

## Motion temperament
- Squishy but controlled: 200–300ms with gentle spring on press (slight scale 0.97–1.02); nothing bounces repeatedly.

## Where it works / where it fails
- Works: kids/education apps, wellness, consumer onboarding, habit trackers, friendly smart-home controls.
- Poor fit: dense professional dashboards, legal/finance documents, very dark visual identities, products needing austere credibility.

## Adapting to existing tokens
- IF the document palette is sharp/vivid THEN soften lightness toward pastel for surfaces and keep one vivid accent; tradeoff: the look quiets down.
- IF shadows/radius tokens are sharp THEN map clay depth onto the closest token radii (≥12pt) and soft shadow tokens; tradeoff: less puff.
- IF content is dense THEN clay the chrome (headers, controls), keep data areas plain — full clay at high density gets noisy.
