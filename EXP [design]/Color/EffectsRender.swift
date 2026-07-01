//
//  EffectsRender.swift
//  EXP [design]
//
//  Core-Graphics rendering for node effects (drop + inner shadow). Shared by the
//  on-canvas drawing and the PNG/PDF export so a shadow looks identical in both.
//
//  Both shadows use CG's built-in `setShadow` (a Gaussian blur). The geometry
//  mirrors CSS `box-shadow`: offset (dx,dy), blur, spread, color.
//
//   • Drop shadow — stamp a "caster" (the shape's silhouette, or the node's own
//     painted content for text) into a transparency layer that has a CG shadow
//     set. The caller then draws the real node on top, leaving only the soft
//     shadow behind it.
//   • Inner shadow — clip to the shape, then fill the region *outside* an
//     (optionally spread) hole with a shadowed opaque fill; the hole's edge casts
//     the shadow inward. The opaque fill itself sits outside the clip, so only its
//     inward shadow shows.
//
//  `scale` converts model points → the context's space (zoom on canvas, 1 on
//  export), and is applied to offset/blur so a shadow tracks zoom correctly.
//

import AppKit
import CoreGraphics

/// The outline a shape casts a shadow from, plus spread-grown/shrunk variants.
/// Space-agnostic (the caller builds it in view or local coordinates).
struct Silhouette {
    enum Shape { case roundRect(radius: CGFloat); case oval; case custom(CGPath) }
    let rect: CGRect
    let shape: Shape

    /// The path grown (positive) or shrunk (negative) by `spread`. Arbitrary
    /// custom paths ignore spread (returned unchanged).
    func path(spread: CGFloat) -> CGPath {
        switch shape {
        case .roundRect(let r):
            let rr = rect.insetBy(dx: -spread, dy: -spread)
            let rad = max(0, r + spread)
            return CGPath(roundedRect: rr, cornerWidth: rad, cornerHeight: rad, transform: nil)
        case .oval:
            return CGPath(ellipseIn: rect.insetBy(dx: -spread, dy: -spread), transform: nil)
        case .custom(let p):
            return p
        }
    }
    var clip: CGPath { path(spread: 0) }
}

enum EffectsRender {

    /// Hard ceiling on a shadow's blur radius in DEVICE space (points × scale).
    /// `setShadow`'s cost (and the offscreen surface Core Graphics allocates for it)
    /// grows with the blur radius, and `blur = e.blur * zoom` is otherwise unbounded:
    /// at high zoom a normal shadow demands a multi-thousand-pixel gaussian, which
    /// triggers "Surface too large" and hangs the render thread in the convolution
    /// kernel. Past ~200px a gaussian is visually indistinguishable anyway, so we cap
    /// it — shadows look identical at sane zooms and simply stop melting at extreme ones.
    static let maxShadowBlurPx: CGFloat = 200

    /// Drop shadow. `caster` draws the silhouette (or content) that throws the
    /// shadow; it is covered by the real node afterward.
    static func drawDropShadow(_ e: Effect, scale: CGFloat, in ctx: CGContext, caster: () -> Void) {
        guard e.isEnabled, e.kind == .dropShadow else { return }
        ctx.saveGState()
        // Flipped (y-down) context: negate the height so +Y reads as *down*,
        // matching CSS `box-shadow` offset-y. (+X = right is already correct.)
        let blurPx = min(max(0, e.blur * scale), maxShadowBlurPx)
        ctx.setShadow(offset: CGSize(width: e.dx * scale, height: -e.dy * scale),
                      blur: blurPx,
                      color: PaintRender.nsColor(e.color).cgColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        caster()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Inner shadow inside `clip` (the shape). `hole` is `clip` shrunk by spread
    /// (pass `clip` again for no spread). Both paths are in the ctx's current space.
    static func drawInnerShadow(_ e: Effect, clip: CGPath, hole: CGPath, in ctx: CGContext, scale: CGFloat) {
        guard e.isEnabled, e.kind == .innerShadow else { return }
        let blurPx = min(max(0, e.blur * scale), maxShadowBlurPx)
        let pad = blurPx + (abs(e.dx) + abs(e.dy) + 4) * scale
        let box = clip.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad)
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        // Flipped (y-down) context: negate the height so +Y reads as *down*,
        // matching CSS `box-shadow` offset-y. (+X = right is already correct.)
        ctx.setShadow(offset: CGSize(width: e.dx * scale, height: -e.dy * scale),
                      blur: blurPx,
                      color: PaintRender.nsColor(e.color).cgColor)
        // (box  XOR  hole) → everything around the hole; its inner edge casts the
        // shadow inward. Opaque fill is mostly clipped away by `clip`.
        let ring = CGMutablePath()
        ring.addRect(box)
        ring.addPath(hole)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(ring)
        ctx.setFillColor(NSColor.black.cgColor)   // opaque; only the cast shadow shows
        ctx.fillPath(using: .evenOdd)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
