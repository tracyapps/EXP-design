import AppKit
import Foundation

// Regression contract for BUG-083. Expectations come from CSS Backgrounds §6.1:
// https://www.w3.org/TR/css-backgrounds-3/#shadow-layers
// CSS lists front-to-back; EXP draws each shadow kind in array order, back-to-front.

extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize {
        CGSize(width: maxWidth ?? 20, height: 20)
    }
    func measuredSize(boxWidth currentWidth: CGFloat) -> CGSize {
        box == .fixed ? measuredSize(maxWidth: currentWidth) : measuredSize()
    }
}

@main
private enum RenderedHTMLShadowCheck {
    @MainActor
    static func main() throws {
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("\(value ? "PASS" : "FAIL"): \(message)")
            if !value { failures += 1 }
        }
        func close(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.0001 }
        func shadows(_ nodes: [Node]) -> [Effect] {
            nodes.flatMap { node in
                let own = node.effects.filter { $0.kind == .dropShadow || $0.kind == .innerShadow }
                if case .group(let children) = node.content { return own + shadows(children) }
                return own
            }
        }
        func imported(_ css: String) throws -> (document: Document, effects: [Effect], report: InteropImportReport) {
            var style = RenderedHTMLComputedStyle()
            style.backgroundColor = "rgb(255, 255, 255)"
            style.boxShadow = css
            let box = RenderedHTMLElement(tagName: "div", path: "0.0",
                                          rect: CGRect(x: 20, y: 20, width: 160, height: 100),
                                          style: style)
            let root = RenderedHTMLElement(tagName: "body", path: "0",
                                           rect: CGRect(x: 0, y: 0, width: 240, height: 180),
                                           style: RenderedHTMLComputedStyle(), children: [box])
            let snapshot = RenderedHTMLSnapshot(sourceName: "Shadow regression", sourceURL: "file:///shadow/index.html",
                                                 title: "Shadows", viewport: RenderedHTMLViewport(name: "Desktop", width: 240, renderHeight: 180),
                                                 documentHeight: 180, root: root)
            let result = try RenderedHTMLImporter().read(snapshotData: [JSONEncoder().encode(snapshot)])
            guard let page = result.payload.pages.first else { throw CocoaError(.fileReadCorruptFile) }
            let document = Document(artboards: page.artboards, nodes: page.nodes)
            return (document, shadows(page.nodes), result.report)
        }

        check(try imported("none").effects.isEmpty, "none adds no effects")
        let single = try imported("rgba(20, 40, 60, 0.25) -2px 3px 8px -1px").effects
        check(single.count == 1 && single[0].kind == .dropShadow
              && single[0].dx == -2 && single[0].dy == 3 && single[0].blur == 8 && single[0].spread == -1
              && close(single[0].color.r, 20.0 / 255) && close(single[0].color.a, 0.25),
              "single shadow retains negative offset/spread, blur, color and alpha")
        let minimal = try imported("rgb(0, 0, 0) 0px 2px").effects
        check(minimal.count == 1 && minimal[0].blur == 0 && minimal[0].spread == 0,
              "omitted blur/spread default to zero")

        let pair = try imported("rgba(255, 0, 0, 0.5) 1px 2px 3px 4px, rgba(0, 0, 255, 0.25) 8px 9px 10px -2px")
        check(pair.effects.count == 2, "both comma-separated rgba shadows survive import")
        check(pair.effects.map(\.dx) == [8, 1], "first CSS outer shadow paints on top")
        check(pair.report.mappedCounts["Shadow"] == 2, "report counts both mapped shadows")
        check(!pair.report.issues.contains { $0.category == "Shadow" && $0.fidelity == .approximate },
              "supported shadow stack is not reported as reduced")

        let mixed = try imported("rgba(255, 0, 0, 0.6) 1px 2px 3px 4px, inset rgba(0, 255, 0, 0.4) 5px 6px 7px -2px, rgba(0, 0, 255, 0) 9px 10px 11px 12px, inset rgba(255, 255, 0, 0.2) -3px -4px 5px 6px")
        let outer = mixed.effects.filter { $0.kind == .dropShadow }
        let inner = mixed.effects.filter { $0.kind == .innerShadow }
        check(outer.map(\.dx) == [9, 1] && inner.map(\.dx) == [-3, 5],
              "mixed outer/inset stacks retain their own CSS paint order")
        check(outer.count == 2 && close(outer[0].color.a, 0) && inner.count == 2
              && inner[1].spread == -2 && inner[1].blur == 7 && close(inner[1].color.a, 0.4),
              "transparent and inset shadows retain values without flattening")

        let reopened = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(mixed.document))
        let restored = shadows(reopened.nodes)
        check(restored.count == 4 && restored.map(\.dx) == mixed.effects.map(\.dx)
              && restored.map(\.kind) == mixed.effects.map(\.kind)
              && restored.map(\.spread) == mixed.effects.map(\.spread)
              && restored.map { $0.color.a } == mixed.effects.map { $0.color.a },
              "all four imported shadows survive document save/reopen")
        print("\(failures) failing shadow regression checks")
        if failures > 0 { exit(1) }
    }
}
