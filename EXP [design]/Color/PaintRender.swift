//
//  PaintRender.swift
//  EXP [design]
//
//  AppKit/CoreGraphics rendering for `Paint` (solid or gradient). Kept out of the
//  model so the model stays UI-free. Used by both the live canvas and the export
//  renderer, so a gradient looks identical on screen and in PNG/PDF.
//

import AppKit

enum PaintRender {

    /// Fill an `NSBezierPath` (already in the current context's coordinates) with
    /// a paint. `bounds` is the path's bounding rect, used to place the gradient.
    /// `pdfSafeAlpha` routes gradient stops' ALPHA through a soft mask — required
    /// when the context emits PDF (raster export, thumbnails): CG's PDF emitter
    /// drops stop alpha entirely (PDF shadings have no alpha component), so a
    /// gradient-to-transparent fills OPAQUE there. The live canvas (bitmap
    /// context) keeps the direct path — it is correct there.
    static func fill(_ paint: Paint, path: NSBezierPath, bounds: CGRect, in ctx: CGContext,
                     pdfSafeAlpha: Bool = false) {
        switch paint {
        case .solid(let c):
            nsColor(c).setFill()
            path.fill()
        case .gradient(let g):
            ctx.saveGState()
            path.addClip()
            drawGradient(g, in: bounds, ctx: ctx, pdfSafeAlpha: pdfSafeAlpha)
            ctx.restoreGState()
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
                              pattern: StrokePattern = .solid,
                              in ctx: CGContext) {
        guard width > 0 else { return }
        let cg = path.cgPath
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineJoin(join)
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
                         pdfSafeAlpha: Bool = false) {
        switch paint {
        case .solid(let c):
            nsColor(c).setFill()
            ctx.fill(rect)
        case .gradient(let g):
            ctx.saveGState()
            ctx.clip(to: rect)
            drawGradient(g, in: rect, ctx: ctx, pdfSafeAlpha: pdfSafeAlpha)
            ctx.restoreGState()
        }
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
