---
name: directions
version: 2.0.0
updated: 2026-08-31
---

## TL;DR
How to compose design directions: silently enumerate candidates, pick the most genuinely distinct ones, declare each as an explicit diff on the style genome below, draw one per artboard via apply_edits, hand control back. Variations that reuse the original's elements are a defect.
Load when: the designer asks for variations, options, directions, "mock up a couple", or "explore this".

## The contract
- 3–4 directions by default, never 1; never exceed 4 — choice overload is real. "Just a couple" → draw 2, still fully divergent (divergence contract below).
- Each direction = a concept name + a genome diff + a one-line rationale + a one-line tradeoff. No diff, no direction.
- Diversity ≠ extremes: diverge on axes, not garishness. A direction that fights the brief is worse than two good ones — offer fewer when the brief is narrow, and say why.
- The stuck-designer case ("I'm stuck — mock up a couple to get me started") is where this module earns its keep: enumerate across genome corners, move layout grammar in at least one direction, type or color in another. Samey output here is the failure mode this file exists to prevent. State the defaults you chose in the reply's first line ("spreading across layout + type corners — say which axis to push") so a stuck designer can redirect in one word.

## Style genome — choose explicitly, never by default
Nine axes. Per direction, pick one option per axis and record it in the direction's diff; axes left unstated inherit the document's own values. Tradeoff: declaring the genome costs a beat of reasoning — skipping it is how directions collapse into the model default.

- **Layout grammar** — single column / split / asymmetric grid / bento / sidebar-app / hero-forward / data-dense. Reads right: single column for linear reading (docs, onboarding); split for text-vs-subject contrast (marketing, features); asymmetric grid for editorial weight (portfolios, magazines); bento for scannable feature mosaics; sidebar-app for tools and dashboards; hero-forward for one dominant statement (launches, brand moments); data-dense for analytics and finance.
- **Type pairing strategy** — single-family weight range (IBM Plex Sans, Source Sans 3, or Public Sans — weights carry hierarchy); serif+sans contrast (Source Serif 4, Lora, or PT Serif headings over a plain sans); display+neutral body (Space Grotesk, Sora, or Fraunces display over Source Sans 3 or Public Sans); mono-as-accent (IBM Plex Mono, JetBrains Mono, or Space Mono for labels, numbers, code — body stays sans). All examples are freely available; substitute the closest licensed face in the document and keep the strategy. Sizes and steps per typography.md.
- **Color strategy** — monochrome (one hue stepped in lightness; calm, hardest to clash) / analogous (neighboring hues; cohesive, low tension) / complementary (opposed hues; energetic, needs restraint) / split-complementary (base plus two neighbors of its opposite; vivid but steadier than complementary) / duotone-two-accent (neutral field, two accents; rich but noisy past two). Keep 60-30-10 (dominant/secondary/accent), compose lightness-first, anchor in tokens per color.md, and name the neutral temperature — warm reads approachable, cool reads technical.
- **Shape language** — radius family 0 / 2–4 / 8–12 / 16+ / full-pill: 0 reads formal-editorial, 2–4 enterprise, 8–12 neutral-consumer, 16+ playful, pills for chips and actions. Boundary treatment: fills carry weight, hairlines carry structure, borders carry separation — name one as primary. Stroke weight follows the radius family: ~1pt at 0–4, 1.5–2pt at 8+.
- **Icon style** — outline (light, technical) / filled (confident, small-scale) / duotone (friendly, product-marketing); rounded terminals suit radius 8+, sharp suits 0–4; stroke weight matches the shape boundary weight. Mixing icon styles inside one direction is a defect.
- **Elevation & depth** — flat (swiss, editorial) / hairline layers (docs, data-dense) / soft shadows (consumer cards) / hard offset shadows (neo-brutalist, playful) / glass (media-rich heroes, sparingly). If a style module is loaded, its shadow-and-texture section wins.
- **Density** — compact (enterprise tables, dashboards) / regular (default product surface) / airy (marketing, editorial). Density moves the whole spacing scale, not just paddings — spacing-layout.md stays descriptive evidence, not a target.
- **Texture & finish** — none is the default; grain only for editorial/poster contexts with the designer's nod. Anti-generic blocklist items (gradient identities, blobs, mesh decoration) stay out regardless of brief.
- **Motion temperament** — 150–200ms fades/offsets, ease-out in, ease-in out, no bounce. The canvas is static, so declare temperament in the rationale line; the handoff carries it.

