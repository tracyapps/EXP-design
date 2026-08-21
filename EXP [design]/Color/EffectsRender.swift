//
//  EffectsRender.swift
//  EXP [design]
//
//  Core-Graphics/Core-Image rendering for node effects. Shared by the on-canvas
//  drawing and the PNG/PDF export so effects look identical in both.
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
import CoreImage
import CoreGraphics

/// The outline a shape casts a shadow from, plus spread-grown/shrunk variants.
/// Space-agnostic (the caller builds it in view or local coordinates).
struct Silhouette {
    enum Shape {
        case roundRect(radius: CGFloat)
        /// v1.3 per-corner radii (already scaled to the silhouette's space).
        case perCornerRect(CornerRadii)
        case oval
        case custom(CGPath)
    }
    let rect: CGRect
    let shape: Shape

    /// The path grown (positive) or shrunk (negative) by `spread`. Arbitrary
    /// custom paths ignore spread (returned unchanged).
    func path(spread: CGFloat) -> CGPath {
        switch shape {
        case .roundRect(let r):
            let rr = rect.insetBy(dx: -spread, dy: -spread)
            let rad = min(max(0, r + spread),
                          max(0, min(rr.width, rr.height) / 2))
            return CGPath(roundedRect: rr, cornerWidth: rad, cornerHeight: rad, transform: nil)
        case .perCornerRect(let radii):
            // Each radius grows with the spread, mirroring the uniform case.
            return radii.offset(by: spread).path(in: rect.insetBy(dx: -spread, dy: -spread))
        case .oval:
            return CGPath(ellipseIn: rect.insetBy(dx: -spread, dy: -spread), transform: nil)
        case .custom(let p):
            return p
        }
    }
    var clip: CGPath { path(spread: 0) }
}

enum EffectsRender {

    /// Whether the CANVAS preview can honour a shadow's `spread` for this node.
    ///
    /// BUG-034. `Silhouette.path(spread:)` above can only grow or shrink a
    /// rect / rounded-rect / ellipse outline; a `.custom` path comes back
    /// unchanged, and text, groups, lines and instances have no silhouette at all
    /// (their shadow is blurred from rendered content). SVG export takes the other
    /// road entirely — `ExportRenderer` emits `<feMorphology>` for ANY node type
    /// whenever spread is non-zero — so canvas and export can legitimately
    /// disagree. Stage 1 of the fix is to SAY where they disagree (the Effects
    /// inspector reads this); Stage 2, committed to Wave 7, removes the divergence
    /// by dilating the alpha mask with the same BOX structuring element
    /// `feMorphology` uses. Deleting `Effect.spread` was considered and rejected:
    /// the CSS, Figma and SVG importers all read spread, so dropping the field
    /// would silently lose imported data.
    ///
    /// Keep in sync with `CanvasNSView.nodeSilhouette`.
    static func previewsSpread(_ node: Node) -> Bool {
        switch node.content {
        case .rectangle, .ellipse, .image: return true
        default: return false
        }
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// A bounded bitmap protects the same interaction/export paths that already
    /// guard shadow buffers. Above this limit the caller draws the unblurred
    /// vector content rather than risking an allocation failure or UI hang.
    private static let maxLayerPixels = 32_000_000
    private static let maxLayerDimension = 12_000

    /// Blur a node's own pixels while leaving its geometry editable. `bounds` is
    /// in the caller's y-down user space; `deviceScale` is backing scale on the
    /// canvas and 1 for export. The drawing closure is replayed into a tightly
    /// bounded transparent bitmap, filtered, then composited back once.
    static func drawLayerBlur(_ effects: [Effect], bounds: CGRect,
                              deviceScale: CGFloat, in ctx: CGContext,
                              draw: (CGContext) -> Void) {
        let active = effects.filter { $0.isEnabled && $0.kind == .layerBlur && $0.blur > 0 }
        guard !active.isEmpty, !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            draw(ctx)
            return
        }
        let scale = max(1, deviceScale)
        let maxSigma = active.map(\.blur).max() ?? 0
        let pad = maxSigma * 3 + 2 / scale
        let expanded = bounds.insetBy(dx: -pad, dy: -pad)
        let width = max(1, Int(ceil(expanded.width * scale)))
        let height = max(1, Int(ceil(expanded.height * scale)))
        guard width <= maxLayerDimension, height <= maxLayerDimension,
              width <= maxLayerPixels / max(1, height),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: 0,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            draw(ctx)
            return
        }

