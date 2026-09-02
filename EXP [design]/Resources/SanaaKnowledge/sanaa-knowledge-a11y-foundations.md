---
name: a11y-foundations
version: 1.0.0
updated: 2026-08-29
---

## TL;DR
The accessibility standards map, what a design file can and cannot settle, and the claim language Sanaa uses.
Load when: critiquing, fixing, or discussing accessibility, compliance, 508 / ADA / WCAG.
Facts verified 2026-08-29 against primary sources (URLs inline). Re-verify before any standard or deadline reaches product copy.

## The standards map (which law references which technical standard)
- **Section 508** (US federal ICT): incorporates **WCAG 2.0 Level AA** by reference; no refresh exists as of Aug 2026. §504 also covers authoring tools. https://www.section508.gov/develop/applicability-conformance/
- **DOJ ADA Title II web rule** (state/local governments): technical standard **WCAG 2.1 Level AA** — https://www.ada.gov/resources/2024-03-08-web-rule/ . The April 2026 interim final rule extended compliance deadlines: entities ≥50,000 population → **April 26, 2027**; <50,000 and special district governments → **April 26, 2028** — https://www.federalregister.gov/documents/2026/04/20/2026-07663/ ; https://www.ecfr.gov/current/title-28/chapter-I/part-35/subpart-D/section-35.200 . Deadlines are entity-scoped (governments, not private companies) and rulemaking was active at the verification date — re-verify before citing.
- **ADA Title III** (private sector): **no binding web technical standard** — WCAG targets are risk-driven. https://www.ada.gov/resources/web-guidance/
- **WCAG versions**: **2.2 is the current W3C Recommendation** (Oct 2023, updated Dec 2024); 2.2 does not deprecate 2.1; 4.1.1 Parsing is obsoleted in 2.2 — do not cite it. https://www.w3.org/WAI/standards-guidelines/wcag/ . WCAG 3 is a Working Draft (Mar 2026) with the contrast algorithm undetermined (https://www.w3.org/TR/wcag-3.0/) — never a conformance target.
- **EN 301 549** (EU): **v3.2.1** is the harmonised version (incorporates WCAG 2.1); a 2.2-aligned revision is in development but not harmonised. https://digital-strategy.ec.europa.eu/en/policies/latest-changes-accessibility-standard . The **European Accessibility Act applies from 28 June 2025** (Directive (EU) 2019/882). https://eur-lex.europa.eu/eli/dir/2019/882/oj/eng
- **WAI-ARIA 1.2** is a W3C spec used WITH WCAG (https://www.w3.org/TR/wai-aria-1.2/) — no law "specifies ARIA". Phrase semantics guidance against ARIA + the APG; phrase conformance against WCAG.

## Claim language (binding; full pattern list in voice.md)
- Criteria-level only: "4.53:1 vs 4.5:1 per SC 1.4.3, this pair" — never "ADA compliant", "508 compliant", "accessible now", or unscoped "meets WCAG".
- Name the regulated entity when deadlines come up: Title II deadlines apply to state/local governments, not private companies.
- Version discipline: US legal baselines are WCAG 2.1 AA (Title II) and WCAG 2.0 AA (508). Designing to 2.2 AA is good practice (backward-compatible) — say which version a statement is about.

## Design-stage checks (computable from the file — get_design_facts measures these)
- **Text contrast on solid fills — SC 1.4.3**: 4.5:1; 3:1 for large text (≥18pt regular / ≥14pt bold ≈ 24px / ≈18.67px). Thresholds are read as ≥, never rounded down. https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html — AAA **SC 1.4.6**: 7:1 / 4.5:1.
- **Non-text contrast — SC 1.4.11**: 3:1 against adjacent colors for component boundaries/states and graphics that carry meaning. https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html
- **Pointer targets — SC 2.5.8**: ≥24×24 CSS px (≈ points at 1x), five exceptions: spacing / equivalent / inline / essential / user-agent control. https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html — AAA reference **SC 2.5.5**: 44×44.
- **Focus indicator geometry — SC 2.4.13** (AAA): ≥2 CSS px perimeter area, ≥3:1 change between states. https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance.html — sticky-header occlusion → **SC 2.4.11** (AA).
- **Text-spacing stress — SC 1.4.12**: no content loss at 1.5× line height, 2× paragraph spacing, 0.12× letter spacing, 0.16× word spacing. https://www.w3.org/WAI/WCAG22/Understanding/text-spacing.html
- **Dragging alternatives — SC 2.5.7**; **redundant entry — SC 3.3.7**.
Sanaa states measured values, never verdicts: numbers + citations; exceptions and intent are the designer's call.

## Judgment-required (never automate a verdict)
- Alt-text quality (**1.1.1**); reading-order meaningfulness (**1.3.2**, **2.4.3**); descriptive labels and link purpose (**2.4.4**, **2.4.6**); error-message quality (**3.3.1–3.3.3**).
- Exception adjudication ("essential", "inline", incidental text, logotypes) — flag as possible, don't auto-exempt.
- Cognitive load and clarity of instructions.

## Edge cases (report "couldn't assess" — never estimate silently)
- **Alpha/transparency**: WCAG defines no blending method — a flattened ratio is an estimate and must be labeled with its base (get_design_facts does this).
- **Gradients / background images / images of text**: "test the area where contrast is lowest" is guidance, not a measurement; anti-aliasing degrades large-text image edges. https://webaim.org/articles/contrast/ ; https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
- **APCA**: not in WCAG 2.x, not a conformance metric; WCAG 3's algorithm is undetermined. https://www.w3.org/TR/wcag-3.0/ — advisory signal at most, always labeled as such.
- Automated checkers can't see intent (incidental vs meaningful, decorative vs informative) — that judgment stays with the designer.

## Coverage honesty
Design-stage/automated checks catch a subset of issues: ~30% (UK GDS Way), ~40% (DWP manual), up to ~57% in Deque's vendor study.
https://gds-way.digital.cabinet-office.gov.uk/manuals/accessibility.html · https://accessibility-manual.dwp.gov.uk/best-practice/how-to-do-accessibility-testing · https://www.deque.com/automated-accessibility-coverage-report/
Any "clean" report carries this caveat plus the design-stage/implementation-stage split: color, size, and spacing live in the canvas; keyboard behavior, focus order/visibility, and ARIA semantics live in the Handoff export (docs/SEMANTIC-HTML-CONTRACT.md).
