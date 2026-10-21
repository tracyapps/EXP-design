# EXP [design] website

A small React + Vite prototype for the public home of EXP [design].

## Run it

```bash
npm install
npm run dev
```

## Content model

The roadmap/progress/backlog areas are generated from the repo docs before each
dev/build run:

```bash
npm run sync
```

See `DEPLOYMENT.md` for the Vercel setup.

## Design sources

- `src/design-system.css` and `src/tokens/` are copied from the EXP design system.
- `public/assets/exp-canvas-workbench.png` is the current product screenshot.
- `public/assets/sanaa-critique-report.png` and `sanaa-ask-menu.png` show the
  v2.4 Sanaa critique and canvas entry points.
- `docs/exp-website-concept.png` is the generated visual concept used as the
  first implementation reference.
- `docs/FEATURE-ASSET-BRIEFS.md` describes the component, import/handoff, and
  Design Language images planned for the v2.1 homepage refresh. CSS concept
  visuals keep those sections complete until the final graphics replace them.

## Sharing kit: edit the words in one place

Edit **`content/share-kit.html`** for `/share`: intro, downloadable assets,
copyable snippets, and the “Say this / Not this / Because…” table. It is ordinary
HTML, with comments showing how to add a snippet/button. Keep IDs unique and
match each button's `data-copy-target` to its paragraph's ID. React/JavaScript
edits are unnecessary. Text is trusted build-time content, not member HTML.

Run `npm run dev` to preview `/share`, then `npm run build` before deploying.
While the dev server is already running, run `npm run sync` after content edits.
The sync step wraps that content in `public/share.html`; edit the content source,
not that generated page. All words, downloads and navigation work without JS;
copy buttons enhance the page when scripts work. Copy failures select the text.
`public/share/share.css` controls this page's styling; `public/share/share.js`
contains the copy enhancement.

`npm run sync` also rebuilds the wide 1200×630 and square 1080×1080 PNGs from the
real canvas screenshot and updates crawler-readable Open Graph/Twitter metadata
in `index.html`. Artwork/layout lives in `scripts/build-share-kit.mjs`. It uses
the repository's pinned Sharp dependency, so install the root dependencies too
(`npm ci` at the repository root), as production already does. Share graphics
and generated HTML are checked in for direct review. No image service or tracking
is involved. Real social-network cache refreshes need checking after deployment.

Public profile photos need additive migration `012_community_photos.sql` in the
existing account database. Existing runtime table grants cover the new columns;
there are no new provider credentials. Before migration the photo choices stay
unavailable, text profiles keep working, and private photos are never public.
See `docs/launch/SHARING-AND-PUBLIC-PHOTOS-v2.8.md` at the repository root.
