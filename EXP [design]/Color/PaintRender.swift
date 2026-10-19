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
    private(set) static var meshFailureGeneration: UInt64 = 0
    private static func mesh(_ value: MeshFill, bounds: CGRect, ctx: CGContext, pdf: Bool) {
        do { try drawMesh(value,in: bounds,ctx: ctx,pdfSafeAlpha: pdf) }
        catch {
            meshFailureGeneration &+= 1
            ctx.setFillColor(NSColor.systemRed.cgColor); ctx.fill(bounds)
        }
    }


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
        case .mesh(let m):
            ctx.saveGState(); path.addClip()
            mesh(m,bounds: bounds,ctx: ctx,pdf: pdfSafeAlpha)
            ctx.restoreGState()
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
    /// handled across PDF/CoreGraphics destinations.
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

    /// BUG-065. Stroke with ANY paint — a gradient (or pattern) stroke. The
    /// stroke region becomes the clip — built with the same alignment
    /// arithmetic `strokeAligned` uses, and shaped by the same join/miter/cap/
    /// dash settings, since those change the STROKED PATH's outline too — and
    /// the paint fills it through the same primitives the fills use, so a
    /// gradient stroke cannot disagree between the canvas and raster/PDF export.
    ///
    /// Solid strokes do NOT come through here: callers branch and keep
    /// `strokeAligned`/`strokePath`, which renders byte-for-byte what every
    /// existing document has always drawn. `bounds` is the element's GEOMETRY
    /// frame — SVG resolves a stroke gradient against the element bbox, not the
    /// outer stroke edge, and the canvas matches the export.
    static func strokePaint(_ path: NSBezierPath, width: CGFloat,
                            alignment: StrokeAlignment, paint: Paint,
                            bounds: CGRect, in ctx: CGContext,
                            join: CGLineJoin = .miter, cap: CGLineCap = .butt,
                            miterLimit: CGFloat = 4,
                            pattern: StrokePattern = .solid,
                            pdfSafeAlpha: Bool = false,
                            patterns: PatternResolver? = nil,
                            patternSpace: CGAffineTransform = .identity) {
        guard width > 0 else { return }
        let cg = path.cgPath
        let cover = cg.boundingBoxOfPath.insetBy(dx: -width * 2 - 8, dy: -width * 2 - 8)

        ctx.saveGState()
        ctx.setLineJoin(join)
        // Same rationale as strokeAligned: CG defaults to 10, SVG to 4, and the
        // limit changes the SHAPE of sharp corners in the stroked region.
        ctx.setMiterLimit(miterLimit)
        configureStrokePattern(pattern, width: width, fallbackCap: cap, in: ctx)
        switch alignment {
        case .center:
            ctx.addPath(cg)
            ctx.setLineWidth(width)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
        case .inside:
            ctx.addPath(cg)
            ctx.clip()
            ctx.addPath(cg)
            ctx.setLineWidth(width * 2)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
        case .outside:
            let outer = CGMutablePath()
            outer.addRect(cover)
            outer.addPath(cg)
            ctx.addPath(outer)
            ctx.clip(using: .evenOdd)
            ctx.addPath(cg)
            ctx.setLineWidth(width * 2)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
        }
        switch paint {
        case .solid(let c):
            ctx.setFillColor(cgColor(c))
            ctx.fill(cover)
        case .mesh(let m):
            do { try drawMeshStroke(m,bounds: bounds,cover: cover,ctx: ctx) }
            catch { meshFailureGeneration &+= 1; ctx.setFillColor(NSColor.systemRed.cgColor); ctx.fill(cover) }
        case .gradient(let g):
            ctx.saveGState()
            drawGradient(g, in: bounds, ctx: ctx, pdfSafeAlpha: pdfSafeAlpha)
            ctx.restoreGState()
        case .pattern(let ref):
            let drawn = tilePattern(ref, bounds: cover, in: ctx, resolver: patterns,
                                    space: patternSpace)
            if !drawn {
                ctx.setFillColor(cgColor(ref.fallback))
                ctx.fill(cover)
            }
        }
        ctx.restoreGState()
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
        case .mesh(let m): mesh(m,bounds: rect,ctx: ctx,pdf: pdfSafeAlpha)
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
    /// degenerate tile or singular transform — so
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
        guard tw.isFinite, th.isFinite, tw > 0, th > 0 else { return false }

        // The lattice lives in `transform`'s space, itself anchored in document
        // space. A singular transform has no inverse — CGAffineTransform.inverted()
        // returns the input unchanged in that case, which would silently tile the
        // wrong region — so check the determinant rather than trusting the result.
        let t = pattern.transform
        let determinant = t.a * t.d - t.b * t.c
        guard abs(determinant) > 1e-9 else { return false }

        let region = documentBounds.applying(t.inverted())
        guard region.width.isFinite, region.height.isFinite else { return false }

        // The lattice origin remains fixed as its repeat size changes. The
        // native tiled sampler submits one pattern, so the former 40,000-draw
        // loop cap must not turn a legitimate small-scale fill into its fallback.
        let ox = pattern.origin.x, oy = pattern.origin.y
        guard ox.isFinite, oy.isFinite else { return false }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.concatenate(space)
        ctx.concatenate(t)
        ctx.interpolationQuality = .high
        // One repeating image sampler owns every shared edge. Independently
        // antialiasing adjacent image rectangles leaves a transparent hairline;
        // overlapping them instead corrupts translucent artwork at each join.
        // Flip the lattice once so its image remains upright in model y-down space.
        ctx.translateBy(x: ox, y: oy + th)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(pattern.image,in: CGRect(x: 0, y: 0, width: tw, height: th),byTiling: true)
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
                drawRadial(gradient,geometry: g.radialGeometry(in: rect),rect: rect,ctx: ctx,options: opts)
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
            drawRadial(gradient,geometry: g.radialGeometry(in: rect),rect: rect,ctx: ctx,options: opts)
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
            drawRadial(gradient,geometry: g.radialGeometry(in: rect),rect: rect,ctx: bitmap,options: opts)
        }
        return bitmap.makeImage()
    }

    private static func drawRadial(_ gradient: CGGradient,geometry: RadialGradientGeometry,
                                   rect: CGRect,ctx: CGContext,options: CGGradientDrawingOptions) {
        guard rect.width > 0,rect.height > 0,geometry.isValid else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX+geometry.center.x*rect.width,y: rect.minY+geometry.center.y*rect.height)
        ctx.scaleBy(x: geometry.radius.width*rect.width,y: geometry.radius.height*rect.height)
        ctx.drawRadialGradient(gradient,startCenter: .zero,startRadius: 0,endCenter: .zero,endRadius: 1,options: options)
        ctx.restoreGState()
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