        // Match EXP's top-left, y-down drawing space inside the offscreen bitmap.
        bitmap.translateBy(x: 0, y: CGFloat(height))
        bitmap.scaleBy(x: scale, y: -scale)
        bitmap.translateBy(x: -expanded.minX, y: -expanded.minY)
        let graphics = NSGraphicsContext(cgContext: bitmap, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        draw(bitmap)
        NSGraphicsContext.restoreGraphicsState()

        guard let image = bitmap.makeImage() else { draw(ctx); return }
        var filtered = CIImage(cgImage: image)
        for effect in active {
            let sigma = Double(min(maxShadowBlurPx, effect.blur * scale))
            filtered = filtered.clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .cropped(to: filtered.extent)
        }
        guard let output = ciContext.createCGImage(filtered, from: filtered.extent) else {
            draw(ctx)
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: expanded.minX, y: expanded.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(output, in: CGRect(origin: .zero, size: expanded.size))
        ctx.restoreGState()
    }

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
    ///
    /// `castBounds` (the caster's bounding box, same space as the ctx) matters
    /// enormously: a transparency layer allocates its buffer at the CURRENT CLIP
    /// size. Without a clip that's the whole canvas — one full-canvas alloc +
    /// clear + composite PER SHADOWED NODE, which is what made rendering into an
    /// unclipped offscreen bitmap take seconds. Clipping to the caster + blur +
    /// offset bounds the buffer to the node's own footprint; the shadow cannot
    /// paint outside that region anyway, so the result is pixel-identical.
    /// `knockout`, when provided AND `e.preserveTransparency` is set, draws the
    /// node's TRUE silhouette/content (no spread outset); its pixels — and any
    /// shadow beneath them — are punched out of the shadow layer with
    /// `.destinationOut`, so the shadow exists only OUTSIDE the object. That is
    /// what keeps a semi-transparent fill from going black on its own shadow.
    /// Partial alpha knocks out proportionally — identical semantics to the SVG
    /// export's `feComposite operator="out"`.
    static func drawDropShadow(_ e: Effect, scale: CGFloat, in ctx: CGContext,
                               castBounds: CGRect? = nil,
                               knockout: (() -> Void)? = nil, caster: () -> Void) {
        guard e.isEnabled, e.kind == .dropShadow else { return }
        ctx.saveGState()
        // Flipped (y-down) context: negate the height so +Y reads as *down*,
        // matching CSS `box-shadow` offset-y. (+X = right is already correct.)
        let blurPx = min(max(0, e.blur * scale), maxShadowBlurPx)
        if let b = castBounds {
            // Everything the shadow can reach: caster bounds grown by the blur
            // radius and the offset, plus a small pad for antialiasing fringe.
            let pad = blurPx + (abs(e.dx) + abs(e.dy)) * scale + 8
            ctx.clip(to: b.insetBy(dx: -pad, dy: -pad))
        }
        if e.preserveTransparency, let knockout {
            // Outer layer: (shadowed caster) − (object's own pixels).
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setShadow(offset: CGSize(width: e.dx * scale, height: -e.dy * scale),
                          blur: blurPx,
                          color: PaintRender.nsColor(e.color).cgColor)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            caster()
            ctx.endTransparencyLayer()
            // Punch: clear the shadow state, then erase the object's footprint
            // from the layer (grouped so overlapping punch drawing acts once).
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setBlendMode(.destinationOut)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            knockout()
            ctx.endTransparencyLayer()
            ctx.endTransparencyLayer()
        } else {
            ctx.setShadow(offset: CGSize(width: e.dx * scale, height: -e.dy * scale),
                          blur: blurPx,
                          color: PaintRender.nsColor(e.color).cgColor)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            caster()
            ctx.endTransparencyLayer()
        }
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

    /// Noise / grain: composite a turbulence tile over the node with the
    /// effect's own blend mode + amount. `clip` is the node's silhouette in the
    /// ctx's space (pass nil for silhouette-less nodes — the CALLER is then
    /// responsible for restricting the noise to the node's pixels, e.g. via a
    /// transparency layer + destination-in punch; see CanvasNSView.drawNode).
    /// `rect` is the node's frame in the ctx's space; `modelSize` its size in
    /// model points (the tile is generated in model space so texture scale is
    /// zoom-independent and matches the SVG export's feTurbulence).
    static func drawNoise(_ e: Effect, clip: CGPath?, rect: CGRect, modelSize: CGSize, in ctx: CGContext) {
        guard e.isEnabled, e.kind == .noise, e.amount > 0 else { return }
        guard let tile = TurbulenceNoise.noiseImage(for: e, size: modelSize) else { return }
        ctx.saveGState()
        if let clip {
            ctx.addPath(clip)
            ctx.clip()
        } else {
            ctx.clip(to: rect)
        }
        ctx.setAlpha(min(1, max(0, e.amount)))
        ctx.setBlendMode(e.blend.cg)
        ctx.interpolationQuality = .none   // crisp grain at any zoom
        ctx.draw(tile, in: rect)
        ctx.restoreGState()
    }
}
