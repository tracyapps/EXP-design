# EXP [design] v2.9

Development draft — not a published release. Baseline: **2.9 / build 20**.

Opened November 9, 2026 after the owner confirmed the successful v2.7→v2.8
installed update. The selected next-release focus is Design Language: color
modes and named spacing tokens, starting with automatic spacing and element
margin/padding. Selecting a spacing token links the field to its value; later
token edits update linked uses, while committing a different number detaches
that field and restores the selector to None/default.

These are planned capabilities, not implemented release features. Scope and
interaction brief: `docs/DESIGN-LANGUAGE-v2.9.md`. Public v2.8/build 19, its
release tag, ZIP, notes and updater item remain unchanged. Only verified shipping
behavior belongs in the final public notes.
