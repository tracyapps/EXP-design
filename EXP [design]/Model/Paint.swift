//
//  Paint.swift
//  EXP [design]
//
//  A fill can be a flat color OR a gradient. `Paint` is the model type used for
//  shape fills and artboard backgrounds. It stays UI-free (sRGB numbers only);
//  AppKit/CoreGraphics bridging for rendering lives in PaintRender.swift.
//
//  Backward compatibility: a flat `Paint` encodes as a *bare* `RGBAColor` object
//  ({r,g,b,a}) — exactly what older files stored for `fill` — so old documents
//  decode straight into `.solid`, and new flat fills look unchanged on disk. Only
//  gradients add a tagged object.
//

import Foundation
import CoreGraphics

/// One color stop of a gradient. `position` is 0…1 along the gradient.
struct GradientStop: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var color: RGBAColor
    var position: Double

    nonisolated init(id: UUID = UUID(), color: RGBAColor, position: Double) {
        self.id = id
        self.color = color
        self.position = position
    }
}

/// A multi-stop gradient. Geometry is normalized to the shape's bounding box:
/// linear is driven by `angle` (degrees, y-down: 0 = →, 90 = ↓) or, when the
/// gradient line has been placed explicitly, by `start`/`end`; radial is centered
/// with a radius to the box corner.
struct GradientFill: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case linear, radial }

    var kind: Kind = .linear
    var stops: [GradientStop] = [
        GradientStop(color: .white, position: 0),
        GradientStop(color: .black, position: 1)
    ]
    var angle: Double = 90

    /// FEAT-032 — the gradient LINE, in UNIT space (0…1 of the fill rect, the same
    /// objectBoundingBox convention CSS and SVG use). `nil` means "derive from
    /// `angle`", which is exactly what every document written before this field
    /// contained, so old files load and draw identically.
    ///
    /// An angle alone cannot express where the ramp STARTS or how LONG it is — drag
    /// a gradient's handles in any other tool and both change. Storing the line is
    /// what makes on-canvas handles representable at all, and it is also how the
    /// value reaches SVG and CSS without being flattened back to a full-width sweep.
    /// `angle` is kept in sync with the line (see `settingLine`) so the inspector's
    /// numeric field and anything reading the angle stay correct.
    var start: CGPoint? = nil
    var end: CGPoint? = nil

    enum CodingKeys: String, CodingKey { case kind, stops, angle, start, end }

    /// Every parameter keeps a default so this matches the memberwise initializer
    /// the compiler used to synthesize — existing call sites are unaffected.
    init(kind: Kind = .linear,
         stops: [GradientStop] = [GradientStop(color: .white, position: 0),
                                  GradientStop(color: .black, position: 1)],
         angle: Double = 90,
         start: CGPoint? = nil, end: CGPoint? = nil) {
        self.kind = kind; self.stops = stops; self.angle = angle
        self.start = start; self.end = end
    }

    /// Tolerant decode: a file without `start`/`end` is an angle-only gradient.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .linear
        stops = try c.decodeIfPresent([GradientStop].self, forKey: .stops) ?? [
            GradientStop(color: .white, position: 0),
            GradientStop(color: .black, position: 1)
        ]
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 90
        start = try c.decodeIfPresent(CGPoint.self, forKey: .start)
        end = try c.decodeIfPresent(CGPoint.self, forKey: .end)
        // A half-written line is meaningless; fall back to the angle rather than
        // guessing the missing endpoint.
        if start == nil || end == nil { start = nil; end = nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(stops, forKey: .stops)
        try c.encode(angle, forKey: .angle)
        try c.encodeIfPresent(start, forKey: .start)
        try c.encodeIfPresent(end, forKey: .end)
    }

    /// Stops in draw order (ascending position), clamped to 0…1.
    var sortedStops: [GradientStop] {
        stops.map { GradientStop(id: $0.id, color: $0.color, position: min(1, max(0, $0.position))) }
            .sorted { $0.position < $1.position }
    }

    /// Linear start/end points within a rect: the explicit line when there is one,
    /// otherwise derived from the angle exactly as before.
    func linearPoints(in rect: CGRect) -> (CGPoint, CGPoint) {
        if let s = start, let e = end {
            return (CGPoint(x: rect.minX + s.x * rect.width, y: rect.minY + s.y * rect.height),
                    CGPoint(x: rect.minX + e.x * rect.width, y: rect.minY + e.y * rect.height))
        }
        return angleLinearPoints(in: rect)
    }

    /// The angle-derived line — CSS's own gradient-line construction: through the
    /// centre, long enough that the first and last stop cover the box corners.
    /// Kept separate because CSS export needs it as the REFERENCE line even when an
    /// explicit line is in play.
    func angleLinearPoints(in rect: CGRect) -> (CGPoint, CGPoint) {
        let a = angle * .pi / 180
        let dx = cos(a), dy = sin(a)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let half = (abs(rect.width * dx) + abs(rect.height * dy)) / 2
        return (CGPoint(x: c.x - dx * half, y: c.y - dy * half),
                CGPoint(x: c.x + dx * half, y: c.y + dy * half))
    }

    /// The drawn line as UNIT-space endpoints (0…1 of `rect`). Exact for both the
    /// explicit and the angle-derived case, which is what lets SVG state the line in
    /// objectBoundingBox units and still match the canvas.
    func unitLinearPoints(in rect: CGRect) -> (CGPoint, CGPoint) {
        if let s = start, let e = end { return (s, e) }
        let (p0, p1) = angleLinearPoints(in: rect)
        func unit(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.width  > 0 ? (p.x - rect.minX) / rect.width  : 0,
                    y: rect.height > 0 ? (p.y - rect.minY) / rect.height : 0)
        }
        return (unit(p0), unit(p1))
    }

    /// A copy whose line is `s`→`e` in unit space, with `angle` updated to match so
    /// the inspector field and every angle reader stay truthful. `rect` supplies the
    /// aspect the angle is measured in.
    func settingLine(start s: CGPoint, end e: CGPoint, in rect: CGRect) -> GradientFill {
        var g = self
        g.start = s
        g.end = e
        let dx = (e.x - s.x) * rect.width, dy = (e.y - s.y) * rect.height
        if abs(dx) > 1e-9 || abs(dy) > 1e-9 {
            var deg = atan2(dy, dx) * 180 / .pi
            if deg < 0 { deg += 360 }
            g.angle = deg
        }
        return g
    }

    /// A copy rotated to `newAngle`. When the gradient has an explicitly placed
    /// line, keep that line's midpoint and physical length and rotate it in place;
    /// otherwise the explicit endpoints would continue to win over `angle` and an
    /// Inspector edit would not change the canvas at all.
    func settingAngle(_ newAngle: Double, in rect: CGRect) -> GradientFill {
        var g = self
        let remainder = newAngle.truncatingRemainder(dividingBy: 360)
        let normalized = remainder < 0 ? remainder + 360 : remainder
        g.angle = normalized

        guard let s = start, let e = end,
              rect.width > 1e-9, rect.height > 1e-9 else { return g }

        let p0 = CGPoint(x: rect.minX + s.x * rect.width,
                         y: rect.minY + s.y * rect.height)
        let p1 = CGPoint(x: rect.minX + e.x * rect.width,
                         y: rect.minY + e.y * rect.height)
        let midpoint = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let halfLength = hypot(p1.x - p0.x, p1.y - p0.y) / 2
        let radians = normalized * .pi / 180
        let offset = CGPoint(x: cos(radians) * halfLength,
                             y: sin(radians) * halfLength)
        let newStart = CGPoint(x: midpoint.x - offset.x, y: midpoint.y - offset.y)
        let newEnd = CGPoint(x: midpoint.x + offset.x, y: midpoint.y + offset.y)
        g.start = CGPoint(x: (newStart.x - rect.minX) / rect.width,
                          y: (newStart.y - rect.minY) / rect.height)
        g.end = CGPoint(x: (newEnd.x - rect.minX) / rect.width,
                        y: (newEnd.y - rect.minY) / rect.height)
        return g
    }

    /// The colour the gradient shows at `t` along its line (0…1), interpolated in
    /// sRGB between the surrounding stops.
    ///
    /// FEAT-045 uses this when a click on the line adds a stop: the new stop starts
    /// as the colour that was already at that spot, so ADDING a stop never changes
    /// how the gradient looks. You then move or recolour it deliberately, which is
    /// the behaviour that makes clicking the line safe to do by accident.
    func color(at t: Double) -> RGBAColor {
        let s = sortedStops
        guard let first = s.first, let last = s.last else { return .black }
        if t <= Double(first.position) { return first.color }
        if t >= Double(last.position) { return last.color }
        for i in 1..<s.count {
            let lo = s[i - 1], hi = s[i]
            let p0 = Double(lo.position), p1 = Double(hi.position)
            guard t >= p0, t <= p1 else { continue }
            let f = (p1 - p0) > 1e-9 ? (t - p0) / (p1 - p0) : 0
            return RGBAColor(r: lo.color.r + (hi.color.r - lo.color.r) * f,
                             g: lo.color.g + (hi.color.g - lo.color.g) * f,
                             b: lo.color.b + (hi.color.b - lo.color.b) * f,
                             a: lo.color.a + (hi.color.a - lo.color.a) * f)
        }
        return last.color
    }

    /// Stop positions remapped onto the CSS gradient line.
    ///
    /// CSS `linear-gradient(<deg>, …)` always sweeps the FULL angle-derived line, so
    /// an explicit start offset or a shortened line has no direct syntax. It does
    /// have an exact equivalent though: both lines are parallel, so projecting the
    /// explicit line onto the CSS one turns offset and length into stop percentages
    /// (which CSS permits outside 0–100%). Without an explicit line this returns the
    /// stops unchanged, so ordinary gradients export byte-for-byte as before.
    func cssStopPositions(in rect: CGRect) -> [(color: RGBAColor, position: Double)] {
        let ordered = sortedStops
        guard kind == .linear, start != nil, end != nil else {
            return ordered.map { (color: $0.color, position: Double($0.position)) }
        }
        let (p0, p1) = angleLinearPoints(in: rect)
        let lx = p1.x - p0.x, ly = p1.y - p0.y
        let length2 = lx * lx + ly * ly
        guard length2 > 1e-9 else {
            return ordered.map { (color: $0.color, position: Double($0.position)) }
        }
        let (s, e) = linearPoints(in: rect)
        // Projection of a point onto the CSS line, as a fraction of its length.
        func t(_ p: CGPoint) -> Double {
            Double(((p.x - p0.x) * lx + (p.y - p0.y) * ly) / length2)
        }
        let a = t(s), b = t(e) - t(s)
        return ordered.map { (color: $0.color, position: a + Double($0.position) * b) }
    }
}

