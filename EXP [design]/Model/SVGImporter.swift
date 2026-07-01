//
//  SVGImporter.swift
//  EXP [design]
//
//  Imports an SVG file as EDITABLE native layers (not a flattened raster):
//   • <g> → groups (nesting preserved); transforms are baked into child geometry
//   • <path> / <polyline> / <polygon> → editable Path layers
//   • <rect> / <circle> / <ellipse> → Rectangle/Ellipse layers when the transform
//     is axis-aligned, else a Path
//   • <line> → Line layer
//   • <text> → Text layer (basic: position, size, family, weight/style, fill)
//   • fills: solid colors + <linearGradient>/<radialGradient> (objectBoundingBox);
//     stroke, stroke-width, opacity/fill-opacity/stroke-opacity
//   • viewBox → width/height scaling
//
//  Unsupported features are skipped; if nothing parses, the caller raster-falls
//  back. Coordinates are SVG user units (y-down — same as our document space).
//

import Foundation
import CoreGraphics

enum SVGImporter {

    /// Parse SVG `data` into a single group Node (children in group-local coords),
    /// with frame origin at (0,0). nil if it isn't usable SVG / produced nothing.
    static func importGroup(from data: Data) -> Node? {
        guard let doc = try? XMLDocument(data: data, options: [.documentTidyXML]),
              let root = doc.rootElement(), root.name == "svg" else { return nil }

        var ctx = Context()
        collectGradients(in: root, into: &ctx)

        // viewBox → target size mapping (so 1 user unit ≈ 1 doc point at the
        // declared width/height).
        let size = canvasSize(root)
        var ctm = CGAffineTransform.identity
        if let vb = viewBox(root) {
            let sx = size.width / (vb.width == 0 ? size.width : vb.width)
            let sy = size.height / (vb.height == 0 ? size.height : vb.height)
            ctm = CGAffineTransform(translationX: -vb.minX * sx, y: -vb.minY * sy)
                .scaledBy(x: sx, y: sy)
        }

        var children: [Node] = []
        for child in root.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            children.append(contentsOf: nodes(for: child, ctm: ctm, inherited: Style(), ctx: ctx))
        }
        guard !children.isEmpty else { return nil }

