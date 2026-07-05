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
