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
/// linear is driven by `angle` (degrees, y-down: 0 = →, 90 = ↓); radial is
/// centered with a radius to the box corner. (On-canvas handles come later.)
struct GradientFill: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case linear, radial }

    var kind: Kind = .linear
    var stops: [GradientStop] = [
        GradientStop(color: .white, position: 0),
        GradientStop(color: .black, position: 1)
    ]
    var angle: Double = 90

    /// Stops in draw order (ascending position), clamped to 0…1.
    var sortedStops: [GradientStop] {
        stops.map { GradientStop(id: $0.id, color: $0.color, position: min(1, max(0, $0.position))) }
            .sorted { $0.position < $1.position }
    }

    /// Linear start/end points within a rect, derived from the angle.
    func linearPoints(in rect: CGRect) -> (CGPoint, CGPoint) {
        let a = angle * .pi / 180
        let dx = cos(a), dy = sin(a)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let half = (abs(rect.width * dx) + abs(rect.height * dy)) / 2
        return (CGPoint(x: c.x - dx * half, y: c.y - dy * half),
                CGPoint(x: c.x + dx * half, y: c.y + dy * half))
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
