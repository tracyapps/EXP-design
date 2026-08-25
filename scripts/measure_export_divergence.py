#!/usr/bin/env python3
"""Measure whether an export's difference from the canvas is a COLOUR transform
or a SPATIAL redistribution of light. BUG-053.

Why this exists: "the export looks wrong" has two very different causes that look
similar to the eye — a colour-space/gamma mismatch (every pixel of a given value
maps to the same new value) versus a blur radius that changed (light moves from
the periphery into the core, and the mapping depends on WHERE a pixel is, not what
value it had). This script discriminates between them in one run.

Usage:
    python3 measure_bloom_profile.py design.png export.png [centre_u centre_v]

`design.png` and `export.png` should be the same artboard. They are resampled to a
common size, so different capture scales are fine. centre_u/centre_v (0..1) locate
the brightest bloom; default is the image centre.

Reading the output:
  - Large scatter in the "same design value -> export value" bins means the
    difference is NOT a global colour transform.
  - A radial ratio well above 1 near the centre that crosses below 1 further out
    means light was CONCENTRATED — the effective blur radius shrank. The crossover
    radius over the original radius approximates the factor it shrank by.

Requires: pillow, numpy.
"""
import sys
import numpy as np
from PIL import Image

N = 240


def load(path):
    return np.array(Image.open(path).convert("RGB").resize((N, N), Image.LANCZOS)).astype(float)


def luminance(x):
    return 0.2126 * x[..., 0] + 0.7152 * x[..., 1] + 0.0722 * x[..., 2]


def colour_transform_test(d, e):
    print("Is a single global per-channel transform enough to explain it?")
    print("(small +/- means yes -> suspect colour space or gamma;")
    print(" large +/- means no  -> suspect compositing or blur radius)\n")
    for ch, name in enumerate("RGB"):
        x, y = d[..., ch].ravel(), e[..., ch].ravel()
        bins = np.linspace(x.min(), x.max(), 9)
        idx = np.digitize(x, bins)
        print(f"  {name}:")
        for b in range(1, 9):
            m = idx == b
            if m.sum() < 32:
                continue
            print(f"    design~{x[m].mean():6.1f} -> export {y[m].mean():6.1f} "
                  f"+/- {y[m].std():5.1f}  (n={m.sum()})")
        print()


def radial_test(d, e, cu, cv):
    ld, le = luminance(d), luminance(e)
    print(f"mean luminance   design {ld.mean():6.2f}   export {le.mean():6.2f}")
    print(f"std  luminance   design {ld.std():6.2f}   export {le.std():6.2f}   (contrast)")
    print(f"p99 luminance    design {np.percentile(ld, 99):6.2f}   export {np.percentile(le, 99):6.2f}")
    print(f"p10 luminance    design {np.percentile(ld, 10):6.2f}   export {np.percentile(le, 10):6.2f}\n")

    cy, cx = cv * N, cu * N
    yy, xx = np.mgrid[0:N, 0:N]
    r = np.hypot(yy - cy, xx - cx)
    print(" radius   design-lum   export-lum   ratio")
    crossover = None
    for lo in range(0, int(N * 0.7), 15):
        m = (r >= lo) & (r < lo + 15)
        if m.sum() == 0:
            continue
        a, b = ld[m].mean(), le[m].mean()
        ratio = b / max(a, 0.01)
        if crossover is None and ratio < 1.0 and lo > 0:
            crossover = lo
        print(f"  {lo:3d}-{lo + 15:3d}   {a:8.2f}   {b:8.2f}   {ratio:6.2f}")
    if crossover:
        print(f"\ncrossover near radius {crossover}px of {N} — beyond this the export is DARKER,")
        print("inside it the export is BRIGHTER: light was concentrated, not recoloured.")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    d, e = load(sys.argv[1]), load(sys.argv[2])
    cu = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
    cv = float(sys.argv[4]) if len(sys.argv) > 4 else 0.5
    colour_transform_test(d, e)
    radial_test(d, e, cu, cv)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
