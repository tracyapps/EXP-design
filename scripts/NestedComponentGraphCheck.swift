import Foundation
import CoreGraphics

// This graph check never renders text. Deterministic metrics satisfy the model's
// auto-layout references without pulling AppKit into the headless executable.
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
private enum NestedComponentGraphCheck {
    static func instance(_ sourceID: UUID, name: String) -> Node {
        Node(name: name,
             frame: CGRect(x: 0, y: 0, width: 40, height: 40),
             content: .instance(ComponentInstance(sourceID: sourceID)))
    }

    static func main() {
        let aID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        let bID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
        let cID = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

        let nestedC = instance(cID, name: "C instance")
        let group = Node(name: "Nested group",
                         frame: CGRect(x: 0, y: 0, width: 40, height: 40),
                         content: .group(children: [nestedC]))
        let a = ComponentSource(id: aID, name: "A", size: CGSize(width: 40, height: 40),
                                children: [instance(bID, name: "B instance")])
        let b = ComponentSource(id: bID, name: "B", size: CGSize(width: 40, height: 40),
                                children: [group])
        let c = ComponentSource(id: cID, name: "C", size: CGSize(width: 40, height: 40),
                                children: [])
        var document = Document(artboards: [], sources: [a, b, c])

        require(document.directSourceDependencies(of: aID) == [bID],
                "A's direct dependency was not found")
        require(document.directSourceDependencies(of: bID) == [cID],
                "a dependency nested in a group was not found")
        require(document.source(aID, dependsOn: cID),
                "transitive A -> B -> C dependency was not found")
        require(!document.canNestComponent(aID, in: cID),
                "C -> A should be rejected because it closes A -> B -> C -> A")
        require(!document.canNestComponent(aID, in: aID),
                "direct self-nesting should be rejected")
        require(document.canNestComponent(cID, in: aID),
                "adding another A -> C edge should remain legal")

        let plain = Node(name: "Plain shape",
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                         content: .rectangle(RectangleShape()))
        require(document.canInsert([plain], intoSource: cID),
                "plain layers should always be insertable into a valid source")
        require(!document.canInsert([instance(aID, name: "A instance")], intoSource: cID),
                "moving a component subtree must use the same indirect-cycle guard")

        // State editing must preserve the entire outline, including alpha and
        // inside/center/outside position, without leaking it into the base.
        let shapeID = UUID()
        let baseShape = Node(id: shapeID, name: "Outlined",
                             frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                             content: .rectangle(RectangleShape(
                                stroke: RGBAColor(r: 0, g: 0, b: 0, a: 1),
                                strokeWidth: 1, strokeAlignment: .center)))
        var editedShape = baseShape
        editedShape.content = .rectangle(RectangleShape(
            stroke: RGBAColor(r: 1, g: 0.25, b: 0, a: 0.4),
            strokeWidth: 6, strokeAlignment: .outside))
        let captured = ComponentStateEditing.capture(
            base: [baseShape], edited: [editedShape], state: ComponentState(name: "hover"))
        require(captured.state.overrides.count == 1,
                "outline changes should produce one bounded state override")
        guard case .stroke(let outline) = captured.state.overrides[0].value else {
            fputs("FAIL: outline change was not captured as a stroke override\n", stderr)
            exit(1)
        }
        require(outline.width == 6 && outline.alignment == .outside && outline.color?.a == 0.4,
                "stroke width, position, or transparency was lost")
        let applied = ComponentStateEditing.applied(captured.base, state: captured.state)
        guard case .rectangle(let appliedShape) = applied[0].content else {
            fputs("FAIL: applied state did not retain the rectangle\n", stderr)
            exit(1)
        }
        require(appliedShape.strokeWidth == 6 && appliedShape.strokeAlignment == .outside
                    && appliedShape.stroke.a == 0.4,
                "captured outline did not resolve back onto the state")

        // A placed A instance can choose C's state through A -> B -> group -> C,
        // and that path-scoped choice must survive document JSON round-tripping.
        let cStateID = UUID()
        document.sources[2].states = [ComponentState(id: cStateID, name: "open")]
        let bNodeID = document.sources[0].children[0].id
        guard case .group(let bGroupChildren) = document.sources[1].children[0].content else {
            fputs("FAIL: B fixture group missing\n", stderr)
            exit(1)
        }
        let cNodeID = bGroupChildren[0].id
        let root = ComponentInstance(
            sourceID: aID,
            nestedStateOverrides: [NestedInstanceStateOverride(
                instancePath: [bNodeID, cNodeID], stateID: cStateID)])
        guard case .instance(let resolvedB)? = document.resolvedChildren(of: root).first?.content,
              case .group(let resolvedGroup)? = document.resolvedChildren(of: resolvedB).first?.content,
              case .instance(let resolvedC) = resolvedGroup[0].content else {
            fputs("FAIL: nested component chain did not resolve\n", stderr)
            exit(1)
        }
        require(resolvedC.activeStateID == cStateID,
                "deep nested component state did not reach the target instance")

        document.nodes = [Node(name: "Root instance", frame: .zero, content: .instance(root))]
        let roundTrip = try! JSONDecoder().decode(Document.self,
            from: JSONEncoder().encode(document))
        guard case .instance(let decodedRoot) = roundTrip.nodes[0].content else {
            fputs("FAIL: decoded root instance missing\n", stderr)
            exit(1)
        }
        require(decodedRoot.nestedStateOverrides == root.nestedStateOverrides,
                "nested state path was lost during document round-trip")

        // A damaged legacy graph must terminate rather than recurse forever.
        document.sources[2].children = [instance(aID, name: "Legacy cycle")]
        require(document.source(aID, dependsOn: aID),
                "an existing legacy cycle should be detectable")

        print("ok: direct + grouped + transitive source dependencies")
        print("ok: direct and indirect component cycles rejected")
        print("ok: existing malformed cycles terminate safely")
        print("ok: component states capture complete outline appearance")
        print("ok: deep nested component state paths resolve and round-trip")
    }
}
