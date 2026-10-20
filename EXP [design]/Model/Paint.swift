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

/// Optional radial geometry in fractions of the fill's bounds.
struct RadialGradientGeometry: Codable,Equatable,Sendable {
    var center: CGPoint
    var radius: CGSize
    var isValid: Bool {
        [center.x,center.y,radius.width,radius.height].allSatisfy(\.isFinite)
            && (-2...3).contains(center.x) && (-2...3).contains(center.y)
            && radius.width > 0 && radius.height > 0 && radius.width <= 1_000_000 && radius.height <= 1_000_000
    }
}

/// Linear uses an angle or explicit line; radial keeps its legacy centered
/// circle until editable center/elliptical radii are authored.
struct GradientFill: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case linear, radial }

    var kind: Kind = .linear
    var stops: [GradientStop] = [
        GradientStop(color: .white, position: 0),
        GradientStop(color: .black, position: 1)
    ]
    var angle: Double = 90
    /// nil retains the original centered circular gradient, including old files.
    var radial: RadialGradientGeometry? = nil

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

    enum CodingKeys: String, CodingKey { case kind, stops, angle, start, end, radial }

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
        radial = try c.decodeIfPresent(RadialGradientGeometry.self,forKey: .radial)
        if let radial,!radial.isValid { throw DecodingError.dataCorruptedError(forKey: .radial,in: c,debugDescription: "Invalid radial geometry") }
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
        try c.encodeIfPresent(radial,forKey: .radial)
    }

    /// Center/radii in unit box coordinates. The implicit default reproduces
    /// the previous circle-to-corner paint exactly on every aspect ratio.
    func radialGeometry(in rect: CGRect) -> RadialGradientGeometry {
        if let radial,radial.isValid { return radial }
        let radius = max(1,hypot(rect.width,rect.height)/2)
        return RadialGradientGeometry(center: CGPoint(x: 0.5,y: 0.5),
            radius: CGSize(width: radius/max(0.001,rect.width),height: radius/max(0.001,rect.height)))
    }
    func radialCSS(stops: String) -> String {
        guard let radial,radial.isValid else { return "radial-gradient(circle, \(stops))" }
        return "radial-gradient(ellipse \(radial.radius.width*100)% \(radial.radius.height*100)% at \(radial.center.x*100)% \(radial.center.y*100)%, \(stops))"
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

enum PatternAnchor: String, Codable, Sendable { case document, shape }

/// A per-fill anchor and the frozen conversion basis for imported SVG fractions.
/// Tile artwork/size still live on the shared source; resizing a layer does not
/// change this basis. Older references omit placement and retain SVG semantics.
struct PatternPlacement: Codable, Equatable, Sendable {
    let anchor: PatternAnchor
    let referenceSize: CGSize
    var offset: CGPoint = .zero
    init(anchor: PatternAnchor, referenceSize: CGSize, offset: CGPoint = .zero) {
        self.anchor = anchor; self.referenceSize = referenceSize; self.offset = offset
    }
    private enum CodingKeys: String, CodingKey { case anchor, referenceSize, offset }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        anchor = try c.decode(PatternAnchor.self,forKey: .anchor)
        referenceSize = try c.decode(CGSize.self,forKey: .referenceSize)
        offset = try c.decodeIfPresent(CGPoint.self,forKey: .offset) ?? .zero
        guard referenceSize.width.isFinite,referenceSize.height.isFinite,
              referenceSize.width > 0,referenceSize.height > 0,offset.x.isFinite,offset.y.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .referenceSize,in: c,debugDescription: "Pattern reference size must be positive and finite.")
        }
    }
}

/// A fill that paints a repeating tile from the document's pattern library
/// (FEAT-062).
///
/// Deliberately a REFERENCE, not the artwork itself. The tile lives once in
/// `Document.patterns` as a `PatternSource`, exactly as a component's artwork
/// lives once in `Document.sources` — so one pattern can back many layers,
/// editing the tile updates every use, matching placement/scale fills share an
/// SVG `<pattern>`, and `Paint` stays a small Equatable
/// value type instead of becoming recursive (Paint → Node → Paint).
struct PatternRef: Codable, Equatable, Sendable {
    var patternID: UUID
    var placement: PatternPlacement? = nil
    /// Painted when the pattern cannot be resolved — a missing id, a document
    /// opened by an older build, a library that failed to load. Never optional:
    /// a fill must always be able to paint SOMETHING, and inventing a silent
    /// black for an unresolvable reference is precisely the failure this feature
    /// exists to remove. Importers should set this to a representative color
    /// sampled from the tile, so a degraded render is at least plausible.
    var fallback: RGBAColor

