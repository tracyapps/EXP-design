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
        collectStylesheets(in: root, into: &ctx)
        collectGradients(in: root, into: &ctx)
        collectFilters(in: root, into: &ctx)

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

    private struct Context {
        var gradients: [String: GradientFill] = [:]
        /// `<filter id>` → the Effects we could reconstruct from its primitives
        /// (feTurbulence noise/dissolve chains, drop/inner shadow chains).
        var filters: [String: [Effect]] = [:]
        /// Ordered author rules from SVG `<style>` elements. Many Illustrator
        /// exports put every paint in `.cls-N` rules and leave only `class` on
        /// the geometry; without this cascade those shapes silently use SVG's
        /// initial black fill.
        var cssRules: [CSSRule] = []
    }

    private struct CSSRule {
        var selector: CSSSelector
        var declarations: [String: String]
        var sourceOrder: Int
    }

    /// A deliberately bounded CSS selector model for presentation styles in an
    /// SVG file. Compound element/id/class selectors cover the common output of
    /// Illustrator, Affinity, Sketch, and browser SVG exporters. Combinators,
    /// attribute selectors, and pseudo-classes are rejected instead of being
    /// approximated incorrectly.
    private struct CSSSelector {
        var element: String?
        var id: String?
        var classes: Set<String>

        var specificity: Int {
            (id == nil ? 0 : 100) + classes.count * 10 + (element == nil ? 0 : 1)
        }

        func matches(_ el: XMLElement) -> Bool {
            if let element, el.name?.lowercased() != element { return false }
            if let id, el.attribute(forName: "id")?.stringValue != id { return false }
            if !classes.isEmpty {
                let actual = Set((el.attribute(forName: "class")?.stringValue ?? "")
                    .split(whereSeparator: \Character.isWhitespace).map(String.init))
                if !classes.isSubset(of: actual) { return false }
            }
            return true
        }
    }

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
        var out = rawNodes(for: el, ctm: parentCTM, inherited: inherited, ctx: ctx)
        // filter="url(#…)" (attribute or style declaration) → re-attach any
        // effects we reconstructed from that filter's primitives.
        if let fx = filterEffects(el, ctx: ctx), !fx.isEmpty {
            out = out.map { n in
                var n = n
                n.effects.append(contentsOf: fx.map { var e = $0; e.id = UUID(); return e })
                return n
            }
        }
        return out
    }

    private static func rawNodes(for el: XMLElement, ctm parentCTM: CGAffineTransform,
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
            // SVG fills implicitly close every subpath, so a filled path with no
            // explicit `Z` still renders closed. Treat the path as closed when any
            // subpath is explicitly closed OR the style carries a real fill —
            // otherwise a filled icon exported without `Z` came in as an open,
            // unfilled stroke ("shape isn't closed" bug). A stroke-only path with
            // no fill stays open.
            let hasFill = !isClearPaint(style.resolvedFill)
            let closed = parsed.contains { $0.closed } || hasFill
            return pathNode(subs, style: style, name: "Path", closed: closed)

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
            if name == "defs" || name == "linearGradient" || name == "radialGradient" || name == "filter" { return [] }
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
        // stroke:none → width 0 with the MODEL-DEFAULT color, not a transparent
        // one: a clear color at width 0 is inert for rendering but lies in the
        // inspector, and bumping the width later would add an invisible stroke.
        var ps = PathShape(points: localized[0], closed: closed,
                           fill: style.resolvedFill, stroke: style.stroke ?? .black,
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
                                       stroke: style.stroke ?? .black,   // none → default color, width 0
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
            let shape = EllipseShape(fill: style.resolvedFill, stroke: style.stroke ?? .black,   // none → default color, width 0
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
        let props = resolvedProperties(for: el, ctx: ctx)
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

    private static let presentationAttributeKeys = [
        "fill", "stroke", "stroke-width", "opacity", "fill-opacity",
        "stroke-opacity", "font-size", "font-family", "font-weight", "font-style",
        "stop-color", "stop-opacity", "filter",
    ]

    /// SVG presentation attributes behave like zero-specificity CSS. Author
    /// stylesheet rules override them; an element's inline `style` wins last.
    /// Matching stylesheet rules are applied by specificity, then source order.
    private static func resolvedProperties(for el: XMLElement, ctx: Context) -> [String: String] {
        var props: [String: String] = [:]
        for key in presentationAttributeKeys {
            if let value = el.attribute(forName: key)?.stringValue { props[key] = value }
        }

        let matches = ctx.cssRules.filter { $0.selector.matches(el) }.sorted {
            let lhs = $0.selector.specificity, rhs = $1.selector.specificity
            return lhs == rhs ? $0.sourceOrder < $1.sourceOrder : lhs < rhs
        }
        for rule in matches {
            for (key, value) in rule.declarations { props[key] = value }
        }

        if let inline = el.attribute(forName: "style")?.stringValue {
            for (key, value) in cssDeclarations(inline) { props[key] = value }
        }
        return props
    }

    private static func collectStylesheets(in root: XMLElement, into ctx: inout Context) {
        guard let nodes = try? root.nodes(forXPath: "//*[local-name()='style']") else { return }
        let commentPattern = #"/\*.*?\*/"#
        let rulePattern = #"([^{}]+)\{([^{}]*)\}"#
        guard let comments = try? NSRegularExpression(pattern: commentPattern, options: [.dotMatchesLineSeparators]),
              let rules = try? NSRegularExpression(pattern: rulePattern, options: [.dotMatchesLineSeparators]) else { return }

        var order = ctx.cssRules.count
        for case let style as XMLElement in nodes {
            let raw = style.stringValue ?? ""
            let full = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            let css = comments.stringByReplacingMatches(in: raw, range: full, withTemplate: "")
            let ns = css as NSString
            for match in rules.matches(in: css, range: NSRange(location: 0, length: ns.length)) {
                let selectorList = ns.substring(with: match.range(at: 1))
                let declarations = cssDeclarations(ns.substring(with: match.range(at: 2)))
                guard !declarations.isEmpty else { continue }
                for rawSelector in selectorList.split(separator: ",") {
                    guard let selector = cssSelector(String(rawSelector)) else { continue }
                    ctx.cssRules.append(CSSRule(selector: selector,
                                                declarations: declarations,
                                                sourceOrder: order))
                    order += 1
                }
            }
        }
    }

    private static func cssDeclarations(_ body: String) -> [String: String] {
        var props: [String: String] = [:]
        for declaration in body.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.lowercased().hasSuffix("!important") {
                value = String(value.dropLast("!important".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !key.isEmpty, !value.isEmpty { props[key] = value }
        }
        return props
    }

    private static func cssSelector(_ raw: String) -> CSSSelector? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !text.contains(where: { $0.isWhitespace || ">+~[]:".contains($0) }) else { return nil }

        var selector = CSSSelector(element: nil, id: nil, classes: [])
        var index = text.startIndex
        if text[index] == "*" {
            index = text.index(after: index)
        } else if text[index] != ".", text[index] != "#" {
            let start = index
            while index < text.endIndex, isCSSIdentifierCharacter(text[index]) {
                index = text.index(after: index)
            }
            guard index > start else { return nil }
            selector.element = String(text[start..<index]).lowercased()
        }

        while index < text.endIndex {
            let marker = text[index]
            guard marker == "." || marker == "#" else { return nil }
            index = text.index(after: index)
            let start = index
            while index < text.endIndex, isCSSIdentifierCharacter(text[index]) {
                index = text.index(after: index)
            }
            guard index > start else { return nil }
            let name = String(text[start..<index])
            if marker == "." { selector.classes.insert(name) }
            else if selector.id == nil { selector.id = name }
            else { return nil }
        }
        return selector
    }

    private static func isCSSIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    private static func paint(_ value: String, opacity: Double, ctx: Context) -> Paint? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.lowercased() == "none" { return nil }
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
                // stop-color / stop-opacity via presentation attribute, class
                // stylesheet, or inline style (same cascade as normal layers).
                let props = resolvedProperties(for: stop, ctx: ctx)
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

    // MARK: Filters (feTurbulence noise / dissolve, shadow chains)

    /// Read `filter="url(#id)"` through the same presentation-attribute /
    /// stylesheet / inline-style cascade as paint, then reattach reconstructed
    /// effects (nil when none).
    private static func filterEffects(_ el: XMLElement, ctx: Context) -> [Effect]? {
        let raw = resolvedProperties(for: el, ctx: ctx)["filter"]
        guard let v = raw?.trimmingCharacters(in: .whitespaces), v.hasPrefix("url(") else { return nil }
        let id = v.dropFirst(4).drop(while: { $0 == "#" }).prefix(while: { $0 != ")" && $0 != "#" })
        return ctx.filters[String(id)]
    }

    /// Reconstruct Effects from every `<filter>` def we can understand. This is
    /// deliberately tolerant: it recognises the chains OUR exporter emits
    /// exactly, and degrades any other feTurbulence into a plain noise effect
    /// with that turbulence's parameters (so wild SVG textures still arrive as
    /// something editable rather than being dropped silently).
    private static func collectFilters(in root: XMLElement, into ctx: inout Context) {
        guard let all = try? root.nodes(forXPath: "//*[local-name()='filter']") else { return }
        for case let filt as XMLElement in all {
            guard let id = filt.attribute(forName: "id")?.stringValue else { continue }
            let prims = filt.children?.compactMap { $0 as? XMLElement } ?? []
            var effects: [Effect] = []

            func attr(_ el: XMLElement, _ n: String) -> String? { el.attribute(forName: n)?.stringValue }
            func dnum(_ el: XMLElement, _ n: String, _ dflt: Double) -> Double {
                attr(el, n).flatMap(Double.init) ?? dflt
            }
            /// The primitive consuming `result` as its `in` (linear-chain walk).
            func consumer(of result: String) -> XMLElement? {
                prims.first { attr($0, "in") == result }
            }

            // — feTurbulence chains → noise / dissolve —
            for turb in prims where turb.name == "feTurbulence" {
                var e = Effect(kind: .noise)
                e.turbulenceType = attr(turb, "type") == "turbulence" ? .turbulence : .fractalNoise
                // baseFrequency may be "x" or "x y"; take the first number.
                if let bf = attr(turb, "baseFrequency")?.split(separator: " ").first,
                   let f = Double(bf) { e.frequency = CGFloat(f) }
                e.octaves = Int(dnum(turb, "numOctaves", 1))
                e.seed = Int(dnum(turb, "seed", 0))
                e.monochrome = false
                e.amount = 0.35
                e.blend = .normal

                // Walk the chain this turbulence feeds.
                var cursor = attr(turb, "result")
                var hops = 0
                var sawThreshold = false
                while let r = cursor, let next = consumer(of: r), hops < 6 {
                    hops += 1
                    switch next.name {
                    case "feColorMatrix":
                        if let values = attr(next, "values") {
                            let nums = values.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { Double($0) }
                            if nums.count == 20 {
                                // Alpha row constant = amount; G'-from-R = monochrome.
                                e.amount = CGFloat(min(1, max(0, nums[19])))
                                e.monochrome = nums[5] == 1 && nums[6] == 0
                            }
                        }
                    case "feComponentTransfer":
                        // feFuncA linear slope/intercept ≈ step(threshold) → dissolve.
                        if let funcA = next.children?.compactMap({ $0 as? XMLElement }).first(where: { $0.name == "feFuncA" }),
                           attr(funcA, "type") == "linear" {
                            let slope = dnum(funcA, "slope", 1)
                            let intercept = dnum(funcA, "intercept", 0)
                            if slope != 0 {
                                e.kind = .dissolve
                                e.amount = CGFloat(min(1, max(0, (0.5 - intercept) / slope)))
                                e.monochrome = true
                                sawThreshold = true
                            }
                        }
                    case "feBlend":
                        if let mode = attr(next, "mode") { e.blend = blendFromCSS(mode) }
                    default:
                        break
                    }
                    cursor = attr(next, "result")
                }
                effects.append(e)
            }

            // — feOffset chains → drop / inner shadows (the exporter's shape) —
            for offset in prims where offset.name == "feOffset" {
                guard let inRef = attr(offset, "in"),
                      let blurEl = prims.first(where: { $0.name == "feGaussianBlur" && attr($0, "result") == inRef }),
                      let offResult = attr(offset, "result") else { continue }
                var e = Effect(kind: .dropShadow)
                e.dx = CGFloat(dnum(offset, "dx", 0))
                e.dy = CGFloat(dnum(offset, "dy", 0))
                e.blur = CGFloat(dnum(blurEl, "stdDeviation", 0) * 2)
                // Inner shadows knock the offset back out of the source.
                if prims.contains(where: { $0.name == "feComposite" && attr($0, "in2") == offResult && attr($0, "operator") == "out" }) {
                    e.kind = .innerShadow
                }
                // Spread came from a feMorphology feeding the blur.
                if let blurIn = attr(blurEl, "in"),
                   let morph = prims.first(where: { $0.name == "feMorphology" && attr($0, "result") == blurIn }) {
                    let r = CGFloat(dnum(morph, "radius", 0))
                    e.spread = attr(morph, "operator") == "erode" ? -r : r
                }
                // Colour from THIS shadow's feFlood: the composite(operator in)
                // that consumes the offset (drop) or the knocked-out ring (inner)
                // names the flood in its `in`.
                var shadowShape = offResult
                if e.kind == .innerShadow,
                   let knock = prims.first(where: { $0.name == "feComposite" && attr($0, "in2") == offResult && attr($0, "operator") == "out" }),
                   let knockResult = attr(knock, "result") {
                    shadowShape = knockResult
                }
                if let paintIn = prims.first(where: { $0.name == "feComposite" && attr($0, "in2") == shadowShape && attr($0, "operator") == "in" }),
                   let floodRef = attr(paintIn, "in"),
                   let flood = prims.first(where: { $0.name == "feFlood" && attr($0, "result") == floodRef }) {
                    var c = color(attr(flood, "flood-color") ?? "#000") ?? .black
                    c = applyAlpha(c, dnum(flood, "flood-opacity", 1))
                    e.color = c
                }
                effects.append(e)
            }

            if !effects.isEmpty { ctx.filters[id] = effects }
        }
    }

    /// CSS blend-mode name → BlendMode (reverse of BlendMode.cssName).
    private static func blendFromCSS(_ name: String) -> BlendMode {
        switch name {
        case "color-dodge": return .colorDodge
        case "color-burn":  return .colorBurn
        case "soft-light":  return .softLight
        case "hard-light":  return .hardLight
        default:            return BlendMode(rawValue: name) ?? .normal
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
                let d: Double = v.contains("%") ? 100 : 255   // rgb() may be percentages
                return RGBAColor(r: Double(n[0])/d, g: Double(n[1])/d, b: Double(n[2])/d,
                                 a: n.count >= 4 ? Double(n[3]) : 1)
            }
        }
        if v.hasPrefix("hsl") {
            let n = numbers(v)
            if n.count >= 3 {
                return hslToRGBA(h: Double(n[0]), s: Double(n[1]) / 100, l: Double(n[2]) / 100,
                                 a: n.count >= 4 ? Double(n[3]) : 1)
            }
        }
        // `currentColor`/`inherit` have no CSS color context in a bare SVG import,
        // so resolve to SVG's initial color (black) rather than returning nil —
        // returning nil silently dropped the fill to transparent ("lost color" bug).
        if v == "currentcolor" || v == "inherit" { return .black }
        return namedColor(v)
    }

    /// CSS `hsl()` → RGBA. `h` in degrees, `s`/`l`/`a` in 0…1.
    private static func hslToRGBA(h: Double, s: Double, l: Double, a: Double) -> RGBAColor {
        if s == 0 { return RGBAColor(r: l, g: l, b: l, a: a) }   // achromatic
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let pp = 2 * l - q
        func hue(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1/6 { return pp + (q - pp) * 6 * t }
            if t < 1/2 { return q }
            if t < 2/3 { return pp + (q - pp) * (2/3 - t) * 6 }
            return pp
        }
        return RGBAColor(r: hue(hh + 1/3), g: hue(hh), b: hue(hh - 1/3), a: a)
    }

    /// Full CSS named-color lookup (the extended keyword set). Was an 11-entry
    /// table, so any other keyword — `steelblue`, `crimson`, `teal` … — parsed to
    /// nil and the fill vanished. Values are 0xRRGGBB.
    private static func namedColor(_ v: String) -> RGBAColor? {
        guard let hex = cssNamed[v] else { return nil }
        return RGBAColor(r: Double((hex >> 16) & 0xFF) / 255,
                         g: Double((hex >> 8) & 0xFF) / 255,
                         b: Double(hex & 0xFF) / 255, a: 1)
    }

    /// A fill is "clear" (paints nothing) only if it's a fully-transparent solid;
    /// gradients always paint. Used to decide the implicit fill-close above.
    private static func isClearPaint(_ p: Paint) -> Bool {
        if case .solid(let c) = p { return c.a <= 0 }
        return false
    }

    private static let cssNamed: [String: UInt32] = [
        "aliceblue":0xF0F8FF, "antiquewhite":0xFAEBD7, "aqua":0x00FFFF, "aquamarine":0x7FFFD4, "azure":0xF0FFFF,
        "beige":0xF5F5DC, "bisque":0xFFE4C4, "black":0x000000, "blanchedalmond":0xFFEBCD, "blue":0x0000FF,
        "blueviolet":0x8A2BE2, "brown":0xA52A2A, "burlywood":0xDEB887, "cadetblue":0x5F9EA0, "chartreuse":0x7FFF00,
        "chocolate":0xD2691E, "coral":0xFF7F50, "cornflowerblue":0x6495ED, "cornsilk":0xFFF8DC, "crimson":0xDC143C,
        "cyan":0x00FFFF, "darkblue":0x00008B, "darkcyan":0x008B8B, "darkgoldenrod":0xB8860B, "darkgray":0xA9A9A9,
        "darkgrey":0xA9A9A9, "darkgreen":0x006400, "darkkhaki":0xBDB76B, "darkmagenta":0x8B008B, "darkolivegreen":0x556B2F,
        "darkorange":0xFF8C00, "darkorchid":0x9932CC, "darkred":0x8B0000, "darksalmon":0xE9967A, "darkseagreen":0x8FBC8F,
        "darkslateblue":0x483D8B, "darkslategray":0x2F4F4F, "darkslategrey":0x2F4F4F, "darkturquoise":0x00CED1, "darkviolet":0x9400D3,
        "deeppink":0xFF1493, "deepskyblue":0x00BFFF, "dimgray":0x696969, "dimgrey":0x696969, "dodgerblue":0x1E90FF,
        "firebrick":0xB22222, "floralwhite":0xFFFAF0, "forestgreen":0x228B22, "fuchsia":0xFF00FF, "gainsboro":0xDCDCDC,
        "ghostwhite":0xF8F8FF, "gold":0xFFD700, "goldenrod":0xDAA520, "gray":0x808080, "grey":0x808080,
        "green":0x008000, "greenyellow":0xADFF2F, "honeydew":0xF0FFF0, "hotpink":0xFF69B4, "indianred":0xCD5C5C,
        "indigo":0x4B0082, "ivory":0xFFFFF0, "khaki":0xF0E68C, "lavender":0xE6E6FA, "lavenderblush":0xFFF0F5,
        "lawngreen":0x7CFC00, "lemonchiffon":0xFFFACD, "lightblue":0xADD8E6, "lightcoral":0xF08080, "lightcyan":0xE0FFFF,
        "lightgoldenrodyellow":0xFAFAD2, "lightgray":0xD3D3D3, "lightgrey":0xD3D3D3, "lightgreen":0x90EE90, "lightpink":0xFFB6C1,
        "lightsalmon":0xFFA07A, "lightseagreen":0x20B2AA, "lightskyblue":0x87CEFA, "lightslategray":0x778899, "lightslategrey":0x778899,
        "lightsteelblue":0xB0C4DE, "lightyellow":0xFFFFE0, "lime":0x00FF00, "limegreen":0x32CD32, "linen":0xFAF0E6,
        "magenta":0xFF00FF, "maroon":0x800000, "mediumaquamarine":0x66CDAA, "mediumblue":0x0000CD, "mediumorchid":0xBA55D3,
        "mediumpurple":0x9370DB, "mediumseagreen":0x3CB371, "mediumslateblue":0x7B68EE, "mediumspringgreen":0x00FA9A, "mediumturquoise":0x48D1CC,
        "mediumvioletred":0xC71585, "midnightblue":0x191970, "mintcream":0xF5FFFA, "mistyrose":0xFFE4E1, "moccasin":0xFFE4B5,
        "navajowhite":0xFFDEAD, "navy":0x000080, "oldlace":0xFDF5E6, "olive":0x808000, "olivedrab":0x6B8E23,
        "orange":0xFFA500, "orangered":0xFF4500, "orchid":0xDA70D6, "palegoldenrod":0xEEE8AA, "palegreen":0x98FB98,
        "paleturquoise":0xAFEEEE, "palevioletred":0xDB7093, "papayawhip":0xFFEFD5, "peachpuff":0xFFDAB9, "peru":0xCD853F,
        "pink":0xFFC0CB, "plum":0xDDA0DD, "powderblue":0xB0E0E6, "purple":0x800080, "rebeccapurple":0x663399,
        "red":0xFF0000, "rosybrown":0xBC8F8F, "royalblue":0x4169E1, "saddlebrown":0x8B4513, "salmon":0xFA8072,
        "sandybrown":0xF4A460, "seagreen":0x2E8B57, "seashell":0xFFF5EE, "sienna":0xA0522D, "silver":0xC0C0C0,
        "skyblue":0x87CEEB, "slateblue":0x6A5ACD, "slategray":0x708090, "slategrey":0x708090, "snow":0xFFFAFA,
        "springgreen":0x00FF7F, "steelblue":0x4682B4, "tan":0xD2B48C, "teal":0x008080, "thistle":0xD8BFD8,
        "tomato":0xFF6347, "turquoise":0x40E0D0, "violet":0xEE82EE, "wheat":0xF5DEB3, "white":0xFFFFFF,
        "whitesmoke":0xF5F5F5, "yellow":0xFFFF00, "yellowgreen":0x9ACD32,
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
