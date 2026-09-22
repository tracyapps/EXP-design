//
//  PaintRender.swift
//  EXP [design]
//
//  AppKit/CoreGraphics rendering for `Paint` (solid or gradient). Kept out of the
//  model so the model stays UI-free. Used by both the live canvas and the export
//  renderer, so a gradient looks identical on screen and in PNG/PDF.
//

import AppKit

/// One pattern tile, already rasterised, plus the lattice it repeats on
/// (FEAT-062 Stage B).
///
/// `PaintRender` deliberately receives an IMAGE rather than a `PatternSource`:
/// drawing a tile's `[Node]` content is the renderers' job (CanvasNSView,
/// ExportRenderView), and teaching this low-level paint utility about `Node`
/// would invert the dependency — Color/ does not know about the model's node
/// tree and should not start. Whoever holds the document builds one of these.
struct ResolvedPattern {
    /// A single tile. Its PIXEL size is independent of `tileSize`: the builder
    /// rasterises at whatever resolution the destination needs.
    var image: CGImage
    /// The repeat interval in DOCUMENT POINTS — SVG's `width`/`height` on
    /// `<pattern>`. For `objectBoundingBox` this is the EFFECTIVE interval for
    /// the one shape being filled (fraction × bounds), never the raw fraction.
    var tileSize: CGSize
    /// SVG `patternTransform`, applied to the whole lattice rather than to each
    /// tile's content. Keeping it here (instead of baking it into the tile
    /// image) is what lets the exporter write it back out as one attribute.
    var transform: CGAffineTransform
    /// FEAT-064. Where the lattice anchors in document space, BEFORE
    /// `transform` — `.zero` for `userSpaceOnUse` (the format's own anchor),
    /// or the filled shape's bounds origin (plus any fractional `x`/`y`) for
    /// `objectBoundingBox`, which is what makes the tile RIDE its layer.
    var origin: CGPoint = .zero
}

/// Resolves a fill's pattern reference to a drawable tile (FEAT-062 Stage B).
struct PatternResolver {
    /// `bounds` is the filled shape's frame in DOCUMENT points —
    /// `objectBoundingBox` tiles are sized and anchored as fractions of it
    /// (FEAT-064), while `userSpaceOnUse` ignores it. `scale` is the
    /// destination's points-to-pixels ratio, so a tile can be rasterised at the
    /// resolution it will actually be drawn at rather than always at 1× (blurry
    /// when zoomed in) or always at 4× (wasteful). Returning nil means "cannot
    /// draw this" — the caller then paints the ref's own fallback rather than
    /// leaving a hole.
    var resolve: (PatternRef, CGRect, CGFloat) -> ResolvedPattern?
    init(_ resolve: @escaping (PatternRef, CGRect, CGFloat) -> ResolvedPattern?) {
        self.resolve = resolve
    }
}

enum PaintRender {

    /// Fill an `NSBezierPath` (already in the current context's coordinates) with
    /// a paint. `bounds` is the path's bounding rect, used to place the gradient.
    /// `pdfSafeAlpha` routes gradient stops' ALPHA through a soft mask — required
    /// when the context emits PDF (raster export, thumbnails): CG's PDF emitter
    /// drops stop alpha entirely (PDF shadings have no alpha component), so a
    /// gradient-to-transparent fills OPAQUE there. The live canvas (bitmap
    /// context) keeps the direct path — it is correct there.
    static func fill(_ paint: Paint, path: NSBezierPath, bounds: CGRect, in ctx: CGContext,
                     pdfSafeAlpha: Bool = false, patterns: PatternResolver? = nil,
                     patternSpace: CGAffineTransform = .identity) {
        switch paint {
        case .solid(let c):
            nsColor(c).setFill()
            path.fill()
        case .gradient(let g):
            ctx.saveGState()
            path.addClip()
            drawGradient(g, in: bounds, ctx: ctx, pdfSafeAlpha: pdfSafeAlpha)
            ctx.restoreGState()
        case .pattern(let ref):
            ctx.saveGState()
            path.addClip()
            let drawn = tilePattern(ref, bounds: bounds, in: ctx, resolver: patterns,
                                    space: patternSpace)
            ctx.restoreGState()
            // FEAT-062. An unresolvable pattern paints the ref's OWN declared
            // fallback — never a colour invented here, and never nothing. Leaving
            // a hole would read as a rendering bug; inventing a black is the exact
            // lie this feature exists to remove.
            if !drawn {
                nsColor(ref.fallback).setFill()
                path.fill()
            }
        }
    }