/// A shape fill / artboard background: flat color or gradient.
enum Paint: Codable, Equatable, Sendable {
    case solid(RGBAColor)
    case gradient(GradientFill)

    /// A single representative color (the solid value, or the first stop) — used
    /// where one color is needed (swatches, solid overrides, fallbacks).
    var representativeColor: RGBAColor {
        switch self {
        case .solid(let c): return c
        case .gradient(let g): return g.sortedStops.first?.color ?? .white
        }
    }
    var isGradient: Bool { if case .gradient = self { return true }; return false }
    var gradientValue: GradientFill? { if case .gradient(let g) = self { return g }; return nil }

    static let white = Paint.solid(.white)
    static let black = Paint.solid(.black)
    static let clear = Paint.solid(.clear)

    // MARK: Codable (flat = bare RGBAColor; gradient = tagged)

    private enum CodingKeys: String, CodingKey { case kind, gradient }

    init(from decoder: Decoder) throws {
        // Legacy / flat: a bare {r,g,b,a} object decodes as RGBAColor.
        if let c = try? RGBAColor(from: decoder) { self = .solid(c); return }
        let ct = try decoder.container(keyedBy: CodingKeys.self)
        if (try? ct.decodeIfPresent(String.self, forKey: .kind)) == "gradient",
           let g = try? ct.decode(GradientFill.self, forKey: .gradient) {
            self = .gradient(g)
        } else {
            self = .solid(.white)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .solid(let c):
            try c.encode(to: encoder)        // bare RGBAColor → unchanged on disk
        case .gradient(let g):
            var ct = encoder.container(keyedBy: CodingKeys.self)
            try ct.encode("gradient", forKey: .kind)
            try ct.encode(g, forKey: .gradient)
        }
    }
}