extension PaintRender {
    /// Shared mesh primitive for canvas, export and swatches. The native path is
    /// vector work proportional to the bounded point count, independent of zoom.
    /// PDF alpha uses bounded coverage masks because PDF shadings drop stop alpha.
    static func drawMesh(_ mesh: MeshFill, in rect: CGRect, ctx: CGContext,
                         pdfSafeAlpha: Bool = false) throws {
        try mesh.validate()
        guard [rect.minX,rect.minY,rect.maxX,rect.maxY,rect.width * rect.height].allSatisfy(\.isFinite),
              rect.width > 0, rect.height > 0 else { throw MeshFill.ValidationError.invalidData }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.clip(to: rect)
        ctx.setFillColor(cgColor(mesh.base)); ctx.fill(rect)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for point in mesh.points where point.color.a * point.opacity > 0 {
            func radial(in target: CGContext) {
                let c = point.color
                let rgb = (c.r,c.g,c.b)
                let colors = [CGColor(srgbRed: rgb.0,green: rgb.1,blue: rgb.2,alpha: c.a * point.opacity),
                              CGColor(srgbRed: rgb.0,green: rgb.1,blue: rgb.2,alpha: 0)]
                let gradient = CGGradient(colorsSpace: space,colors: colors as CFArray,locations: [0,1])!
                target.saveGState(); defer { target.restoreGState() }
                target.translateBy(x: rect.minX,y: rect.minY)
                target.scaleBy(x: rect.width,y: rect.height)
                target.drawRadialGradient(gradient,startCenter: point.position,startRadius: 0,
                    endCenter: point.position,endRadius: point.radius,options: [.drawsAfterEndLocation])
            }
            if pdfSafeAlpha {
                // At most 1 MP / 1024 per axis per point, generated one at a
                // time. No full-layer float capture or zoom-squared allocation.
                let scale = min(3,1024 / max(rect.width,rect.height),
                                (1_048_576 / (rect.width * rect.height)).squareRoot())
                let w = min(1024,max(1,Int(ceil(rect.width * scale))))
                let h = min(1024,max(1,Int(ceil(rect.height * scale))))
                guard let mask = CGContext(data: nil,width: w,height: h,bitsPerComponent: 8,bytesPerRow: 0,
                    space: space,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw MeshFill.ValidationError.invalidData
                }
                // Evaluate coverage at exact pixel centres. Re-rasterizing a
                // translucent CGGradient into a mask quantizes the falloff twice.
                // Mask image rows run opposite the destination's y-down space.
                guard let data = mask.data else { throw MeshFill.ValidationError.invalidData }
                let bytes = data.assumingMemoryBound(to: UInt8.self)
                for y in 0..<h {
                    let dy = (1 - (Double(y) + 0.5) / Double(h) - point.position.y) / point.radius
                    for x in 0..<w {
                        let dx = ((Double(x) + 0.5) / Double(w) - point.position.x) / point.radius
                        let a = UInt8((255 * point.color.a * point.opacity * max(0,1-hypot(dx,dy))).rounded())
                        let index = y * mask.bytesPerRow + x * 4
                        for channel in 0..<4 { bytes[index + channel] = a }
                    }
                }
                guard let image = mask.makeImage() else { throw MeshFill.ValidationError.invalidData }
                ctx.saveGState()
                ctx.clip(to: rect,mask: image)
                ctx.setFillColor(cgColorOpaque(point.color)); ctx.fill(rect)
                ctx.restoreGState()
            } else { radial(in: ctx) }
        }
    }
}

