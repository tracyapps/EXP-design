import Foundation
import CoreGraphics

extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize {
        CGSize(width: maxWidth ?? 20, height: 20)
    }
    func measuredSize(boxWidth currentWidth: CGFloat) -> CGSize {
        box == .fixed ? measuredSize(maxWidth: currentWidth) : measuredSize()
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum CanvasPagesCheck {
    static func main() throws {
        let left = Node(name: "Left", frame: CGRect(x: 10, y: 10, width: 20, height: 20),
                        content: .rectangle(RectangleShape()))
        let right = Node(name: "Right", frame: CGRect(x: 40, y: 10, width: 20, height: 20),
                         content: .rectangle(RectangleShape()))
        let relationship = AnchoredRelationship(
            kind: .controls,
            subject: RelationshipEndpoint(nodeID: left.id),
            target: RelationshipEndpoint(nodeID: right.id))
        let board = Artboard(name: "Board", frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let first = CanvasPage(name: "Flows", artboards: [board], nodes: [left, right],
                               anchoredRelationships: [relationship])
        let secondBoard = Artboard(name: "Same coordinates", frame: board.frame)
        let second = CanvasPage(name: "Archive", artboards: [secondBoard])
        var document = Document(artboards: [], nodes: [])
        document.pages = [first, second]

        require(document.owningArtboard(of: left.frame, on: first.id)?.id == board.id,
                "first-page ownership did not resolve")
        require(document.owningArtboard(of: left.frame, on: second.id)?.id == secondBoard.id,
                "same-coordinate artboards leaked across page boundaries")

        let copy = Document.duplicatingPage(first, named: "Flows copy")
        require(copy.id != first.id && copy.artboards[0].id != board.id,
                "duplicated page/artboard ids were reused")
        require(Set(copy.nodes.map(\.id)).isDisjoint(with: Set(first.nodes.map(\.id))),
                "duplicated page node ids were reused")
        let copiedIDs = Set(copy.nodes.map(\.id))
        require(copiedIDs.contains(copy.anchoredRelationships[0].subject.nodeID)
                && copiedIDs.contains(copy.anchoredRelationships[0].target.nodeID),
                "page-root relationship did not retarget to duplicated nodes")

        let encoded = try JSONEncoder().encode(document)
        let roundTrip = try JSONDecoder().decode(Document.self, from: encoded)
        require(roundTrip.pages.map(\.name) == ["Flows", "Archive"],
                "page names/order did not round-trip")
        require(roundTrip.pages[0].nodes.count == 2 && roundTrip.pages[1].artboards.count == 1,
                "page content did not round-trip")

        // Simulate a v2 single-canvas file by replacing the new `pages` key with
        // its legacy root arrays. Opening it must create one default canvas page.
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let pageJSON = (legacy.removeValue(forKey: "pages") as! [[String: Any]])[0]
        legacy["schemaVersion"] = 2
        legacy["formatVersion"] = 2
        legacy["artboards"] = pageJSON["artboards"]
        legacy["nodes"] = pageJSON["nodes"]
        legacy["guides"] = pageJSON["guides"]
        legacy["anchoredRelationships"] = pageJSON["anchoredRelationships"]
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let migrated = try JSONDecoder().decode(Document.self, from: legacyData)
        require(migrated.pages.count == 1 && migrated.pages[0].nodes.count == 2,
                "legacy single-canvas document did not migrate into Page 1")

        print("ok: canvas pages isolate ownership, deep-duplicate, round-trip, and migrate v2 documents")
    }
}