    /// Per-paint repeat size; the shared source and lattice anchor stay unchanged.
    var scale: CGFloat {
        didSet { scale = Self.boundedScale(scale) }
    }
    static func boundedScale(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(100,max(0.01,value)) : 1
    }
    init(patternID: UUID, fallback: RGBAColor = .clear, scale: CGFloat = 1) {
        self.patternID = patternID
        self.fallback = fallback
        self.scale = Self.boundedScale(scale)
    }
    private enum CodingKeys: String, CodingKey { case patternID, fallback, scale, placement }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        patternID = try c.decode(UUID.self,forKey: .patternID)
        placement = try c.decodeIfPresent(PatternPlacement.self,forKey: .placement)
        fallback = try c.decode(RGBAColor.self,forKey: .fallback)
        scale = try c.decodeIfPresent(CGFloat.self,forKey: .scale) ?? 1
        guard scale.isFinite, (0.01...100).contains(scale) else {
            throw DecodingError.dataCorruptedError(forKey: .scale,in: c,debugDescription: "Pattern scale must be 0.01 through 100.")
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(patternID,forKey: .patternID)
        try c.encodeIfPresent(placement,forKey: .placement)
        try c.encode(fallback,forKey: .fallback)
        if scale != 1 { try c.encode(scale,forKey: .scale) }
    }

}

enum Paint: Codable, Equatable, Sendable {
    case solid(RGBAColor)
    case gradient(GradientFill)
    case pattern(PatternRef)
    case mesh(MeshFill)

    /// A single representative color (the solid value, or the first stop) — used
    /// where one color is needed (swatches, solid overrides, fallbacks).
    var representativeColor: RGBAColor {
        switch self {
        case .solid(let c): return c
        case .gradient(let g): return g.sortedStops.first?.color ?? .white
        case .mesh(let m): return m.base
        case .pattern(let p): return p.fallback
        }
    }
    var isGradient: Bool { if case .gradient = self { return true }; return false }
    var gradientValue: GradientFill? { if case .gradient(let g) = self { return g }; return nil }
    var meshValue: MeshFill? { if case .mesh(let m) = self { return m }; return nil }
    var isMesh: Bool { meshValue != nil }
    var isPattern: Bool { if case .pattern = self { return true }; return false }
    var patternValue: PatternRef? { if case .pattern(let p) = self { return p }; return nil }

    static let white = Paint.solid(.white)
    static let black = Paint.solid(.black)
    static let clear = Paint.solid(.clear)

    // MARK: Codable (flat = bare RGBAColor; gradient = tagged)

    private enum CodingKeys: String, CodingKey { case kind, gradient, pattern, mesh }

    init(from decoder: Decoder) throws {
        // Legacy / flat: a bare {r,g,b,a} object decodes as RGBAColor.
        if let c = try? RGBAColor(from: decoder) { self = .solid(c); return }
        let ct = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? ct.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        if kind == "mesh" { self = .mesh(try ct.decode(MeshFill.self, forKey: .mesh)); return }
        if kind == "gradient", let g = try? ct.decode(GradientFill.self, forKey: .gradient) {
            self = .gradient(g)
        } else if kind == "pattern", let p = try? ct.decode(PatternRef.self, forKey: .pattern) {
            self = .pattern(p)
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
        case .mesh(let m):
            var ct = encoder.container(keyedBy: CodingKeys.self)
            try ct.encode("mesh",forKey: .kind); try ct.encode(m,forKey: .mesh)
        case .pattern(let p):
            // An older build reading this falls through the decoder's unknown-kind
            // branch to `.solid(.white)` rather than throwing, so a v2.5 document
            // still OPENS in v2.4 — degraded, never bricked.
            var ct = encoder.container(keyedBy: CodingKeys.self)
            try ct.encode("pattern", forKey: .kind)
            try ct.encode(p, forKey: .pattern)
        }
    }
}

/// FEAT-033: an ordered stack of elliptical radial colors over a base. Unit-space
/// radius scales independently with carrier width/height (CSS ellipse / SVG bbox).
/// This is a layered-radial fill, not a Bézier patch mesh.
struct MeshPoint: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var position: CGPoint
    var radius: Double
    var color: RGBAColor
    var opacity: Double = 1
}

struct MeshFill: Codable, Equatable, Sendable {
    static let maximumPoints = 8
    var base: RGBAColor
    /// Back to front; CSS reverses this order because its first image is on top.
    var points: [MeshPoint]
    var version = 1