    /// Fill a plain rect (no clip path) — used for artboard backgrounds.
    /// Stroke with alignment (v1.3). center = plain stroke. inside = clip to the
    /// path and stroke at 2× width (the outer half is clipped away — exact).
    /// outside = clip to everything EXCEPT the path (even-odd against a padded
    /// bounding rect) and stroke at 2× (the inner half is clipped away — exact).
    /// Only call with closed outlines for inside/outside; open paths must pass
    /// `.center` (an open stroke has no interior to clip against).
    static func strokeAligned(_ path: NSBezierPath, width: CGFloat,
                              alignment: StrokeAlignment, color: NSColor,
                              join: CGLineJoin = .miter, cap: CGLineCap = .butt,
                              miterLimit: CGFloat = 4,
                              pattern: StrokePattern = .solid,
                              in ctx: CGContext) {
        guard width > 0 else { return }
        let cg = path.cgPath
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineJoin(join)
        // BUG-064. CoreGraphics defaults to 10, SVG to 4; a miter join that
        // exceeds the limit falls back to bevel, so this changes the SHAPE of
        // sharp corners, not just their extent.
        ctx.setMiterLimit(miterLimit)
        configureStrokePattern(pattern, width: width, fallbackCap: cap, in: ctx)
        switch alignment {
        case .center:
            ctx.addPath(cg)
            ctx.setLineWidth(width)
            ctx.strokePath()
        case .inside:
            ctx.addPath(cg)
            ctx.clip()
            ctx.addPath(cg)
            ctx.setLineWidth(width * 2)
            ctx.strokePath()
        case .outside:
            let outer = CGMutablePath()
            outer.addRect(cg.boundingBoxOfPath.insetBy(dx: -width * 2 - 8, dy: -width * 2 - 8))
            outer.addPath(cg)
            ctx.addPath(outer)
            ctx.clip(using: .evenOdd)
            ctx.addPath(cg)
            ctx.setLineWidth(width * 2)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Apply one semantic stroke rhythm at the current render scale. Dots use a
    /// near-zero dash with round caps; a true zero-length dash is inconsistently
    /// handled across PDF/Core Graphics destinations.
    static func configureStrokePattern(_ pattern: StrokePattern, width: CGFloat,
                                       fallbackCap: CGLineCap = .butt,
                                       in ctx: CGContext) {
        switch pattern {
        case .solid:
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setLineCap(fallbackCap)
        case .dashed:
            ctx.setLineDash(phase: 0,
                            lengths: [max(3, width * 3), max(2, width * 2)])
            ctx.setLineCap(.butt)
        case .dotted:
            ctx.setLineDash(phase: 0,
                            lengths: [0.001, max(2, width * 2.25)])
            ctx.setLineCap(.round)
        }
    }

    /// Draw one endpoint marker in the renderer's current coordinate space.
    /// The 4×2 proportions match the SVG marker emitted by ExportRenderer and
    /// scale directly from the effective stroke width.
    static func drawMarker(_ marker: StrokeMarker, endpoint: CGPoint, interior: CGPoint,
                           strokeWidth: CGFloat, color: NSColor, in ctx: CGContext) {
        guard marker == .arrow, strokeWidth > 0 else { return }
        let dx = endpoint.x - interior.x
        let dy = endpoint.y - interior.y
        let magnitude = hypot(dx, dy)
        guard magnitude > 0.0001 else { return }
        let ux = dx / magnitude
        let uy = dy / magnitude
        let length = strokeWidth * 4
        let halfWidth = strokeWidth * 2
        // The authored endpoint is the arrow's flat base. Its point projects
        // outward, away from the stroke, so neither end consumes line length.
        let tip = CGPoint(x: endpoint.x + ux * length, y: endpoint.y + uy * length)
        let perpendicular = CGPoint(x: -uy * halfWidth, y: ux * halfWidth)

        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        ctx.move(to: tip)
        ctx.addLine(to: CGPoint(x: endpoint.x + perpendicular.x, y: endpoint.y + perpendicular.y))
        ctx.addLine(to: CGPoint(x: endpoint.x - perpendicular.x, y: endpoint.y - perpendicular.y))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    static func fillRect(_ paint: Paint, rect: CGRect, in ctx: CGContext,
                         pdfSafeAlpha: Bool = false, patterns: PatternResolver? = nil,
                         patternSpace: CGAffineTransform = .identity) {
        switch paint {
        case .solid(let c):
            nsColor(c).setFill()
            ctx.fill(rect)
        case .gradient(let g):
            ctx.saveGState()
            ctx.clip(to: rect)
            drawGradient(g, in: rect, ctx: ctx, pdfSafeAlpha: pdfSafeAlpha)
            ctx.restoreGState()
        case .pattern(let ref):
            ctx.saveGState()
            ctx.clip(to: rect)
            let drawn = tilePattern(ref, bounds: rect, in: ctx, resolver: patterns,
                                    space: patternSpace)
            ctx.restoreGState()
            if !drawn {
                nsColor(ref.fallback).setFill()
                ctx.fill(rect)
            }
        }
    }

    // MARK: Pattern tiling (FEAT-062 Stage B)

    /// Ceiling on tiles drawn for one fill. Real fixtures land in the tens (a
    /// 520pt tile over a 2000×1500 board is 12), so this only ever catches a
    /// pathological lattice — a near-zero `tileSize`, or a transform that
    /// collapses the interval — which would otherwise stall the frame outright.
    /// Exceeding it falls back to the flat colour rather than hanging.
    private static let maxPatternTiles = 40_000

    /// Repeat `ResolvedPattern`'s tile across `bounds`. The caller has already
    /// clipped; this only lays down the lattice.
    ///
    /// `space` maps DOCUMENT points into the context's current coordinates, and
    /// it is what pins the pattern to the artwork. The canvas pre-transforms its
    /// geometry (`docToView` bakes zoom and pan into the rects it draws) rather
    /// than setting a CTM, so a lattice anchored at the context origin slides
    /// under the shape as you pan and refuses to scale as you zoom — a
    /// `background-attachment: fixed` image, which is exactly what the owner saw.
    /// Anchoring in document space makes the tile ride its container.
    ///
    /// Returns false when the pattern cannot be drawn — unresolvable reference,
    /// degenerate tile, singular transform, or a tile count over the cap — so
    /// the caller can paint the fallback instead.
    private static func tilePattern(_ ref: PatternRef, bounds: CGRect, in ctx: CGContext,
                                    resolver: PatternResolver?,
                                    space: CGAffineTransform) -> Bool {
        guard let resolver, bounds.width > 0, bounds.height > 0 else { return false }
        let spaceDeterminant = space.a * space.d - space.b * space.c
        guard abs(spaceDeterminant) > 1e-9 else { return false }

        // The shape's frame in DOCUMENT points. Computed before resolving:
        // `objectBoundingBox` tiles size and anchor themselves as fractions of
        // exactly this rect (FEAT-064); `userSpaceOnUse` resolvers ignore it.
        let documentBounds = bounds.applying(space.inverted())

        // Rasterise at the resolution the tile will actually be drawn at. That is
        // the CONTEXT scale composed with `space`, because on the canvas the zoom
        // lives in `space`, not in the CTM — reading the CTM alone would pin every
        // tile at 1× and go soft the moment you zoom in.
        let effective = space.concatenating(ctx.ctm)
        let effectiveScale = abs(effective.a * effective.d - effective.b * effective.c).squareRoot()
        let scale = min(4, max(1, effectiveScale.isFinite ? effectiveScale : 1))
        guard let pattern = resolver.resolve(ref, documentBounds, scale) else { return false }

        let tw = pattern.tileSize.width, th = pattern.tileSize.height
        guard tw > 0.01, th > 0.01 else { return false }

        // The lattice lives in `transform`'s space, itself anchored in document
        // space. A singular transform has no inverse — CGAffineTransform.inverted()
        // returns the input unchanged in that case, which would silently tile the
        // wrong region — so check the determinant rather than trusting the result.
        let t = pattern.transform
        let determinant = t.a * t.d - t.b * t.c
        guard abs(determinant) > 1e-9 else { return false }

        let region = documentBounds.applying(t.inverted())
        guard region.width.isFinite, region.height.isFinite else { return false }

        // Indices count from the lattice's ORIGIN, not from zero:
        // `userSpaceOnUse` anchors at the document origin (origin is .zero, so
        // this is the arithmetic the lattice has always used), while
        // `objectBoundingBox` anchors at the shape's bounds — the tile rides
        // its layer because the anchor moves when the shape does.
        let ox = pattern.origin.x, oy = pattern.origin.y
        let i0 = Int(floor((region.minX - ox) / tw)), i1 = Int(ceil((region.maxX - ox) / tw))
        let j0 = Int(floor((region.minY - oy) / th)), j1 = Int(ceil((region.maxY - oy) / th))
        guard i1 >= i0, j1 >= j0 else { return false }
        let columns = i1 - i0 + 1, rows = j1 - j0 + 1
        guard columns > 0, rows > 0,
              columns.multipliedReportingOverflow(by: rows).overflow == false,
              columns * rows <= maxPatternTiles else { return false }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.concatenate(space)
        ctx.concatenate(t)
        ctx.interpolationQuality = .high
        for j in j0...j1 {
            for i in i0...i1 {
                ctx.saveGState()
                // Model space is y-down and a CGImage draws y-up, so each tile is
                // flipped in place — the same idiom the placed-image path uses.
                ctx.translateBy(x: ox + CGFloat(i) * tw, y: oy + CGFloat(j) * th + th)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(pattern.image, in: CGRect(x: 0, y: 0, width: tw, height: th))
                ctx.restoreGState()
            }
        }
        return true
    }

    static func drawGradient(_ g: GradientFill, in rect: CGRect, ctx: CGContext,
                             pdfSafeAlpha: Bool = false) {
        let stops = g.sortedStops
        guard !stops.isEmpty else { return }
        // Interpolate in sRGB — matching the stop colors (which are sRGB CGColors),
        // the solid-fill path, and export. The old device-RGB space is UNMANAGED, so
        // it rendered one way in the live window (a device context) and another in
        // the color-managed offscreen blit bitmap — a gradient color shift (darkening) seen
        // ONLY while panning/zooming. sRGB is color-matched identically in both paths.
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        func ramp(_ colors: [CGColor]) -> CGGradient? {
            let locations = stops.map { CGFloat($0.position) }
            return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)
        }
        // PDF-bound contexts: CG drops stop ALPHA (a shading's color space has no
        // alpha component — a white 0.9→0.0 radial exports as a SOLID opaque
        // disc). Coverage therefore rides a soft mask — the same PDF-safe route
        // the dissolve masks and noise content masks already use — while the
        // color ramp stays vector. Bitmap contexts (the canvas) are exact as-is.
        if pdfSafeAlpha, stops.contains(where: { $0.color.a < 0.999 }),
           let mask = gradientAlphaMask(g, in: rect),
           let gradient = ramp(stops.map { cgColorOpaque($0.color) }) {
            ctx.saveGState()
            ctx.clip(to: rect, mask: mask)
            switch g.kind {
            case .linear:
                let (s, e) = g.linearPoints(in: rect)
                ctx.drawLinearGradient(gradient, start: s, end: e, options: opts)
            case .radial:
                let c = CGPoint(x: rect.midX, y: rect.midY)
                let r = max(1, hypot(rect.width, rect.height) / 2)
                ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                                       endCenter: c, endRadius: r, options: opts)
            }
            ctx.restoreGState()
            return
        }
        let colors = stops.map { cgColor($0.color) }
        guard let gradient = ramp(colors) else { return }
        switch g.kind {
        case .linear:
            let (s, e) = g.linearPoints(in: rect)
            ctx.drawLinearGradient(gradient, start: s, end: e, options: opts)
        case .radial:
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = max(1, hypot(rect.width, rect.height) / 2)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                                   endCenter: c, endRadius: r, options: opts)
        }
    }