extension PaintRender {
    static func meshPreview(_ mesh: MeshFill, size: CGSize) -> CGImage? {
        guard size.width.isFinite,size.height.isFinite,size.width > 0,size.height > 0 else { return nil }
        let w = min(256,max(1,Int(min(256,size.width)))), h = min(256,max(1,Int(min(256,size.height))))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil,width: w,height: h,bitsPerComponent: 8,bytesPerRow: 0,
            space: space,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0,y: CGFloat(h)); ctx.scaleBy(x: 1,y: -1)
        guard (try? drawMesh(mesh,in: CGRect(x: 0,y: 0,width: w,height: h),ctx: ctx)) != nil else { return nil }
        return ctx.makeImage()
    }
}

extension PaintRender {
    private static let meshStrokeTiles: NSCache<NSString,CGImage> = {
        let cache = NSCache<NSString,CGImage>(); cache.totalCostLimit = 32 << 20; cache.countLimit = 32; return cache
    }()
    /// Match the SVG pattern paint server on an outline, including the portions
    /// outside its geometry box: the completed unit mesh repeats at box edges.
    private static func drawMeshStroke(_ mesh: MeshFill,bounds: CGRect,cover: CGRect,ctx: CGContext) throws {
        try mesh.validate()
        guard [bounds.width,bounds.height,bounds.width*bounds.height,cover.minX,cover.minY,cover.maxX,cover.maxY].allSatisfy(\.isFinite),bounds.width > 0,bounds.height > 0 else { throw MeshFill.ValidationError.invalidData }
        let scale = min(4,max(1,hypot(ctx.ctm.a,ctx.ctm.b)),4096/max(bounds.width,bounds.height),sqrt(4_000_000/(bounds.width*bounds.height)))
        let w = max(1,Int(min(4096,ceil(bounds.width*scale)))),h = max(1,Int(min(4096,ceil(bounds.height*scale))))
        let key = "\(try mesh.metadata()):\(w)x\(h)" as NSString
        let image: CGImage
        if let hit = meshStrokeTiles.object(forKey: key) { image = hit }
        else {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let tile = CGContext(data: nil,width: w,height: h,bitsPerComponent: 8,bytesPerRow: 0,space: space,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw MeshFill.ValidationError.invalidData }
            tile.translateBy(x: 0,y: CGFloat(h)); tile.scaleBy(x: CGFloat(w)/bounds.width,y: -CGFloat(h)/bounds.height)
            try drawMesh(mesh,in: CGRect(origin: .zero,size: bounds.size),ctx: tile)
            guard let output = tile.makeImage() else { throw MeshFill.ValidationError.invalidData }
            image = output; meshStrokeTiles.setObject(image,forKey: key,cost: image.bytesPerRow*image.height)
        }
        let x0 = floor((cover.minX-bounds.minX)/bounds.width),x1 = ceil((cover.maxX-bounds.minX)/bounds.width)
        let y0 = floor((cover.minY-bounds.minY)/bounds.height),y1 = ceil((cover.maxY-bounds.minY)/bounds.height)
        guard [x0,x1,y0,y1].allSatisfy(\.isFinite),abs(x0) < 40000,abs(x1) < 40000,abs(y0) < 40000,abs(y1) < 40000,
              (x1-x0+1)*(y1-y0+1) <= 40000 else { throw MeshFill.ValidationError.invalidData }
        for y in Int(y0)...Int(y1) { for x in Int(x0)...Int(x1) {
            let rect = bounds.offsetBy(dx: CGFloat(x)*bounds.width,dy: CGFloat(y)*bounds.height)
            ctx.saveGState(); ctx.translateBy(x: rect.minX,y: rect.maxY); ctx.scaleBy(x: 1,y: -1)
            ctx.draw(image,in: CGRect(origin: .zero,size: rect.size)); ctx.restoreGState()
        }}
    }
}
