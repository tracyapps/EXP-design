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
    static func fill(_ paint: Paint, path: NSBezierPath, bounds: CGRect, in ctx: CGContext) {
        switch paint {
        case .solid(let c):
            nsColor(c).setFill()
            path.fill()
        case .gradient(let g):
            ctx.saveGState()
            path.addClip()
            drawGradient(g, in: bounds, ctx: ctx)
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

    static func fillRect(_ paint: Paint, rect: CGRect, in ctx: CGContext) {
        switch paint {
        case .solid(let c):
            nsColor(c).setFill()
            ctx.fill(rect)
        case .gradient(let g):
            ctx.saveGState()
            ctx.clip(to: rect)
            drawGradient(g, in: rect, ctx: ctx)
            ctx.restoreGState()
        }
    }

    static func drawGradient(_ g: GradientFill, in rect: CGRect, ctx: CGContext) {
        let stops = g.sortedStops
        guard !stops.isEmpty else { return }
        // Interpolate in sRGB — matching the stop colors (which are sRGB CGColors),
        // the solid-fill path, and export. The old device-RGB space is UNMANAGED, so
        // it rendered one way in the live window (a device context) and another in the
        // color-managed offscreen blit bitmap — a gradient color shift (darkening) seen
        // ONLY while panning/zooming. sRGB is color-matched identically in both paths.
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colors = stops.map { cgColor($0.color) } as CFArray
        let locations = stops.map { CGFloat($0.position) }
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) else { return }
        let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
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

    static func nsColor(_ c: RGBAColor) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
    }
    static func cgColor(_ c: RGBAColor) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
    }
}
