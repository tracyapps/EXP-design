# Component library round-trip fixtures

Test material for EXP's component & token sync (FEAT-082 to FEAT-087). The same
three components are written the way seven kinds of component library ship them.
Each format has two copies:

- **working/**: point EXP at this one. Import, edit, send changes back.
- **control/**: never edited. The reference that proves nothing was lost.

`compare.html` shows both copies of one component side by side, running live,
with the source files underneath and every differing line marked.

## Use it

Needs Node 20 or newer. No install step for the page itself.

```sh
cd "spike/component-libraries"
npm run serve                 # then open http://127.0.0.1:4173/
npm run verify                # same check on the command line (exit 1 if anything differs)
npm run reset -- react        # restore one working copy from its control
npm run reset -- --all        # restore all of them
npm run rebuild -- react      # rebuild a working copy after markup/logic changes
```

The page must be opened through `npm run serve`, not by double-clicking the HTML
file: browsers block a local file from reading other local files.

**CSS and token edits show up immediately** because every format loads its styles
from plain files in `styles/`. Markup or logic changes in a format with a build
step need `npm run rebuild -- <format>`; the page says when a working build is
older than its source. Rebuilding Angular needs Node 22.22.3+ or 24.15+.

## A round-trip test

1. `npm run serve`, open the page, pick a format and component. Both columns match.
2. In EXP, import from `formats/<format>/working` (tokens today: File ▸ Import
   Library Tokens…).
3. Make a change in EXP and send it back to the working copy (FEAT-084 onward).
4. Refresh the page (or tick **Refresh when files change**). Intended changes are
   marked `+` in the working column and `−` in the control column. Anything else
   that changed (or disappeared) is a bug. **Every format** at the bottom checks
   every file, not only the ones shown.
5. `npm run reset -- <format>` to start over.

## Components

| Component | Complexity | What it exercises |
| --- | --- | --- |
| Button | Simple | Variants (appearance × size), disabled, label as slot/children |
| Card | Composite | Contains Button child components; optional parts; tone variant; heading level |
| Accordion | Complex | Parent + AccordionItem children, open state, single vs multiple open |

The accordion follows the WAI-ARIA APG accordion pattern: a `button` inside a
heading with `aria-expanded` and `aria-controls`, panels with `role="region"`
labelled by their button (under the APG's ~6-panel guidance). Checked against
https://www.w3.org/WAI/ARIA/apg/patterns/accordion/ on 2026-10-24. Automated
browser checks cover the roles, relationships and Enter-key toggling in every
format. **Not verified:** VoiceOver or any other screen reader.

## Formats

| Folder | What it is | Build | What EXP can import today |
| --- | --- | --- | --- |
| `html-css` | Static pattern library: HTML snippets, BEM classes, one enhancement script | none | Rendered HTML/CSS import; tokens |
| `web-components` | Vanilla custom elements, shadow DOM, parts, `custom-elements.json` | none | Tokens; FEAT-083 reads the manifest |
| `lit` | Lit 3 in TypeScript, esbuild bundle, `custom-elements.json` | esbuild | Tokens; FEAT-083 reads the manifest |
| `react` | React 19 TSX + CSF3 stories | esbuild | Tokens; components need FEAT-087 |
| `vue` | Vue 3.5 SFCs (`<script setup lang="ts">`) | Vite | Tokens; components need FEAT-087 |
| `svelte` | Svelte 5 runes + TypeScript | Vite | Tokens; components need FEAT-087 |
| `angular` | Angular 22 standalone components, signal inputs | Angular CLI | Tokens; components need FEAT-087 |

All formats share the same class names, `styles/*.css` and `styles/tokens.css`
(light/dark modes, aliases, and one `color-mix()` expression EXP must preserve).
Web Components and Lit link their stylesheet inside each shadow root, so the CSS
stays an editable file.

Framework builds produce two files where it matters: `dist/index.js` (the library
build, framework as a peer dependency) and `dist/preview.js` (framework bundled,
used only by this page through a small `mount()` adapter in `src/preview.*`).
Angular's preview build registers `globalThis.expFixture.mount`.

## How "nothing lost" is checked

- `control.sha256.json` records every control file. The page and `npm run verify`
  warn if a control copy ever changes.
- Working vs control is compared file by file (`node_modules` ignored). Files EXP
  adds, such as `.expsync/`, are listed as **added**, never hidden.
- Code is shown with a line diff; markers are symbols plus hidden text for screen
  readers, not color alone.

## Known limits

- Stories are source only. Storybook isn't installed, so there are no static
  Storybook builds yet (needed for FEAT-087 testing; can be added).
- The Svelte preview wraps a button label in a `<span>` (a limit of passing text
  as a snippet from outside Svelte). The HTML/CSS format shows its snippets as
  written rather than the shared demo list.
- After `npm run snapshot-control`, the current control files become the new
  reference. Run it only when the fixtures themselves are deliberately changed.
