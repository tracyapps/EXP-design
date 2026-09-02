---
name: a11y-applied
version: 1.0.0
updated: 2026-08-31
---

## TL;DR
Applied accessibility workflows for concrete nodes: contrast answers, target sizes, ARIA role choices, doc citations, and honest design-stage limits. Thresholds, standards, deadlines, and claim language live in a11y-foundations — this file is the how.
Load when: answering "is this readable / big enough / what role", drawing new components, or reviewing states before handoff.

Standards facts in this module were re-verified 2026-08-31 against the official
WCAG 2.2 Understanding documents and WAI-ARIA Authoring Practices Guide.

## Contrast workflow
- IF `get_design_facts` is available, RUN IT FIRST (`colorPairs`, `nonTextContrast`) and quote its numbers with node ids. Tradeoff: gathering measured pairs is slower than eyeballing, but a quoted number is checkable and a guess is not.
- UNTIL it ships, GROUND every ratio in the app's contrast checker or an explicit document read (`get_node` fills). NEVER estimate a ratio in prose (color.md rule) — say "I can't assess that pair" instead.
- WHEN reporting, USE the scoped pattern only: "<measured>:1 vs <threshold>:1 per SC x.y.z, this pair" + node id. Never "passes/fails". Thresholds and large-text cutoffs live in a11y-foundations.
- INTERPRET against the right criterion: text pairs → SC 1.4.3; component boundaries, icons, state indicators → SC 1.4.11 at 3:1.
- IF the text sits on a gradient, image, or alpha-stacked fill, SAY "couldn't assess" with the reason (WCAG defines no blending method; a flattened ratio is an estimate). Offer one settlement path: duplicate the artboard, flatten, test the lowest-contrast area. Tradeoff: honest blind spots cost a beat now; silent ones read as false completeness later.
- EVERY fix proposal presents BOTH alternatives, each with a one-line tradeoff: (a) the computed hue/chroma-preserving adjusted value — keeps the palette's character, but is a one-off until tokenized; (b) the nearest existing token — stays on-system, but may shift the hue. Suggested fills respect the document palette — never arbitrary hex.
- IF the failing value IS a widely-used token, PROPOSE "fix the token, not the instance" (edit the Design Language value). Tradeoff: one edit updates every use — and shifts every use, which the designer must want.
- IF large-text classification decides the threshold, LABEL the fontName bold call a heuristic and ask the designer to confirm actual weight and size. Tradeoff: one confirming question beats a wrong threshold silently applied.
- PROPOSE on a duplicate artboard or as draft values first; canvas changes go through consent, never unprompted.

## Target-size workflow
- REPORT measured sizes with node ids ("node 7F3 is 20×20pt — under the 24×24 reference in SC 2.5.8"), never "too small".
- VERSION-SCOPE every size statement: "≥24×24 CSS px supports SC 2.5.8 (WCAG 2.2 AA)"; "≥44×44 meets SC 2.5.5 (AAA)". Don't blur the two numbers.
- IF a target measures under 24×24, NAME the five SC 2.5.8 exceptions that could apply — spacing / equivalent / inline / essential / user-agent control — and flag; adjudication is the designer's call. Tradeoff: exceptions are real, but auto-exempting hides fixable targets.
- IF the fix is geometry, OFFER two options: grow the control, or keep the visual
  size and satisfy the spacing exception — 24 CSS px diameter circles centered
  on each undersized target's bounding box must not intersect another target or
  another undersized target's circle. Tradeoff: the spacing exception is fragile
  — one layout shift can invalidate it; growing costs density.

## ARIA role decision table
- FIRST RULE: prefer native semantics — no ARIA is better than bad ARIA. IF a plain element matches, label nothing.
- IF asked "what role", PICK by what the element does, then check name/role/value (SC 4.1.2): accessible name, role, states.

| If it… | Role(s) | Decision edge |
|---|---|---|
| performs an in-place action | button | navigates instead? → link |
| navigates to another resource or view | link | styled as a pill? still link |
| switches panels inside a view | tablist / tab / tabpanel | each tab controls and labels its associated panel |
| interrupts with urgent info and requires a response | alertdialog | other modal or non-modal dialogs → dialog |
| lists commands to trigger | menu / menubar / menuitem | app commands, not page navigation |
| picks one or more from a list | listbox / option | selection, not commands |
| is an input with a popup list | combobox | input + popup is one pattern |
| displays static data | table | interactive cells → grid |
| flips a setting instantly | switch | applied on submit → checkbox |
| marks a page region | banner / main / navigation / contentinfo | top-level; one main |

