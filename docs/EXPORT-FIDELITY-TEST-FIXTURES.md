# Export fidelity test fixtures — BUG-053 and BUG-054

**You are here because export doesn't match the canvas.** This file is
self-contained on purpose: you should not have to re-read the investigation, the
backlog, or the Progress Log to run these. Build the fixtures, export, compare
against the tables. Nothing here needs a code change first.

Written 2026-08-25, when the bugs were diagnosed but deliberately not fixed.

---

## The 30-second refresher

Two separate defects were found while diagnosing a layered light-leak graphic
whose PNG export looked nothing like the canvas.

- **BUG-053 (P1, the one you actually hit).** PNG, JPG, and PDF export never draw
  the `noise` or `dissolve` effects. The canvas draws them and SVG export draws
  them; the raster exporter is the only one that doesn't. It fails silently — no
  warning, no placeholder, the effect is simply absent.
- **BUG-054 (P2, found while looking, no confirmed symptom).** Blur radii get
  clamped at 200 in *device* space, and the canvas multiplies by zoom while export
  multiplies by 1. So what a blur looks like can depend on the zoom you happened to
  be at when you authored it.

Neither is fixed. **These fixtures exist to prove or disprove both readings before
anyone writes code.** If a prediction below fails, the diagnosis is wrong — write
down what actually happened rather than adjusting the theory to fit it.

Total build time: about 30 minutes. Fixture A alone (15 min) settles the bug you
reported; Fixture B is optional and can wait.

---

## Fixture A — does raster export drop `noise` and `dissolve`? (~15 min)

### Build

1. New document. One artboard named **`FX-A`**, **900 × 300**.
2. Artboard background: solid **`#202020`**. (Mid-dark — a Color Dodge needs
   something to lift, and pure black dodges to nothing.)
3. Three rectangles, each **240 × 200**, all at **y = 50**, at **x = 40 / 330 / 620**.
   Give all three the **same** fill: solid **`#3355AA`**, 100% layer opacity, no
   stroke. Name them so the export is readable:

   | Name | Effects to add |
   |---|---|
   | `A1-plain` | none |
   | `A2-noise-dodge` | **Noise** — amount `0.6`, blend **Color Dodge**, leave turbulence settings at their defaults |
   | `A3-dissolve` | **Dissolve** — amount `0.5` |

4. Set canvas zoom to **100%** and take a screenshot of the artboard. That
   screenshot is the reference — the canvas is what the export is supposed to match.

### Export

- **PNG at 1×**
- **SVG**

### Compare

| Layer | Canvas (reference) | SVG export | PNG export |
|---|---|---|---|
| `A1-plain` | flat blue | same as canvas | same as canvas |
| `A2-noise-dodge` | grainy, visibly lifted | grainy, lifted | **predicted: flat blue, no grain at all** |
| `A3-dissolve` | speckled / eaten away | speckled / eaten away | **predicted: solid, untouched rectangle** |

**If both predictions hold** → BUG-053 confirmed. The fix is to give the raster
exporter `noise` and `dissolve`, in the canvas's order (dissolve first, so shadows
see the dissolved node — the order `svgFilter` already documents).

**If the PNG shows grain and dissolve** → the diagnosis is wrong. Record that in
BACKLOG under BUG-053 and stop; the real cause is still open.

**If SVG is also wrong** → different bug again; note which of the two is wrong and
how.

### While you're here — the mystery dark rectangle

Your original file had a hard-edged dark rectangle matching no layer you could
find. The prediction is that it's `A3` behaviour in the wild: **a layer whose
`dissolve` should eat most of its pixels, rendering as the solid shape underneath.**

- Open the original file and look for a node with a `dissolve` or `noise` effect
  positioned near the box. That's your rectangle.
- If there is no such node, the fallback suspect is the preserve-transparency drop
  shadow knockout (it uses a compositing mode PDF can't represent, and its knockout
  shape is filled opaque black). You already disabled one without the artifact
  clearing — the real test is to disable **every** preserve-transparency drop shadow
  in the document at once, then re-export.

---

## Fixture B — are blur radii zoom- and clamp-dependent? (~15 min, optional)

Only worth building if you want BUG-054 settled too. It is not the bug you hit.

### Build

1. One artboard named **`FX-B`**, **1800 × 900**, background solid **`#101010`**.
2. **Row 1 — layer blur.** Four rectangles, **200 × 200**, at **y = 120**, at
   **x = 100 / 500 / 900 / 1300**. Fill solid **white**, **20%** layer opacity.
   Add a **Layer Blur** to each: **50 / 150 / 250 / 400** points respectively.
   Name them `B1-blur50`, `B1-blur150`, `B1-blur250`, `B1-blur400`.
3. **Row 2 — drop shadow.** Four rectangles, **200 × 200**, at **y = 560**, same
   x positions. Fill solid **white**, 100% opacity. Add a **Drop Shadow** to each:
   offset `0,0`, colour white, **blur 50 / 150 / 250 / 400** points respectively.
   Name them `B2-shadow50` … `B2-shadow400`.

### Export and capture

Do all of these — the point is the comparison between them, not any single one:

- Canvas at **100%** zoom → screenshot, and export **PNG 1×**
- Canvas at **25%** zoom → screenshot, and export **PNG 1×**
- Canvas at **200%** zoom → screenshot, and export **PNG 1×**
- From 100% zoom, also export **PNG 2×** and **PNG 3×**

Name the files so you can tell them apart later (`FX-B-zoom100-1x.png`, etc.).

### Compare

| Check | Prediction if the BUG-054 reading is right |
|---|---|
| `B1-blur250` vs `B1-blur400` in any PNG | **identical** — both clamped to 200 |
| `B2-shadow250` vs `B2-shadow400` in any PNG | **identical** — same clamp |
| The three PNGs exported at different canvas zooms | **identical to each other** — export ignores zoom |
| The three canvas screenshots, normalised for scale | **not** consistent with each other — the canvas result changes with zoom |
| Canvas at 100% vs PNG 1× | should match; anywhere they don't is the divergence |
| PNG 1× vs 2× vs 3× | same picture at different resolutions, no change in blur *radius* relative to the artboard |

To quantify any pair instead of eyeballing:

```sh
python3 scripts/measure_export_divergence.py canvas-screenshot.png export.png
```

It reports whether a difference is a colour transform or a spatial one, and prints
a radial luminance profile. (Requires `pillow` and `numpy`.)

---

## Recording what you find

Put the results in `docs/BACKLOG.md` under BUG-053 / BUG-054 as an
`Owner verification <date>:` line, in the same style as the other entries.

Two things worth stating explicitly whichever way it goes:

- **A failed prediction is a good result.** It means the reading is wrong and the
  cause is still open — that's more useful than a theory that survived because
  nobody tested it.
- **Note anything you did NOT check.** These fixtures cover raster vs SVG for four
  effect kinds. They do not cover `backgroundBlur` (disabled everywhere), stacked
  effects on one layer, effects inside groups or component instances, or effects
  combined with a non-normal layer blend mode. Those are all plausible additional
  divergences and none of them are tested here.