    static func seeded(base: RGBAColor) -> Self {
        MeshFill(base: base,points: [
            MeshPoint(position: CGPoint(x: 0.25,y: 0.25),radius: 0.8,color: RGBAColor(r: 1,g: 0.05,b: 0.4,a: 1)),
            MeshPoint(position: CGPoint(x: 0.8,y: 0.7),radius: 0.85,color: RGBAColor(r: 0,g: 0.8,b: 1,a: 1))])
    }
    enum ValidationError: Error { case invalidData }
    private enum CodingKeys: String, CodingKey { case version, base, points }
    init(base: RGBAColor, points: [MeshPoint] = []) { self.base = base; self.points = points }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        base = try c.decode(RGBAColor.self, forKey: .base)
        points = try c.decode([MeshPoint].self, forKey: .points)
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version,forKey: .version)
        try c.encode(base,forKey: .base)
        try c.encode(points,forKey: .points)
    }
    func validate() throws {
        func validColor(_ c: RGBAColor) -> Bool {
            [c.r,c.g,c.b,c.a].allSatisfy { $0.isFinite && (0...1).contains($0) }
        }
        guard version == 1, validColor(base), points.count <= Self.maximumPoints,
              Set(points.map(\.id)).count == points.count,
              points.allSatisfy({ p in
                  p.position.x.isFinite && p.position.y.isFinite &&
                  (-2...3).contains(p.position.x) && (-2...3).contains(p.position.y) &&
                  p.radius.isFinite && (0.005...4).contains(p.radius) && validColor(p.color) &&
                  p.opacity.isFinite && (0...1).contains(p.opacity)
              }) else { throw ValidationError.invalidData }
    }
    /// Strict, bounded, data-only metadata. No paths, markup, CSS or URLs execute.
    func metadata() throws -> String {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self).base64EncodedString()
    }
    static func fromMetadata(_ value: String) throws -> Self {
        guard value.utf8.count <= 24_000, let data = Data(base64Encoded: value), data.count <= 16_000 else {
            throw ValidationError.invalidData
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
    /// Standards-readable CSS background shorthand, with exact sRGB channel
    /// values. Each point fades to its SAME RGB at zero alpha (no dark fringe).
    func cssBackground() throws -> String {
        try validate()
        func color(_ c: RGBAColor, _ opacity: Double = 1) -> String {
            "rgba(\(c.r * 255), \(c.g * 255), \(c.b * 255), \(c.a * opacity))"
        }
        let layers = points.reversed().map { p in
            "radial-gradient(ellipse \(p.radius * 100)% \(p.radius * 100)% at \(p.position.x * 100)% \(p.position.y * 100)%, \(color(p.color,p.opacity)) 0%, \(color(p.color,0)) 100%)"
        }
        return (layers + [color(base)]).joined(separator: ", ")
    }
    func cssDeclarations() throws -> String {
        "background: \(try cssBackground()); --exp-mesh-v1: \"\(try metadata())\";"
    }
    /// A unit-space pattern is a paint server, so the same mesh works for fills,
    /// backgrounds and stroke outlines without duplicating carrier geometry.
    /// App exports place the unit tile in the logical editing frame explicitly,
    /// so curved ink bounds cannot move its points. Metadata is data-only.
    func svgPattern(id: UUID) throws -> (id: String, definition: String) {
        try validate()
        return try svgPattern(name: "mesh" + id.uuidString.replacingOccurrences(of: "-", with: "").lowercased())
    }
    func svgPattern(name: String, bounds: CGRect? = nil) throws -> (id: String, definition: String) {
        try validate()
        guard name.count <= 100, name.first?.isLetter == true,
              name.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw ValidationError.invalidData }
        func rgb(_ c: RGBAColor) -> String { "rgb(\(c.r * 255),\(c.g * 255),\(c.b * 255))" }
        var defs = "", layers = "<rect width=\"1\" height=\"1\" fill=\"\(rgb(base))\" fill-opacity=\"\(base.a)\"/>"
        for (i,p) in points.enumerated() {
            let gradient = name + "p\(i)"
            defs += "<radialGradient id=\"\(gradient)\" cx=\"\(p.position.x)\" cy=\"\(p.position.y)\" r=\"\(p.radius)\" color-interpolation=\"sRGB\"><stop offset=\"0\" stop-color=\"\(rgb(p.color))\" stop-opacity=\"\(p.color.a * p.opacity)\"/><stop offset=\"1\" stop-color=\"\(rgb(p.color))\" stop-opacity=\"0\"/></radialGradient>"
            layers += "<rect width=\"1\" height=\"1\" fill=\"url(#\(gradient))\"/>"
        }
        let placement: String
        if let bounds {
            guard [bounds.minX,bounds.minY,bounds.width,bounds.height].allSatisfy({ $0.isFinite }),
                  bounds.width > 0,bounds.height > 0 else { throw ValidationError.invalidData }
            placement = "patternUnits=\"userSpaceOnUse\" x=\"\(bounds.minX)\" y=\"\(bounds.minY)\" width=\"\(bounds.width)\" height=\"\(bounds.height)\""
        } else { placement = "patternUnits=\"objectBoundingBox\" width=\"1\" height=\"1\"" }
        let metadata = try metadata()
        return (name, defs + "<pattern id=\"\(name)\" \(placement) viewBox=\"0 0 1 1\" preserveAspectRatio=\"none\" data-exp-mesh-v1=\"\(metadata)\">\(layers)</pattern>")
    }
}