- IF the element is not actually interactive, DO NOT attach a control role. A button label on a static node exports a promise the implementation must honor. Tradeoff: correct labeling costs a moment; mislabeled roles propagate silently into the Handoff export.
- IN REVIEW, WARN on the classic misuses: control roles on non-interactive elements; aria-hidden over focusable content; positive tabindex.

## Doc linking
- ANSWER role questions with the decision rule + role name first; THEN cite the hub: EXP ARIA Roles Guide, https://expdesign.app/aria-roles/
- REFERENCE role pages BY TITLE ("the combobox role page in the EXP ARIA Roles Guide"). DO NOT construct deep-link URLs — subpage slugs are unconfirmed; a wrong link is worse than a title.
- IF the designer needs canonical pattern semantics or keyboard behavior, POINT to the ARIA Authoring Practices Guide patterns (w3.org/WAI/ARIA/apg). Tradeoff: the EXP guide is plain-language and product-specific; the APG is canonical but denser.

## Drawing & reviewing
- WHEN drawing new components, ATTACH the correct role by default — the app's components carry ARIA roles. An unlabeled interactive component exports as noise.
- DESIGN real states into the file: hover / focus / active / disabled / error / empty / loading (state kit in components-states). Tradeoff: extra frames now versus states improvised in code later.
- DESIGN the focus treatment in the canvas — focus geometry belongs to the
  design, not just CSS. For SC 2.4.13 (AAA), the indicator needs an area at
  least equivalent to a 2 CSS px perimeter and ≥3:1 same-pixel contrast between
  focused and unfocused states; it need not literally be a 2px outline. For SC
  2.4.11 (AA), author-created content must not entirely hide the focused
  component; fully unobscured focus is the stricter AAA criterion in SC 2.4.12.
  Tradeoff: visible focus can read heavy — that's taste, and it's the designer's
  call.

## Design-stage vs implementation-stage honesty
- CANVAS fixes cover what the file encodes: color, size, spacing, role labels, states.
- IF the ask is keyboard behavior, focus order, or export-time semantics, POINT to the Handoff export / SEMANTIC-HTML-CONTRACT — never claim a canvas edit fixes them.
- CARRY the coverage caveat on every "checks clean" statement: design-stage/automated checks catch roughly 30–40% of issues (UK GDS/DWP guidance), up to ~57% in the most favorable vendor study (Deque). Sources in a11y-foundations.
- FOR the judgment remainder, NAME one concrete manual check each: focus order → tab through a build; does it match visual order? meaningful sequence → read nodes in export order aloud; screen-reader UX → two minutes of VoiceOver on a build; alt-text quality → cover the image — can you still tell what it's for?

## Worked examples

### "Is this text ok on this fill?"
- "The label (node 2A1, 16px regular) on --surface-raised reads 3.9:1 vs 4.5:1 per SC 1.4.3, this pair."
- "Option A — recolor to the computed adjusted value (derived from the current color, hue/chroma preserved): keeps the palette's character; a one-off until tokenized. Option B — switch to --ink-secondary, the nearest token: stays on-system; slightly warmer. The failing color is --ink-tertiary, used on 14 nodes — if you want it fixed everywhere, fix the token, not the instance: one edit, but every card shifts."
- "The card's other measured pairs read at or above 4.5:1 per SC 1.4.3, these pairs — with the coverage caveat: design-stage checks catch roughly 30–40% of issues (UK GDS/DWP), up to ~57% (Deque)."
- "Swap any of these, or tell me what to re-read."

### "What role for this pill that opens a filter list?"
- Decision: action vs navigation vs selection vs input. "The pill triggers a popup for picking filters — a trigger plus a selection list."
- "Option A — label the pill button with an expanded state; the popup is listbox/option. Keeps the pill a plain trigger. Option B — if tapping the pill focuses a text input that filters as you type, label the pair combobox (input + popup is one pattern). Tradeoff: combobox is richer but heavier to build."
- "Either way the pill needs its accessible name (the visible label) and the expanded state — name/role/value per SC 4.1.2. Keyboard behavior lands in the Handoff export, not the canvas."
- "The button, listbox, and combobox pages in the EXP ARIA Roles Guide: https://expdesign.app/aria-roles/"
