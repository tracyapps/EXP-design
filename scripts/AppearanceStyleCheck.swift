import Foundation
import CoreGraphics

// Model checks keep text geometry out of scope (no text layout is requested).
extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize { .zero }
    func measuredSize(boxWidth: CGFloat) -> CGSize { .zero }
}
private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private func encoded<T: Encodable>(_ value: T) -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try! encoder.encode(value)
}
private func rectangle(_ name: String) -> Node {
    Node(name: name, frame: CGRect(x: 10, y: 20, width: 80, height: 60), content: .rectangle(RectangleShape()))
}
@main enum AppearanceStyleCheck {
    static func main() throws {
        let gradient = Paint.gradient(GradientFill(angle: 37, start: CGPoint(x: 0.2, y: 0.1), end: CGPoint(x: 0.8, y: 0.9)))
        var source = rectangle("Source")
        source.content = .rectangle(RectangleShape(fill: gradient, cornerRadius: 9, stroke: gradient,
            strokeWidth: 3, strokeAlignment: .outside, strokePattern: .dashed,
            cornerRadii: CornerRadii(topLeft: 1, topRight: 4, bottomRight: 7, bottomLeft: 9)))
        source.opacity = 0.6; source.blendMode = .multiply; source.effects = [Effect(blur: 9)]
        var target = rectangle("Target"); target.effects = [Effect(kind: .innerShadow)]
        let original = target
        let paint = NodeAppearanceStyle(paint: source.layerPaintStyle)
        var nodes = [target]
        require(Node.pasteAppearance(paint, to: [target.id], in: &nodes), "paint paste applies")
        target = nodes[0]
        require(encoded(target.content) == encoded(source.content), "gradient geometry, stroke pattern, and per-corner radii copied")
        require(target.effects[0].id == original.effects[0].id && target.opacity == original.opacity && target.blendMode == original.blendMode, "paint excludes effects/opacity/blending")
        require(target.id == original.id && target.frame == original.frame && target.name == original.name, "identity and geometry preserved")
        nodes = [original]
        require(Node.pasteAppearance(NodeAppearanceStyle(effects: source.layerStyle), to: [original.id], in: &nodes), "effects paste applies")
        require(encoded(nodes[0].content) == encoded(original.content), "effects exclude paint and corners")
        require(nodes[0].opacity == 0.6 && nodes[0].blendMode == .multiply && nodes[0].effects[0].blur == 9, "effects include opacity/blending")
        require(nodes[0].effects[0].id != source.effects[0].id, "effect identities are independent")
        nodes = [original]
        require(Node.pasteAppearance(NodeAppearanceStyle(paint: source.layerPaintStyle, effects: source.layerStyle), to: [original.id], in: &nodes), "combined paste applies")
        require(encoded(nodes[0].content) == encoded(source.content), "combined includes paint")
        require(nodes[0].effects[0].blur == 9 && nodes[0].opacity == 0.6, "combined includes effects")
        var hidden = rectangle("Hidden"); hidden.isVisible = false
        var locked = rectangle("Locked"); locked.isLocked = true
        let child = rectangle("Child")
        let nested = Node(name: "Nested", frame: .zero, content: .group(children: [child, hidden, locked]))
        let group = Node(name: "Folder", frame: .zero, content: .group(children: [nested]))
        nodes = [group]
        require(Node.pasteAppearance(NodeAppearanceStyle(paint: source.layerPaintStyle, effects: source.layerStyle),
             to: [group.id, child.id], in: &nodes), "nested folders plus selected child")
        guard case .group(let a) = nodes[0].content, case .group(let b) = a[0].content else { fatalError() }
        require(encoded(b[0].content) == encoded(source.content), "nested folder artwork receives paint")
        require(encoded(b[1]) == encoded(hidden) && encoded(b[2]) == encoded(locked), "hidden/locked artwork protected")
        require(nodes[0].effects.count == 1 && a[0].effects.isEmpty && b[0].effects.count == 1, "effects apply to explicitly selected layers")
        var padding = AutoPadding(); padding.paddingTop = 42; padding.marginLeft = 11
        var padded = group; padded.autoPadding = padding
        nodes = [padded]
        require(Node.pasteAppearance(paint, to: [padded.id], in: &nodes), "padding group paint")
        require(nodes[0].autoPadding?.paddingTop == 42 && nodes[0].autoPadding?.marginLeft == 11, "layout padding preserved")
        require(nodes[0].autoPadding?.fill == gradient && nodes[0].autoPadding?.cornerRadius == 9, "padding background paint copied")
        var path = Node(name: "Path", frame: original.frame, content: .path(PathShape(points: [PathPoint(point: .zero), PathPoint(point: CGPoint(x: 40, y: 20))], strokeCap: .butt, strokeJoin: .bevel, strokeMiterLimit: 8)))
        let geometry = path
        var pathSource = path
        if case .path(var p) = pathSource.content { p.strokeCap = .square; p.strokeJoin = .miter; p.strokeMiterLimit = 11; pathSource.content = .path(p) }
        require(path.applyPaintStyle(pathSource.layerPaintStyle!), "path style applies")
        guard case .path(let p) = path.content, case .path(let before) = geometry.content else { fatalError() }
        require(encoded(p.points) == encoded(before.points), "path points unchanged")
        require(p.strokeCap == .square && p.strokeJoin == .miter && p.strokeMiterLimit == 11, "path cap/join/miter copied")
        var text = Node(name: "Text", frame: original.frame, content: .text(TextContent(string: "Keep these words", fontSize: 23)))
        _ = text.applyPaintStyle(source.layerPaintStyle!)
        guard case .text(let tc) = text.content else { fatalError() }
        require(tc.plainString == "Keep these words" && tc.firstRun.fontSize == 23 && tc.firstRun.color == .black, "text content/font retained; unsupported gradient not flattened")
        let pattern = Paint.pattern(PatternRef(patternID: UUID(), fallback: RGBAColor(r: 0.2, g: 0.7, b: 0.1, a: 1)))
        var patternSource = source
        patternSource.content = .rectangle(RectangleShape(fill: pattern, stroke: pattern, strokeWidth: 2))
        var patternTarget = original
        _ = patternTarget.applyPaintStyle(patternSource.layerPaintStyle!)
        require(patternTarget.layerPaintStyle?.fill == pattern && patternTarget.layerPaintStyle?.stroke == pattern, "pattern identities/fallbacks retained in both paints")
        var noEffects = source; noEffects.effects = []
        nodes = [original]
        require(Node.pasteAppearance(NodeAppearanceStyle(effects: noEffects.layerStyle), to: [original.id], in: &nodes)
            && nodes[0].effects.isEmpty, "an empty copied effects stack clears target effects")
        let textStyle = TypeStyle.capture(from: tc, name: "Named style")
        var designLanguage = DesignLanguage(); designLanguage.saveTypeStyle(textStyle)
        require(designLanguage.typeStyles[0].name == "Named style" && designLanguage.typeStyles[0].fontSize == 23, "type style uses document library")
        nodes = (0..<800).map { rectangle("Icon \($0)") }
        let selected = Set(nodes.map(\.id))
        require(Node.pasteAppearance(paint, to: selected, in: &nodes) && nodes.allSatisfy { $0.layerPaintStyle?.strokeWidth == 3 }, "800-icon batch receives appearance")
        let decoded = try JSONDecoder().decode([Node].self, from: encoded(nodes))
        require(decoded[0].layerPaintStyle?.fill == gradient, "appearance survives document encoding")
        print("PASS: paint/effects/combined channels, gradient geometry, corners, paths, nested folders, protected branches, padding, text, type styles, 800-icon batch, round-trip")
        if let output = CommandLine.arguments.dropFirst().first {
            var doc = Document()
            var text = Node(name: "Convenience Type", frame: CGRect(x: 40,y: 180,width: 220,height: 60), content: .text(TextContent(string: "Save my type style", fontSize: 24)))
            text.content = .text(TextContent(string: "Save my type style", fontSize: 24))
            var left = source; left.frame = CGRect(x:40,y:40,width:120,height:90)
            var right = original; right.frame = CGRect(x:220,y:40,width:120,height:90)
            doc.nodes = [left,right,text]
            try encoded(doc).write(to: URL(fileURLWithPath: output))
        }
    }
}
