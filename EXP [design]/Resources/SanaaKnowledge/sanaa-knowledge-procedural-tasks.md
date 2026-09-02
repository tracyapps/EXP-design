---
name: procedural-tasks
version: 1.0.0
updated: 2026-08-31
---

## TL;DR
Repetitive work — "add more rows", "fill it in", more cards, chips, list items — runs as measure → derive → replicate: read the exemplar, copy geometry and styles verbatim, derive positions with short arithmetic, generate coherent fictional data per column type. Every batch is one consented apply_edits unit.
Load when: the designer asks to extend, fill, or repeat an existing pattern (tables, card lists, form groups, chips, avatar stacks, pagination) or asks for placeholder data.

## Measure → derive → replicate
- IF the ask is repetitive work THEN read the exemplar with get_node / get_artboard before proposing. Copy row height, per-side paddings, gaps, text styles, fills VERBATIM from the document — never from memory, never eyeballed from a screenshot. Tradeoff: one read round-trip first; skipping it produces near-miss geometry that costs more to fix than the read saved.
- IF new positions are needed THEN derive them by short explicit arithmetic on the document's own steps (y = last row y + row height + gap) and state the derived numbers in the reply. Keep magnitudes small — delta arithmetic on the file's own steps, not long absolute coordinate chains. Tradeoff: two lines of visible arithmetic; in exchange every number is checkable at a glance.
- IF the exemplar carries autoLayout (gap, padding) THEN clone it with that structure intact so the app holds the geometry; hand-set absolute positions only when the exemplar itself is hand-placed. Tradeoff: the structure wrapper costs one extra node id; absolute placement breaks on the designer's next edit.

## Column semantics
- IF the pattern is a table THEN classify every column from header text (if the table has one) PLUS patterns in existing cells: name / email / phone / address / price / date / status / id / quantity / avatar / flag / free text. When header and values disagree, the values win — say which you trusted. Tradeoff: header-only classification is faster and occasionally wrong.
- IF a column type is settled THEN generate as one system: ONE locale per table — names, addresses, phones, prices, dates all coherent; identity fields unique and format-valid (emails with plausible domains, ids in the observed pattern); prices and dates in the column's existing format and currency; a deliberate mix of short and long values so the layout gets stressed; any existing ordering or grouping preserved. Tradeoff: long values may overflow — that is the point of stress values; name the rows that carry them.
- IF real content exists anywhere in the file THEN no lorem ipsum — realistic-but-fictional data only (invented people, invented places). Lorem ipsum only on a literally empty board, and say so. Tradeoff: fictional data reads finished; label it placeholder in the reply so it never ships. This is the specific carve-out from anti-generic's subject-grounding rule: composed directions use the designer's real content; pattern fills use labeled fiction.

## Beyond tables
- IF the pattern is repeated cards, list rows, form field groups, chip/tag rows, avatar stacks, or pagination THEN the same discipline applies. Name three things in the reply: the exemplar (node id), the repetition rule ("vertical stack, gap 12"), and the content deltas per copy. The app holds the geometry. Tradeoff: naming the rule costs a sentence; it also makes the batch auditable and re-runnable.
- IF the exemplar is a component instance THEN instance internals are unreachable for writes — extend at the source component or with plain nodes, and say which you touched. Instance semantics and states: components-states.

## Batch & placement
- IF the work extends EXISTING content THEN in-place insert/replace only with consent (per-document, once per session); IF the designer wants variants or duplicates THEN they choose in place or beside. Tradeoff: in place keeps the table one object; a duplicate beside keeps the original intact for comparison.
- IF building a batch THEN one apply_edits call per undoable unit, summary ≤120 chars and honest ("8 user rows, 56pt step", not "table fixes"). IF the batch would exceed the op cap THEN split into labeled batches and say so before continuing ("batch 1 of 2: rows 3–7"). Tradeoff: splitting spends several undo steps; one oversized batch is refused whole.
- IF building insertNodes fragments THEN copy real design.json shapes from get_node output; replaceNode keeps ids. Invented shapes are refused at decode. Tradeoff: verbatim fragments are verbose; refusals burn a round trip.
- Nothing here creates a write path beyond a consented apply_edits batch.

## Honesty
- State what was copied vs derived: "heights, paddings, text runs: copied from row R-7; positions and content: derived." Offer "select Sanaa's changes" after applying so the designer can review the batch in one gesture.
- The document has NO spacing tokens — spacing comes from measured paddings, gaps, and sibling deltas; state the measured values you copied. Rhythm and grid judgments: spacing-layout (descriptive evidence only — the grid call stays the designer's).

## Ambiguity
- IF the pattern's continuation is ambiguous (ordering, grouping, count) THEN ask ONE concrete question with two labeled options ("8 more rows — chronological or alphabetical?") or state the assumption and proceed. Tradeoff: proceeding keeps momentum on filler data; a wrong guess on ordering costs one re-run batch.

## Worked example — "add 8 more rows"
Designer drew a Users table: header H-3, rows R-7 and R-8 — columns Name, Email, Role, Joined.
Measure: get_node R-7 → height 56, padding 16L/12TB, text runs 14/20, row fill; rows sit in a vertical autoLayout, gap 0; R-8 spans y 252–308. Existing values: English-style names, roles among Admin/Editor/Viewer, dates MM/DD/YY → one locale.
Derive: predicted landing y = 308 + 56k → 308, 364, 420, 476, 532, 588, 644, 700 (the stack's autoLayout holds final geometry — insert into the stack; never hand-set y on its children). Content: unique fictional names; unique first.last@plausible-domain emails; roles sampled from the existing three; dates MM/DD/YY, roughly chronological; table rows 6 and 9 carry long names to stress the Name column.
Replicate: clone R-7's fragment verbatim per row; replace cell text only. Reply shape:

"Draft 8 rows at y 308→700, step 56 (56 row + 0 gap, measured R-7/R-8). Copied from R-7: height, paddings, text 14/20, fill. Derived: positions and content — one locale, unique emails, roles from Admin/Editor/Viewer, dates MM/DD/YY; rows 6 and 9 stress the Name column with long names. The host agent drew these; one undo step. Options: (a) in place — needs your once-per-session consent for this board; (b) duplicate beside as 'Users — extended' to compare first. 'Select Sanaa's changes' reviews the batch after. Swap any column's pattern — say which."

## Why these rules (provenance)
- Realistic placeholder data beats lorem ipsum for engaging designs: https://www.nngroup.com/articles/users-real-data/
- One locale per fake-data instance keeps all fields coherent: https://fakerjs.dev/guide/localization
- LLM arithmetic drifts as magnitudes grow — derive from provided numbers, keep them small: https://arxiv.org/html/2502.08680v1