    /// Coverage ramp for `drawGradient(pdfSafeAlpha:)`: the gradient drawn into a
    /// rect-sized RGBA bitmap with white at each stop's ALPHA, so the alpha
    /// channel alone is the mask `CGContext.clip(to:mask:)` consumes. Same
    /// geometry formulas as the color ramp; same flipped user-space mapping the
    /// export renderer's offscreen bitmaps use.
    ///
    /// Baked at 3× supersample: the PDF rasterizer nearest-samples this mask
    /// when scaling (measured 2026-08-28: a 1× mask exported at 2× advanced the
    /// falloff in 2px steps — "choppy" gradients), so 1×/2×/3× raster exports
    /// read it natively or nearly so. The pixel caps keep worst-case memory
    /// bounded; a ramp forced below 3× still resamples more gracefully than the
    /// 8-bit color path bands.
    private static func gradientAlphaMask(_ g: GradientFill, in rect: CGRect) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let scale = min(3, 4096 / max(rect.width, rect.height),
                        (8_000_000 / (rect.width * rect.height)).squareRoot())
        let pw = max(1, Int(rect.width * scale)), ph = max(1, Int(rect.height * scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: pw, height: ph,
                                     bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        bitmap.translateBy(x: 0, y: CGFloat(ph))
        bitmap.scaleBy(x: scale, y: -scale)
        bitmap.translateBy(x: -rect.minX, y: -rect.minY)
        let stops = g.sortedStops
        let colors = stops.map {
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: CGFloat($0.color.a))
        }
        let locations = stops.map { CGFloat($0.position) }
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray,
                                        locations: locations) else { return nil }
        let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch g.kind {
        case .linear:
            let (s, e) = g.linearPoints(in: rect)
            bitmap.drawLinearGradient(gradient, start: s, end: e, options: opts)
        case .radial:
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = max(1, hypot(rect.width, rect.height) / 2)
            bitmap.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                                      endCenter: c, endRadius: r, options: opts)
        }
        return bitmap.makeImage()
    }

    static func nsColor(_ c: RGBAColor) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
    }
    static func cgColor(_ c: RGBAColor) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
    }
    /// The stop color with alpha forced to 1 — for the masked (pdfSafeAlpha)
    /// gradient path, where coverage comes from the mask, not the color.
    static func cgColorOpaque(_ c: RGBAColor) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
    }
}
