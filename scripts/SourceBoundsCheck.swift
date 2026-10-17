import AppKit

@main enum SourceBoundsCheck {
    static func main() throws {
        _ = NSApplication.shared
        let stroke = RectangleShape(fill: .solid(RGBAColor(r: 1, g: 0, b: 0, a: 1)), strokeWidth: 4)
        let node = Node(name: "Artwork", frame: CGRect(x: 10, y: 20, width: 40, height: 30), content: .rectangle(stroke))
        var hidden = node; hidden.id = UUID(); hidden.isVisible = false
        hidden.frame = CGRect(x: -500, y: -500, width: 1000, height: 1000)
        var model = Document()
        let pattern = PatternSource(name: "Tile", children: [node, hidden], tileSize: CGSize(width: 100, height: 100))
        model.patterns = [pattern]
        let bounds = CGRect(x: 8, y: 18, width: 44, height: 34)
        precondition(model.sourceArtworkBounds([node, hidden]) == bounds)
        let invisibleGroup = Node(name: "Hidden content", frame: CGRect(x: -900, y: -900, width: 1800, height: 1800), content: .group(children: [hidden]))
        precondition(model.sourceArtworkBounds([node, invisibleGroup]) == bounds)
        precondition(model.sourceArtworkBounds([invisibleGroup]) == nil)
        let fitted = model.fittingPatternToArtwork(pattern.id)
        precondition(fitted.patterns[0].tileSize == bounds.size && fitted.patterns[0].viewBox == bounds)
        precondition(fitted.patterns[0].children[0].frame == node.frame, "Fit must not rewrite artwork")
        let larger = fitted.resizingPattern(pattern.id, to: CGSize(width: 88, height: 68))
        precondition(larger.patterns[0].viewBox == CGRect(origin: bounds.origin, size: CGSize(width: 88, height: 68)))
        precondition(larger.patterns[0].children[0].frame == node.frame)
        // Raster evidence: extra tile space stays transparent; artwork doesn't stretch.
        let tile = ExportRenderView.patternTile(larger.patterns[0], document: larger, scale: 1)!
        let image = NSBitmapImageRep(cgImage: tile)
        precondition(image.pixelsWide == 88 && image.pixelsHigh == 68)
        precondition(image.colorAt(x: 20, y: 20)!.alphaComponent > 0.9)
        precondition(image.colorAt(x: 70, y: 50)!.alphaComponent < 0.01)
        precondition(model.resizingPattern(pattern.id, to: CGSize(width: CGFloat.nan, height: 1)).patterns[0].tileSize == pattern.tileSize)
        var imported = pattern
        imported.viewBox = CGRect(x: 5, y: 10, width: 200, height: 100)
        imported.tileSize = CGSize(width: 100, height: 50)
        imported.units = .objectBoundingBox
        model.patterns = [imported]
        let importedFit = model.fittingPatternToArtwork(imported.id)
        precondition(importedFit.patterns[0].tileSize == CGSize(width: 22, height: 17))
        precondition(importedFit.patterns[0].units == .objectBoundingBox)
        var component = ComponentSource(name: "Source", size: CGSize(width: 200, height: 200), children: [node, hidden])
        model.sources = [component]
        let fitComponent = model.fittingComponentToArtwork(component.id)
        precondition(fitComponent.sources[0].bounds == bounds && fitComponent.sources[0].hasExplicitBounds)
        // Old files retain automatic managed-frame behavior; a deliberate width
        // overrides it and survives resolution, save/reopen and later child edits.
        var group = Node(name: "Managed", frame: .zero, content: .group(children: [node]))
        group.autoPadding = AutoPadding()
        component.children = [group]
        model.sources = [component]
        precondition(model.sourceUsesManagedBounds(component))
        let fixed = model.resizingComponent(component.id, to: CGRect(x: -5, y: -7, width: 123, height: 91))
        precondition(!fixed.sourceUsesManagedBounds(fixed.sources[0]))
        let instance = ComponentInstance(sourceID: component.id)
        precondition(fixed.resolvedSize(of: instance) == CGSize(width: 123, height: 91))
        let reopened = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(fixed))
        precondition(reopened.sources[0].bounds == fixed.sources[0].bounds && reopened.sources[0].hasExplicitBounds)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(component)) as! [String: Any]
        legacy.removeValue(forKey: "hasExplicitBounds")
        let old = try JSONDecoder().decode(ComponentSource.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(!old.hasExplicitBounds)
        print("Source bounds: strokes/visibility, fit, fixed component resolution, legacy decode, persistence and real tile raster checks pass.")
    }
}