        // Localize children into a group at (0,0,size).
        let group = Node(name: "SVG", frame: CGRect(origin: .zero, size: size),
                         content: .group(children: children))
        return group
    }

    // MARK: Parsing context

    private struct Context { var gradients: [String: GradientFill] = [:] }

    /// Resolved presentation style as it flows down the tree.
    private struct Style {
        var fill: Paint? = .solid(.black)   // SVG default fill is black
        var stroke: RGBAColor? = nil
        var strokeWidth: CGFloat = 1
        var opacity: Double = 1
        var fillOpacity: Double = 1
        var strokeOpacity: Double = 1
        var fontSize: CGFloat = 16
        var fontFamily: String = ""
        var bold = false
        var italic = false
        
        var resolvedFill: Paint { fill ?? .clear }
    }

    // MARK: Element → nodes

    private static func nodes(for el: XMLElement, ctm parentCTM: CGAffineTransform,
                              inherited: Style, ctx: Context) -> [Node] {
        // A child point maps as parentCTM(elementTransform(point)).
        let local = transform(el).concatenating(parentCTM)
        let style = resolveStyle(el, inherited: inherited, ctx: ctx)
        let name = el.name ?? ""

        switch name {
        case "g", "svg", "a":
            var kids: [Node] = []
            for c in el.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                kids.append(contentsOf: nodes(for: c, ctm: local, inherited: style, ctx: ctx))
            }
            guard !kids.isEmpty else { return [] }
            return [groupNode(kids, name: el.attribute(forName: "id")?.stringValue ?? "Group")]

        case "path":
            guard let d = el.attribute(forName: "d")?.stringValue else { return [] }
            let parsed = SVGPath.parse(d)
            let subs = parsed.map { $0.points.map { transformPoint($0, local) } }
            guard !subs.isEmpty else { return [] }
            return pathNode(subs, style: style, name: "Path", closed: parsed.first?.closed ?? false)

        case "rect":
            return rectNode(el, ctm: local, style: style)
        case "circle", "ellipse":
            return ellipseNode(el, ctm: local, style: style, isCircle: name == "circle")
        case "line":
            let a = transformPoint(.init(point: pt(el, "x1", "y1")), local)
            let b = transformPoint(.init(point: pt(el, "x2", "y2")), local)
            return lineNode(a.point, b.point, style: style)
        case "polyline", "polygon":
            let pts = numbers(el.attribute(forName: "points")?.stringValue ?? "")
            var sub: [PathPoint] = []
            var i = 0
            while i + 1 < pts.count { sub.append(transformPoint(.init(point: CGPoint(x: pts[i], y: pts[i+1])), local)); i += 2 }
            guard sub.count >= 2 else { return [] }
            return pathNode([sub], style: style, name: name == "polygon" ? "Polygon" : "Polyline",
                            closed: name == "polygon")
        case "text":
            return textNode(el, ctm: local, style: style)
        default:
            // Recurse into unknown containers (e.g. <switch>) but skip <defs>.
            if name == "defs" || name == "linearGradient" || name == "radialGradient" { return [] }
            var kids: [Node] = []
            for c in el.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                kids.append(contentsOf: nodes(for: c, ctm: local, inherited: style, ctx: ctx))
            }
            return kids
        }
    }

    // MARK: Node builders

    private static func groupNode(_ children: [Node], name: String) -> Node {
        let bounds = children.map(\.frame).reduce(children[0].frame) { $0.union($1) }
        let local = children.map { n -> Node in
            var c = n; c.frame.origin = CGPoint(x: n.frame.minX - bounds.minX, y: n.frame.minY - bounds.minY); return c
        }
        return Node(name: name, frame: bounds, content: .group(children: local))
    }

    private static func pathNode(_ subpaths: [[PathPoint]], style: Style, name: String,
                                 closed: Bool) -> [Node] {
        let all = subpaths.flatMap { $0 }
        guard !all.isEmpty else { return [] }
        let bounds = pointsBounds(all)
        // Localize every point + control to the node frame.
        let localized = subpaths.map { $0.map { localize($0, by: bounds.origin) } }
        var ps = PathShape(points: localized[0], closed: closed,
                           fill: style.resolvedFill, stroke: style.stroke ?? .clear,
                           strokeWidth: style.stroke == nil ? 0 : style.strokeWidth)
        if localized.count > 1 { ps.contours = localized }
        var node = Node(name: name, frame: bounds, content: .path(ps))
        node.opacity = style.opacity
        return [node]
    }

    private static func rectNode(_ el: XMLElement, ctm: CGAffineTransform, style: Style) -> [Node] {
        let x = num(el, "x"), y = num(el, "y"), w = num(el, "width"), h = num(el, "height")
        guard w > 0, h > 0 else { return [] }
        let rx = max(num(el, "rx"), num(el, "ry"))
        if isAxisAligned(ctm) {
            let r = CGRect(x: x, y: y, width: w, height: h).applying(ctm).standardized
            let sx = scaleX(ctm)
            let shape = RectangleShape(fill: style.resolvedFill, cornerRadius: rx * abs(sx),
                                       stroke: style.stroke ?? .clear,
                                       strokeWidth: style.stroke == nil ? 0 : style.strokeWidth)
            var node = Node(name: "Rectangle", frame: r, content: .rectangle(shape))
            node.opacity = style.opacity
            return [node]
        }
        // Rotated/skewed → path of 4 corners.
        let corners = [CGPoint(x: x, y: y), CGPoint(x: x+w, y: y), CGPoint(x: x+w, y: y+h), CGPoint(x: x, y: y+h)]
        let sub = corners.map { transformPoint(.init(point: $0), ctm) }
        return pathNode([sub], style: style, name: "Rectangle", closed: true)
    }

    private static func ellipseNode(_ el: XMLElement, ctm: CGAffineTransform, style: Style, isCircle: Bool) -> [Node] {
        let cx = num(el, "cx"), cy = num(el, "cy")
        let rx = isCircle ? num(el, "r") : num(el, "rx")
        let ry = isCircle ? num(el, "r") : num(el, "ry")
        guard rx > 0, ry > 0 else { return [] }
        let box = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
        if isAxisAligned(ctm) {
            let r = box.applying(ctm).standardized
            let shape = EllipseShape(fill: style.resolvedFill, stroke: style.stroke ?? .clear,
                                     strokeWidth: style.stroke == nil ? 0 : style.strokeWidth)
            var node = Node(name: isCircle ? "Circle" : "Ellipse", frame: r, content: .ellipse(shape))
            node.opacity = style.opacity
            return [node]
        }
        // Rotated → 4-point bézier ellipse.
        let k: CGFloat = 0.5523
        let pts: [PathPoint] = [
            PathPoint(point: CGPoint(x: cx, y: cy - ry), controlIn: CGPoint(x: cx - rx*k, y: cy - ry), controlOut: CGPoint(x: cx + rx*k, y: cy - ry)),
            PathPoint(point: CGPoint(x: cx + rx, y: cy), controlIn: CGPoint(x: cx + rx, y: cy - ry*k), controlOut: CGPoint(x: cx + rx, y: cy + ry*k)),
            PathPoint(point: CGPoint(x: cx, y: cy + ry), controlIn: CGPoint(x: cx + rx*k, y: cy + ry), controlOut: CGPoint(x: cx - rx*k, y: cy + ry)),
            PathPoint(point: CGPoint(x: cx - rx, y: cy), controlIn: CGPoint(x: cx - rx, y: cy + ry*k), controlOut: CGPoint(x: cx - rx, y: cy - ry*k))
        ]
        return pathNode([pts.map { transformPoint($0, ctm) }], style: style, name: "Ellipse", closed: true)
    }

    private static func lineNode(_ a: CGPoint, _ b: CGPoint, style: Style) -> [Node] {
        let minX = min(a.x, b.x), minY = min(a.y, b.y)
        let frame = CGRect(x: minX, y: minY, width: max(1, abs(b.x - a.x)), height: max(1, abs(b.y - a.y)))
        let ls = LineShape(start: CGPoint(x: a.x - minX, y: a.y - minY),
                           end: CGPoint(x: b.x - minX, y: b.y - minY),
                           stroke: style.stroke ?? .black, strokeWidth: max(1, style.strokeWidth))
        var node = Node(name: "Line", frame: frame, content: .line(ls))
        node.opacity = style.opacity
        return [node]
    }

    private static func textNode(_ el: XMLElement, ctm: CGAffineTransform, style: Style) -> [Node] {
        let s = (el.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        let pos = pt(el, "x", "y").applying(ctm)
        let fs = style.fontSize * abs(scaleX(ctm))
        let runColor = style.fill?.representativeColor ?? .black
        let run = TextRun(string: s, fontName: style.fontFamily, fontSize: fs, color: runColor)
        var tc = TextContent(string: s, fontSize: fs, color: runColor, fontName: style.fontFamily)
        tc.runs = [run]
        // SVG y is the baseline; our frame origin is the top-left.
        let origin = CGPoint(x: pos.x, y: pos.y - fs * 0.8)
        var node = Node(name: s.count > 24 ? String(s.prefix(24)) : s,
                        frame: CGRect(origin: origin, size: tc.measuredSize()),
                        content: .text(tc))
        node.opacity = style.opacity
        return [node]
    }

    // MARK: Style resolution

    private static func resolveStyle(_ el: XMLElement, inherited: Style, ctx: Context) -> Style {
        var s = inherited
        var props: [String: String] = [:]
        // Presentation attributes.
        for key in ["fill", "stroke", "stroke-width", "opacity", "fill-opacity",
                    "stroke-opacity", "font-size", "font-family", "font-weight", "font-style"] {
            if let v = el.attribute(forName: key)?.stringValue { props[key] = v }
        }
        // style="" overrides presentation attributes.
        if let style = el.attribute(forName: "style")?.stringValue {
            for decl in style.split(separator: ";") {
                let kv = decl.split(separator: ":", maxSplits: 1)
                if kv.count == 2 { props[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces) }
            }
        }
        if let v = props["opacity"], let d = Double(v) { s.opacity = d }
        if let v = props["fill-opacity"], let d = Double(v) { s.fillOpacity = d }
        if let v = props["stroke-opacity"], let d = Double(v) { s.strokeOpacity = d }
        if let v = props["stroke-width"], let d = Double(v.replacingOccurrences(of: "px", with: "")) { s.strokeWidth = CGFloat(d) }
        if let v = props["font-size"], let d = Double(v.replacingOccurrences(of: "px", with: "")) { s.fontSize = CGFloat(d) }
        if let v = props["font-family"] { s.fontFamily = v.replacingOccurrences(of: "'", with: "").components(separatedBy: ",").first ?? "" }
        if let v = props["font-weight"] { s.bold = (v == "bold" || (Int(v) ?? 0) >= 600) }
        if let v = props["font-style"] { s.italic = (v == "italic" || v == "oblique") }
        if let v = props["fill"] { s.fill = paint(v, opacity: s.fillOpacity, ctx: ctx) }
        else if s.fill != nil, s.fillOpacity < 1 { s.fill = s.fill.map { withOpacity($0, s.fillOpacity) } }
        if let v = props["stroke"] {
            if v == "none" { s.stroke = nil } else { s.stroke = color(v).map { applyAlpha($0, s.strokeOpacity) } }
        }
        return s
    }

    private static func paint(_ value: String, opacity: Double, ctx: Context) -> Paint? {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v == "none" { return nil }
        if v.hasPrefix("url(") {
            let id = v.dropFirst(4).drop(while: { $0 == "#" }).prefix(while: { $0 != ")" && $0 != "#" })
            if let g = ctx.gradients[String(id)] { return .gradient(g) }
            return .solid(.black)
        }
        return color(v).map { .solid(applyAlpha($0, opacity)) }
    }

    private static func withOpacity(_ p: Paint, _ o: Double) -> Paint {
        if case .solid(let c) = p { return .solid(applyAlpha(c, o)) }
        return p
    }
    private static func applyAlpha(_ c: RGBAColor, _ o: Double) -> RGBAColor {
        RGBAColor(r: c.r, g: c.g, b: c.b, a: c.a * o)
    }

    // MARK: Gradients

    private static func collectGradients(in root: XMLElement, into ctx: inout Context) {
        guard let all = try? root.nodes(forXPath: "//*[local-name()='linearGradient' or local-name()='radialGradient']") else { return }
        for case let el as XMLElement in all {
            guard let id = el.attribute(forName: "id")?.stringValue else { continue }
            var g = GradientFill()
            g.kind = el.name == "radialGradient" ? .radial : .linear
            var stops: [GradientStop] = []
            for case let stop as XMLElement in (el.children ?? []) where stop.name == "stop" {
                var off = 0.0
                if let o = stop.attribute(forName: "offset")?.stringValue {
                    off = o.hasSuffix("%") ? (Double(o.dropLast()) ?? 0) / 100 : (Double(o) ?? 0)
                }
                var sc = RGBAColor.black; var sa = 1.0
                // stop-color / stop-opacity via attribute or style.
                var props: [String: String] = [:]
                if let c = stop.attribute(forName: "stop-color")?.stringValue { props["stop-color"] = c }
                if let a = stop.attribute(forName: "stop-opacity")?.stringValue { props["stop-opacity"] = a }
                if let style = stop.attribute(forName: "style")?.stringValue {
                    for decl in style.split(separator: ";") {
                        let kv = decl.split(separator: ":", maxSplits: 1)
                        if kv.count == 2 { props[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces) }
                    }
                }
                if let c = props["stop-color"], let parsed = color(c) { sc = parsed }
                if let a = props["stop-opacity"], let d = Double(a) { sa = d }
                stops.append(GradientStop(color: applyAlpha(sc, sa), position: off))
            }
            if stops.count >= 1 { g.stops = stops.count == 1 ? [stops[0], stops[0]] : stops }
            // Linear direction → our angle (y-down). objectBoundingBox default.
            if g.kind == .linear {
                let x1 = frac(el, "x1", 0), y1 = frac(el, "y1", 0)
                let x2 = frac(el, "x2", 1), y2 = frac(el, "y2", 0)
                g.angle = atan2(y2 - y1, x2 - x1) * 180 / .pi
            }
            ctx.gradients[id] = g
        }
    }

    private static func frac(_ el: XMLElement, _ name: String, _ dflt: Double) -> Double {
        guard let v = el.attribute(forName: name)?.stringValue else { return dflt }
        if v.hasSuffix("%") { return (Double(v.dropLast()) ?? dflt*100) / 100 }
        return Double(v) ?? dflt
    }

    // MARK: Transforms

    private static func transform(_ el: XMLElement) -> CGAffineTransform {
        guard let scanner = el.attribute(forName: "transform")?.stringValue else { return .identity }
        // funcName(args) funcName(args) …  — applied left to right (each later
        // transform is more local, so it's prepended into the running matrix).
        var result = CGAffineTransform.identity
        var idx = scanner.startIndex
        while idx < scanner.endIndex {
            guard let open = scanner[idx...].firstIndex(of: "(") else { break }
            let fn = scanner[idx..<open].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
            guard let close = scanner[open...].firstIndex(of: ")") else { break }
            let args = numbers(String(scanner[scanner.index(after: open)..<close]))
            switch fn {
            case "translate": result = result.translatedBy(x: args.first ?? 0, y: args.count > 1 ? args[1] : 0)
            case "scale":      result = result.scaledBy(x: args.first ?? 1, y: args.count > 1 ? args[1] : (args.first ?? 1))
            case "rotate":
                if args.count >= 3 {
                    result = result.translatedBy(x: args[1], y: args[2]).rotated(by: args[0] * .pi/180).translatedBy(x: -args[1], y: -args[2])
                } else { result = result.rotated(by: (args.first ?? 0) * .pi/180) }
            case "matrix": if args.count == 6 { result = CGAffineTransform(a: args[0], b: args[1], c: args[2], d: args[3], tx: args[4], ty: args[5]).concatenating(result) }
            case "skewX": result = CGAffineTransform(a: 1, b: 0, c: tan((args.first ?? 0) * .pi/180), d: 1, tx: 0, ty: 0).concatenating(result)
            case "skewY": result = CGAffineTransform(a: 1, b: tan((args.first ?? 0) * .pi/180), c: 0, d: 1, tx: 0, ty: 0).concatenating(result)
            default: break
            }
            idx = scanner.index(after: close)
        }
        return result
    }

    private static func transformPoint(_ p: PathPoint, _ t: CGAffineTransform) -> PathPoint {
        PathPoint(point: p.point.applying(t),
                  controlIn: p.controlIn?.applying(t),
                  controlOut: p.controlOut?.applying(t))
    }
    private static func localize(_ p: PathPoint, by o: CGPoint) -> PathPoint {
        PathPoint(point: CGPoint(x: p.point.x - o.x, y: p.point.y - o.y),
                  controlIn: p.controlIn.map { CGPoint(x: $0.x - o.x, y: $0.y - o.y) },
                  controlOut: p.controlOut.map { CGPoint(x: $0.x - o.x, y: $0.y - o.y) })
    }
    private static func pointsBounds(_ pts: [PathPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude, minY = minX
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = maxX
        for p in pts {
            for q in [p.point, p.controlIn, p.controlOut].compactMap({ $0 }) {
                minX = min(minX, q.x); minY = min(minY, q.y); maxX = max(maxX, q.x); maxY = max(maxY, q.y)
            }
        }
        if minX > maxX { return .zero }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
    private static func isAxisAligned(_ t: CGAffineTransform) -> Bool { abs(t.b) < 1e-6 && abs(t.c) < 1e-6 }
    private static func scaleX(_ t: CGAffineTransform) -> CGFloat { (t.a*t.a + t.b*t.b).squareRoot() }

    // MARK: Attribute helpers

    private static func num(_ el: XMLElement, _ name: String) -> CGFloat {
        CGFloat(Double(el.attribute(forName: name)?.stringValue?.replacingOccurrences(of: "px", with: "") ?? "") ?? 0)
    }
    private static func pt(_ el: XMLElement, _ xn: String, _ yn: String) -> CGPoint { CGPoint(x: num(el, xn), y: num(el, yn)) }

    private static func canvasSize(_ root: XMLElement) -> CGSize {
        let w = num(root, "width"), h = num(root, "height")
        if w > 0, h > 0 { return CGSize(width: w, height: h) }
        if let vb = viewBox(root) { return vb.size }
        return CGSize(width: 100, height: 100)
    }
    private static func viewBox(_ root: XMLElement) -> CGRect? {
        let n = numbers(root.attribute(forName: "viewBox")?.stringValue ?? "")
        guard n.count == 4 else { return nil }
        return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
    }

    /// All signed decimals in a string (handles commas, spaces, exponents, -).
    private static func numbers(_ s: String) -> [CGFloat] {
        var out: [CGFloat] = []
        var cur = ""
        func flush() { if let d = Double(cur) { out.append(CGFloat(d)) }; cur = "" }
        for ch in s {
            if ch.isNumber || ch == "." || ch == "e" || ch == "E" { cur.append(ch) }
            else if ch == "-" || ch == "+" {
                if !cur.isEmpty, let last = cur.last, last != "e", last != "E" { flush() }
                cur.append(ch)
            } else { flush() }
        }
        flush()
        return out
    }

    // MARK: Color

    private static func color(_ raw: String) -> RGBAColor? {
        let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if v == "none" || v == "transparent" { return RGBAColor(r: 0, g: 0, b: 0, a: 0) }
        if v.hasPrefix("#") {
            let hex = String(v.dropFirst())
            func c(_ s: Substring) -> Double { Double(Int(s, radix: 16) ?? 0) / 255 }
            if hex.count == 3 {
                let r = String(repeating: hex[hex.startIndex], count: 2)
                let g = String(repeating: hex[hex.index(hex.startIndex, offsetBy: 1)], count: 2)
                let b = String(repeating: hex[hex.index(hex.startIndex, offsetBy: 2)], count: 2)
                return RGBAColor(r: c(Substring(r)), g: c(Substring(g)), b: c(Substring(b)), a: 1)
            }
            if hex.count >= 6 {
                let s = Array(hex)
                func h(_ i: Int) -> Double { Double(Int(String(s[i...i+1]), radix: 16) ?? 0) / 255 }
                let a = hex.count >= 8 ? h(6) : 1
                return RGBAColor(r: h(0), g: h(2), b: h(4), a: a)
            }
        }
        if v.hasPrefix("rgb") {
            let n = numbers(v)
            if n.count >= 3 {
                return RGBAColor(r: Double(n[0])/255, g: Double(n[1])/255, b: Double(n[2])/255,
                                 a: n.count >= 4 ? Double(n[3]) : 1)
            }
        }
        return Self.named[v]
    }

    private static let named: [String: RGBAColor] = [
        "black": .black, "white": .white, "red": RGBAColor(r: 1, g: 0, b: 0, a: 1),
        "green": RGBAColor(r: 0, g: 0.5, b: 0, a: 1), "blue": RGBAColor(r: 0, g: 0, b: 1, a: 1),
        "gray": RGBAColor(r: 0.5, g: 0.5, b: 0.5, a: 1), "grey": RGBAColor(r: 0.5, g: 0.5, b: 0.5, a: 1),
        "yellow": RGBAColor(r: 1, g: 1, b: 0, a: 1), "orange": RGBAColor(r: 1, g: 0.65, b: 0, a: 1),
        "purple": RGBAColor(r: 0.5, g: 0, b: 0.5, a: 1), "silver": RGBAColor(r: 0.75, g: 0.75, b: 0.75, a: 1)
    ]
}

// MARK: - SVG path "d" parser

enum SVGPath {
    struct Subpath { var points: [PathPoint]; var closed: Bool }

    static func parse(_ d: String) -> [Subpath] {
        var subs: [Subpath] = []
        var pts: [PathPoint] = []
        var cur = CGPoint.zero, start = CGPoint.zero
        var prevCubic: CGPoint?, prevQuad: CGPoint?
        let toks = tokenize(d)
        var i = 0

        func setOut(_ p: CGPoint) { if !pts.isEmpty { pts[pts.count - 1].controlOut = p } }
        func flush() { if pts.count >= 2 { subs.append(Subpath(points: pts, closed: false)) }; pts = [] }

        while i < toks.count {
            guard case .cmd(let raw) = toks[i] else { i += 1; continue }
            i += 1
            let rel = raw.isLowercase
            let cmd = Character(raw.uppercased())
            func take(_ n: Int) -> [CGFloat]? {
                guard i + n <= toks.count else { return nil }
                var out: [CGFloat] = []
                for k in i..<(i+n) { guard case .num(let v) = toks[k] else { return nil }; out.append(v) }
                i += n
                return out
            }
            func abs2(_ a: [CGFloat], _ j: Int) -> CGPoint {
                rel ? CGPoint(x: cur.x + a[j], y: cur.y + a[j+1]) : CGPoint(x: a[j], y: a[j+1])
            }

            switch cmd {
            case "M":
                guard let a = take(2) else { break }
                flush()
                cur = abs2(a, 0); start = cur
                pts = [PathPoint(point: cur)]; prevCubic = nil; prevQuad = nil
                while let p = take(2) { cur = abs2(p, 0); pts.append(PathPoint(point: cur)); prevCubic = nil; prevQuad = nil }
            case "L":
                while let p = take(2) { cur = abs2(p, 0); pts.append(PathPoint(point: cur)); prevCubic = nil; prevQuad = nil }
            case "H":
                while let p = take(1) { cur.x = rel ? cur.x + p[0] : p[0]; pts.append(PathPoint(point: cur)); prevCubic = nil; prevQuad = nil }
            case "V":
                while let p = take(1) { cur.y = rel ? cur.y + p[0] : p[0]; pts.append(PathPoint(point: cur)); prevCubic = nil; prevQuad = nil }
            case "C":
                while let p = take(6) {
                    let cp1 = abs2(p, 0), cp2 = abs2(p, 2), end = abs2(p, 4)
                    setOut(cp1); pts.append(PathPoint(point: end, controlIn: cp2))
                    cur = end; prevCubic = cp2; prevQuad = nil
                }
            case "S":
                while let p = take(4) {
                    let cp2 = abs2(p, 0), end = abs2(p, 2)
                    let cp1 = prevCubic.map { CGPoint(x: 2*cur.x - $0.x, y: 2*cur.y - $0.y) } ?? cur
                    setOut(cp1); pts.append(PathPoint(point: end, controlIn: cp2))
                    cur = end; prevCubic = cp2; prevQuad = nil
                }
            case "Q":
                while let p = take(4) {
                    let q = abs2(p, 0), end = abs2(p, 2)
                    setOut(CGPoint(x: cur.x + 2/3*(q.x-cur.x), y: cur.y + 2/3*(q.y-cur.y)))
                    pts.append(PathPoint(point: end, controlIn: CGPoint(x: end.x + 2/3*(q.x-end.x), y: end.y + 2/3*(q.y-end.y))))
                    cur = end; prevQuad = q; prevCubic = nil
                }
            case "T":
                while let p = take(2) {
                    let end = abs2(p, 0)
                    let q = prevQuad.map { CGPoint(x: 2*cur.x - $0.x, y: 2*cur.y - $0.y) } ?? cur
                    setOut(CGPoint(x: cur.x + 2/3*(q.x-cur.x), y: cur.y + 2/3*(q.y-cur.y)))
                    pts.append(PathPoint(point: end, controlIn: CGPoint(x: end.x + 2/3*(q.x-end.x), y: end.y + 2/3*(q.y-end.y))))
                    cur = end; prevQuad = q; prevCubic = nil
                }
            case "A":
                while let p = take(7) {
                    let end = rel ? CGPoint(x: cur.x + p[5], y: cur.y + p[6]) : CGPoint(x: p[5], y: p[6])
                    for s in arcToCubics(from: cur, rx: p[0], ry: p[1], xRotDeg: p[2],
                                         largeArc: p[3] != 0, sweep: p[4] != 0, to: end) {
                        setOut(s.cp1); pts.append(PathPoint(point: s.end, controlIn: s.cp2)); cur = s.end
                    }
                    prevCubic = nil; prevQuad = nil
                }
            case "Z":
                if !pts.isEmpty { subs.append(Subpath(points: pts, closed: true)) }
                cur = start; pts = [PathPoint(point: start)]; prevCubic = nil; prevQuad = nil
            default: break
            }
        }
        flush()
        return subs.filter { $0.points.count >= 2 }
    }

    private enum Tok { case cmd(Character); case num(CGFloat) }

    private static func tokenize(_ d: String) -> [Tok] {
        var toks: [Tok] = []
        var num = ""
        func flushNum() { if let v = Double(num) { toks.append(.num(CGFloat(v))) }; num = "" }
        let cmds = Set("MmLlHhVvCcSsQqTtAaZz")
        for ch in d {
            if cmds.contains(ch) { flushNum(); toks.append(.cmd(ch)) }
            else if ch.isNumber { num.append(ch) }
            else if ch == "." { if num.contains(".") { flushNum() }; num.append(ch) }
            else if ch == "e" || ch == "E" { num.append(ch) }
            else if ch == "-" || ch == "+" {
                if let l = num.last, l != "e", l != "E" { flushNum() }
                num.append(ch)
            } else { flushNum() }
        }
        flushNum()
        return toks
    }

    /// Endpoint-arc → cubic bézier segments (≤90° each). Standard SVG arc impl.
    private static func arcToCubics(from p0: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                                    xRotDeg: CGFloat, largeArc: Bool, sweep: Bool,
                                    to p1: CGPoint) -> [(cp1: CGPoint, cp2: CGPoint, end: CGPoint)] {
        var rx = Swift.abs(rxIn), ry = Swift.abs(ryIn)
        guard rx > 0, ry > 0, p0 != p1 else { return [(p1, p1, p1)] }
        let phi = xRotDeg * .pi / 180, cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosP*dx + sinP*dy, y1p = -sinP*dx + cosP*dy
        let lambda = (x1p*x1p)/(rx*rx) + (y1p*y1p)/(ry*ry)
        if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }
        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        var numr = rx*rx*ry*ry - rx*rx*y1p*y1p - ry*ry*x1p*x1p
        if numr < 0 { numr = 0 }
        let den = rx*rx*y1p*y1p + ry*ry*x1p*x1p
        let co = sign * (den == 0 ? 0 : (numr/den).squareRoot())
        let cxp = co * (rx*y1p/ry), cyp = co * (-ry*x1p/rx)
        let cx = cosP*cxp - sinP*cyp + (p0.x+p1.x)/2
        let cy = sinP*cxp + cosP*cyp + (p0.y+p1.y)/2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux*vx + uy*vy
            let len = (ux*ux+uy*uy).squareRoot() * (vx*vx+vy*vy).squareRoot()
            var a = acos(Swift.max(-1, Swift.min(1, len == 0 ? 1 : dot/len)))
            if ux*vy - uy*vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p-cxp)/rx, (y1p-cyp)/ry)
        var dtheta = angle((x1p-cxp)/rx, (y1p-cyp)/ry, (-x1p-cxp)/rx, (-y1p-cyp)/ry)
        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }
        let segs = Swift.max(1, Int(ceil(Swift.abs(dtheta) / (.pi/2))))
        let delta = dtheta / CGFloat(segs)
        let t = 4.0/3 * tan(delta/4)
        var out: [(CGPoint, CGPoint, CGPoint)] = []
        var a1 = theta1, startPt = p0
        func point(_ c: CGFloat, _ s: CGFloat) -> CGPoint {
            let ex = rx*c, ey = ry*s
            return CGPoint(x: cosP*ex - sinP*ey + cx, y: sinP*ex + cosP*ey + cy)
        }
        func deriv(_ c: CGFloat, _ s: CGFloat) -> CGPoint {
            let ex = -rx*s, ey = ry*c
            return CGPoint(x: cosP*ex - sinP*ey, y: sinP*ex + cosP*ey)
        }
        for _ in 0..<segs {
            let a2 = a1 + delta
            let end = point(cos(a2), sin(a2))
            let d1 = deriv(cos(a1), sin(a1)), d2 = deriv(cos(a2), sin(a2))
            out.append((CGPoint(x: startPt.x + t*d1.x, y: startPt.y + t*d1.y),
                        CGPoint(x: end.x - t*d2.x, y: end.y - t*d2.y), end))
            a1 = a2; startPt = end
        }
        return out
    }
}
