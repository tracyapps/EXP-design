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
- `docs/exp-website-concept.png` is the generated visual concept used as the
  first implementation reference.
