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
        // Deleting a source must delete the SOURCE, not the work: every instance
        // becomes an ordinary group of exactly what it was drawing, wherever it
        // lived, and components nested below it survive as live instances.
        let sID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!
        let tID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A6")!
        let pID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A7")!
        let tStateID = UUID()
        var t = ComponentSource(id: tID, name: "T", size: CGSize(width: 20, height: 20),
                                children: [Node(name: "T body",
                                                frame: CGRect(x: 0, y: 0, width: 20, height: 20),
                                                content: .rectangle(RectangleShape()))])
        t.states = [ComponentState(id: tStateID, name: "pressed")]
        let s = ComponentSource(id: sID, name: "S", size: CGSize(width: 40, height: 40),
                                children: [Node(name: "S body",
                                                frame: CGRect(x: 0, y: 0, width: 40, height: 40),
                                                content: .rectangle(RectangleShape())),
                                           instance(tID, name: "T instance")])
        let p = ComponentSource(id: pID, name: "P", size: CGSize(width: 60, height: 60),
                                children: [instance(sID, name: "S inside P")])
        var doc = Document(artboards: [], sources: [s, t, p])
        let sInsideP = doc.sources[2].children[0].id
        let tInsideS = doc.sources[0].children[1].id
        var first = instance(sID, name: "First use")
        first.frame = CGRect(x: 100, y: 100, width: 40, height: 40)
        var second = instance(sID, name: "Second use")
        second.frame = CGRect(x: 300, y: 100, width: 40, height: 40)
        let parentUse = Node(name: "P use", frame: CGRect(x: 0, y: 0, width: 60, height: 60),
                             content: .instance(ComponentInstance(
                                sourceID: pID,
                                nestedStateOverrides: [NestedInstanceStateOverride(
                                    instancePath: [sInsideP, tInsideS], stateID: tStateID)])))
        doc.nodes = [first, Node(name: "Wrapper", frame: .zero, content: .group(children: [second])),
                     parentUse]

        require(doc.sourcesDepending(on: sID) == [pID],
                "P should be reported as depending on S")
        require(doc.instanceCount(of: sID) == 3,
                "S should be counted on the canvas, inside a group, and inside P")

        let after = doc.deletingComponentSource(sID)
        require(after.source(for: sID) == nil, "the deleted source should be gone")
        require(after.instanceCount(of: sID) == 0, "no instance of S should survive")
        require(after.instanceCount(of: tID) == 3,
                "T instances below S must survive the flatten as live instances")

        guard case .group(let firstChildren) = after.nodes[0].content else {
            fputs("FAIL: a canvas instance did not flatten into a group\n", stderr)
            exit(1)
        }
        require(after.nodes[0].id == first.id && after.nodes[0].name == "First use",
                "the flattened layer must keep its own id and authored name")
        require(after.nodes[0].frame == first.frame,
                "flattening must not move the layer")
        require(firstChildren.count == 2, "the flatten should keep both source layers")
        require(firstChildren[0].frame.minX == 100 && firstChildren[0].frame.minY == 100,
                "flattened children must be offset into the instance's position")
        guard case .group(let wrapperChildren) = after.nodes[1].content,
              case .group = wrapperChildren[0].content else {
            fputs("FAIL: an instance nested in a group did not flatten\n", stderr)
            exit(1)
        }
        guard case .group = after.sources[1].children[0].content else {
            fputs("FAIL: the instance inside source P did not flatten\n", stderr)
            exit(1)
        }

        // Two uses of the same source must not end up sharing node identity.
        var seen = Set<UUID>()
        var duplicated = false
        func visit(_ nodes: [Node]) {
            for node in nodes {
                if !seen.insert(node.id).inserted { duplicated = true }
                if case .group(let kids) = node.content { visit(kids) }
            }
        }
        visit(after.nodes)
        for source in after.sources { visit(source.children) }
        require(!duplicated, "flattening two uses of one source produced duplicate node ids")

        // A state chosen two levels down must re-root onto the surviving
        // instance rather than being silently dropped.
        guard case .group(let flattenedInP) = after.sources[1].children[0].content,
              let survivingT = flattenedInP.first(where: {
                  if case .instance(let i) = $0.content { return i.sourceID == tID }
                  return false
              }) else {
            fputs("FAIL: T did not survive inside P\n", stderr)
            exit(1)
        }
        guard case .instance(let repairedParent) = after.nodes[2].content else {
            fputs("FAIL: the P instance should still be an instance\n", stderr)
            exit(1)
        }
        require(repairedParent.nestedStateOverrides.count == 1,
                "the nested state selection should be repaired, not dropped")
        require(repairedParent.nestedStateOverrides[0].instancePath == [survivingT.id],
                "the nested state path did not re-root onto the surviving instance")
        require(repairedParent.nestedStateOverrides[0].stateID == tStateID,
                "the repaired path lost which state was chosen")

        // Semantic containment (Chunk I): recommendations where a container has
        // expectations, warnings ONLY where a child's role demands a container
        // this parent is not, and silence everywhere else.
        let blank = Document(artboards: [], sources: [])
        require(AriaRole.list.expectedChildRoles == [.listitem],
                "a List should expect List Items")
        require(AriaRole.row.expectedChildRoles == [.cell, .columnheader, .rowheader],
                "a Row should expect cells and header cells")
        require(AriaRole.button.expectedChildRoles.isEmpty,
                "roles without ownership rules must impose nothing on their children")
        require(AriaRole.treeitem.requiredParentRoles == [.tree, .treeitem],
                "a Tree Item must be allowed to nest inside another Tree Item")
        require(AriaRole.radio.requiredParentRoles.isEmpty,
                "a lone Radio is poor practice but not invalid — it must never warn")

        // Uncategorized child inside an expectant container -> suggestion.
        guard let suggestion = blank.containmentAdvice(forChildRole: nil,
                                                       inParentRole: .tablist) else {
            fputs("FAIL: an uncategorized child inside a Tab Bar should be advised\n", stderr)
            exit(1)
        }
        require(suggestion.kind == .suggestion && !suggestion.isWarning,
                "guidance for an uncategorized child must not read as an error")
        require(suggestion.recommended == [.tab],
                "a Tab Bar should recommend Tab")

        // Correctly authored child -> silence.
        require(blank.containmentAdvice(forChildRole: .tab, inParentRole: .tablist) == nil,
                "a correctly placed Tab should produce no advice at all")
        // Legal-but-unrelated child -> silence, not a false alarm.
        require(blank.containmentAdvice(forChildRole: .group, inParentRole: .list) == nil,
                "a decorative Group inside a List must not be reported as invalid")
        // Parent with no expectations -> silence.
        require(blank.containmentAdvice(forChildRole: nil, inParentRole: .button) == nil,
                "a role with no ownership expectation must stay quiet")
        // Misplaced child -> warning that never rewrites the authored role.
        guard let invalid = blank.containmentAdvice(forChildRole: .listitem,
                                                    inParentRole: .tablist) else {
            fputs("FAIL: a List Item inside a Tab Bar should be flagged\n", stderr)
            exit(1)
        }
        require(invalid.kind == .invalidOwnership && invalid.isWarning,
                "a genuinely misplaced role should warn")

        // Container-side advice: a List whose nested components are not List Items.
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let listID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var item = ComponentSource(id: itemID, name: "Row art",
                                   size: CGSize(width: 20, height: 20), children: [])
        var listSource = ComponentSource(id: listID, name: "List",
                                         size: CGSize(width: 40, height: 40),
                                         children: [instance(itemID, name: "Entry")])
        listSource.a11y.role = .list
        var listDoc = Document(artboards: [], sources: [listSource, item])
        require(listDoc.containmentAdvice(forSource: listID)?.kind
                    == .containerHasNoExpectedChildren,
                "a List whose children are not List Items should be flagged")
        item.a11y.role = .listitem
        listDoc.sources[1] = item
        require(listDoc.containmentAdvice(forSource: listID) == nil,
                "once the child is a List Item the container advice should clear")
        let empty = ComponentSource(id: UUID(), name: "Empty list",
                                    size: CGSize(width: 10, height: 10), children: [],
                                    a11y: A11ySemantics(role: .list))
        listDoc.sources.append(empty)
        require(listDoc.containmentAdvice(forSource: empty.id) == nil,
                "an empty container is unfinished, not wrong — it must not be flagged")

        // Picker sections promote the expected roles without removing any.
        let sections = AriaRole.sections(recommendedFor: .list)
        require(sections.first?.isRecommendation == true && sections.first?.roles == [.listitem],
                "the recommended section should lead and hold the expected roles")
        let offered = Set(sections.dropFirst().flatMap(\.roles))
        require(offered == Set(AriaRole.allCases),
                "recommendations must never remove a role the designer may choose")
        require(AriaRole.sections(recommendedFor: nil).allSatisfy { !$0.isRecommendation },
                "with no container context there is nothing to recommend")

        // BUG-007: auto layout must size component instances by what they
        // RESOLVE to, not by the frame they happen to have stored. This mirrors
        // the owner's repro: a tab component, two instances in a 2px auto-layout
        // row, wrapped again as a component and used twice.
        var row = AutoLayout()
        row.direction = .horizontal
        row.distribution = .packed
        row.gap = 2
        row.primary = .start
        row.cross = .center

        let tabID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let tabsID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
        let tabSrc = ComponentSource(id: tabID, name: "tab",
                                     size: CGSize(width: 40, height: 40),
                                     children: [Node(name: "art",
                                                     frame: CGRect(x: 0, y: 0, width: 40, height: 40),
                                                     content: .rectangle(RectangleShape()))])
        // Both instances carry a deliberately STALE 10x10 frame — the exact
        // condition the pure engine cannot detect.
        var staleA = instance(tabID, name: "tab a")
        staleA.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        var staleB = instance(tabID, name: "tab b")
        staleB.frame = CGRect(x: 100, y: 0, width: 10, height: 10)
        var tabRow = Node(name: "Group", frame: CGRect(x: 0, y: 0, width: 22, height: 10),
                          content: .group(children: [staleA, staleB]))
        tabRow.autoLayout = row
        let tabsSrc = ComponentSource(id: tabsID, name: "tabs",
                                      size: CGSize(width: 82, height: 40),
                                      children: [tabRow])
        let layoutDoc = Document(artboards: [], sources: [tabSrc, tabsSrc])

        // The pure engine is the regression witness: it lays the row out from the
        // stale frames, which is precisely the reported defect.
        guard case .group(let naive) = AutoLayoutEngine.reflowed([tabRow])[0].content else {
            fputs("FAIL: the pure engine did not return a group\n", stderr)
            exit(1)
        }
        require(naive[1].frame.minX == 12,
                "the pure engine should still lay out from stored frames")

        guard case .group(let sized) = layoutDoc.reflowed([tabRow])[0].content else {
            fputs("FAIL: document-aware reflow did not return a group\n", stderr)
            exit(1)
        }
        require(sized[0].frame.size == CGSize(width: 40, height: 40)
                    && sized[1].frame.size == CGSize(width: 40, height: 40),
                "instances should be sized from their resolved bounds before layout")
        require(sized[0].frame.minX == 0 && sized[1].frame.minX == 42,
                "the 2px gap must be measured between RESOLVED instance bounds")
        require(layoutDoc.reflowed([tabRow])[0].frame.size == CGSize(width: 82, height: 40),
                "the auto-layout row should hug the resolved instances")

        // One level up: an instance of `tabs` must contribute the re-hugged 82pt
        // width to its own parent's layout, proving innermost-first sizing.
        require(layoutDoc.resolvedSize(of: ComponentInstance(sourceID: tabsID))
                    == CGSize(width: 82, height: 40),
                "a managed source should resolve to its re-hugged row size")
        var outerRow = row
        outerRow.gap = 6
        var outerA = instance(tabsID, name: "tabs a")
        outerA.frame = CGRect(x: 0, y: 0, width: 5, height: 5)
        var outerB = instance(tabsID, name: "tabs b")
        outerB.frame = CGRect(x: 500, y: 0, width: 5, height: 5)
        var outerGroup = Node(name: "Outer", frame: .zero,
                              content: .group(children: [outerA, outerB]))
        outerGroup.autoLayout = outerRow
        guard case .group(let outerSized) = layoutDoc.reflowed([outerGroup])[0].content else {
            fputs("FAIL: the outer row did not return a group\n", stderr)
            exit(1)
        }
        require(outerSized[1].frame.minX == 88,
                "a nested component's re-hugged width must reach its parent's layout")

        // Totality: a damaged document that already contains a cycle must not
        // recurse forever now that layout resolves instances.
        let cyclic = Document(artboards: [], sources: [
            ComponentSource(id: aID, name: "A", size: CGSize(width: 10, height: 10),
                            children: [instance(bID, name: "B")]),
            ComponentSource(id: bID, name: "B", size: CGSize(width: 10, height: 10),
                            children: [instance(aID, name: "A")])])
        var cyclicGroup = Node(name: "Cycle", frame: .zero,
                               content: .group(children: [instance(aID, name: "A use")]))
        cyclicGroup.autoLayout = row
        _ = cyclic.reflowed([cyclicGroup])

        print("ok: existing malformed cycles terminate safely")
        print("ok: component states capture complete outline appearance")
        print("ok: deep nested component state paths resolve and round-trip")
        print("ok: deleting a source flattens every use without losing work")
        print("ok: flattened uses keep identity and stay id-unique")
        print("ok: nested state selections re-root onto surviving instances")
        print("ok: containment recommends, warns only on real ownership errors")
        print("ok: container-side advice clears once children are authored")
        print("ok: recommendations promote roles without removing any")
        print("ok: auto layout sizes instances from resolved bounds (BUG-007)")
        print("ok: nested re-hugged widths reach the parent layout")
        print("ok: layout on a cyclic legacy document terminates")
    }
}