## Divergence contract — hard rules
Every direction, always — including a "quick, just a couple" ask (speed compresses polish, never divergence):
- A concept NAME stating intent, not treatment ("Ledger", not "the blue one").
- A genome diff of ≥3 named axes changed vs the original AND vs each sibling, written from→to: "radius 8–12 → 0", "type: single-family → serif+sans", "elevation: soft shadows → flat".
- A one-line rationale and a one-line tradeoff.
Self-check before proposing: if a direction only recolors or only re-lays-out the original, redraw it. If two siblings share ≥3 genome axes, redraw one of them.
Set-level rule: across the set, at least one direction moves layout grammar, and at least one moves type pairing or color strategy — an all-surface or all-structure set is a defect. At most one direction per set may keep the original's layout grammar; if two siblings hold the original's section skeleton, redraw one of them.
Tradeoff: full divergence costs more drawing per direction; the payoff is a real decision instead of pixel-shuffles of the first safe idea.

## Silent candidate enumeration
Before drawing, privately list ~5 candidate concepts with rough fit-to-brief likelihood, then render the requested count from the strongest genuinely distinct candidates — diversity comes from the tail, not the first safe idea. IF the five cluster on one idea THEN force 2–3 candidates from different genome corners (different layout grammar, different type strategy) before picking. Don't show the enumeration unless asked; if asked "what else did you consider", share the tail in the same name+diff format. Tradeoff: a little silent overhead; the payoff is the documented diversity gain of tail-sampling (verbalized-sampling research, arXiv 2510.01171 — 1.6–2.1× without quality loss).

## Adjective decoder
Mood words are not a spec. Decode into axis moves, read them back, then draw:
- "more professional" → radius family down a step; single-family type with strong weight steps; cool neutral temperature; accent confined to small marks.
- "more modern" → display+neutral body pairing; asymmetric grid or bento; flat or hairline elevation; one deliberate asymmetric move elsewhere.
- "cleaner" → monochrome or duotone strategy; fill→hairline boundaries; density to regular or airy; fewer boundary treatments, not fewer features.
- "friendlier" → radius family up a step; rounded filled icons; warm neutral temperature; analogous palette.
- "more premium" → serif+sans contrast; airy density; lightness-first dark or deep-neutral field; one material change (soft shadow or hairline layers) — never a gradient identity.
- "more technical" → mono-as-accent type; data-dense or sidebar-app grammar; radius 0–2–4; outline icons at consistent stroke; cool neutrals.
Tradeoff: decoded moves are hypotheses, not verdicts — invite veto of any move before it multiplies across the board.

## Reference-image mode
IF a screenshot or reference sits on the canvas THEN extract its genome per axis first: proportions, palette strategy + neutral temperature, type character (contrast, weight, case), radius family, density, icon style, elevation. IF the reference is an image node and this request carries no vision channel, SAY which axes cannot be extracted (palette, type character) and ask the designer for those traits as words or as a source artboard in the document — never state values for axes you cannot see. IF the reference exists as a real artboard in this document, read it with get_artboard and extract from its nodes instead. Derive every value onto the document's own tokens (nearest token hues, matching weight steps, its radius scale) — never lift assets, imagery, or content from the artifact. State the per-axis mapping so the designer can veto any trait ("kept their 8–12 radius; swapped their indigo for your brand hue"). Tradeoff: mapping is approximate — say which axes are confident (radius, density) and which are judgment (type character). Borrow the system, not the artifact's content; if the reference itself shows slop-tells, name them and depart deliberately.

## Style anchor and floor
- Default: the document's own language — read get_tokens and existing artboards first; directions stay inside the document palette and typography unless the designer asks to depart. Axes that stay home are recorded as "unchanged: <axis>".
- Explicit style ask ("make it editorial"): load styles/<name>.md and adapt per that module's rules; the genome diff records the result.
- No tokens yet: propose a minimal token set per direction (surface/text/accent roles) so the designer accepts a system, not a one-off.
- Run anti-generic.md before composing: no blocklist clusters, one signature element per direction, real content, real states. If one direction is deliberately conventional, label it: "the conventional take — the baseline."

## Output contract
- Reply per direction: name → genome diff (from→to) → rationale → tradeoff. Then draw.
- apply_edits: ONE batch per direction, each on a NEW artboard; "variations" default to a new page "Sanaa — <topic> variations". Batch-created artboards need switches only; touching existing artboards asks per-document. Fragments must be real design.json shapes from get_node/get_artboard output — anything else is refused.
- Artboard names carry the lead axis: "A — layout: split", "B — type: serif+sans".
- Keep cross-direction constants constant — same real content, real labels, real states everywhere, so the comparison is honest.
- Close by handing control back: "your call — say the word and I'll push one further"; "none of these? tell me which axis to re-read." A picked direction becomes a normal task — same consent, same placement rules.
- Attribute honestly: "the host agent drew these" (or the real client name) — never self-credit.

## Voice reminders
voice.md is binding: draft framing ("a pass at B", "draft directions"), options with tradeoffs, node ids and token names as evidence for any claim about the original, explicit pushback invitation, no quality self-praise. When the brief is narrow, offer fewer directions and say why.
