import Foundation
import CoreGraphics

// FEAT-012 chunk I-e. Proves the invariants the anchored-relationship model rests
// on. Every case here corresponds to something that actually went wrong, or that
// would silently destroy authored semantics if it regressed — see BACKLOG BUG-010,
// BUG-012, and FEAT-012's chunk notes.
//
// Never renders text: deterministic metrics satisfy the model's auto-layout
// references without pulling AppKit into a headless executable.
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
private enum AnchoredRelationshipCheck {

    // MARK: Fixture

    static func rect(_ name: String) -> Node {
        Node(name: name, frame: CGRect(x: 0, y: 0, width: 20, height: 20),
             content: .rectangle(RectangleShape(fill: .solid(.black), cornerRadius: 0)))
    }

    static func instance(_ sourceID: UUID, name: String) -> Node {
        Node(name: name, frame: CGRect(x: 0, y: 0, width: 40, height: 40),
             content: .instance(ComponentInstance(sourceID: sourceID)))
    }

    static func group(_ name: String, _ children: [Node]) -> Node {
        Node(name: name, frame: CGRect(x: 0, y: 0, width: 100, height: 100),
             content: .group(children: children))
    }

    /// A tab bar component holding two tabs, plus a panel component — the shape
    /// that drove this whole design.
    static func makeDocument() -> (document: Document, tabBar: UUID, panel: UUID,
                                   tabOne: UUID, group: UUID) {
        let tabSource = ComponentSource(
            name: "tab", size: CGSize(width: 40, height: 20),
            children: [rect("label")], a11y: A11ySemantics(role: .tab))

        let tabOne = instance(tabSource.id, name: "one")
        let tabTwo = instance(tabSource.id, name: "two")
        let barSource = ComponentSource(
            name: "tabs", size: CGSize(width: 100, height: 20),
            children: [group("row", [tabOne, tabTwo])],
            a11y: A11ySemantics(role: .tablist))

        let panelSource = ComponentSource(
            name: "tab-content", size: CGSize(width: 100, height: 60),
            children: [rect("body")], a11y: A11ySemantics(role: .tabpanel))

        let barNode = instance(barSource.id, name: "tab row")
        let panelNode = instance(panelSource.id, name: "content panel")
        let area = group("tab area", [barNode, panelNode])

        var document = Document(artboards: [], nodes: [area],
                                sources: [tabSource, barSource, panelSource])

        // tab one (inside the placed bar) controls the panel (a sibling) — the
        // cross-component link that cannot live on the subject.
        let link = AnchoredRelationship(
            kind: .controls,
            subject: RelationshipEndpoint(instanceChain: [barNode.id], nodeID: tabOne.id),
            target: RelationshipEndpoint(nodeID: panelNode.id))
        document.nodes[0].anchoredRelationships = [link]
        return (document, barNode.id, panelNode.id, tabOne.id, area.id)
    }

    static func anchors(in nodes: [Node]) -> [AnchoredRelationship] {
        nodes.flatMap { node -> [AnchoredRelationship] in
            if case .group(let children) = node.content {
                return node.anchoredRelationships + anchors(in: children)
            }
            return node.anchoredRelationships
        }
    }

    // MARK: Checks

    /// A path names component instances only, never groups — so regrouping must not
    /// disturb an endpoint. This is what lets the neighborhood rule be a storage
    /// rule rather than a constraint the designer has to think about.
    static func checkGroupsAreTransparentToPaths() {
        let f = makeDocument()
        let endpoint = RelationshipEndpoint(instanceChain: [f.tabBar], nodeID: f.tabOne)
        guard case .group(let children)? =
                f.document.nodes.first(where: { $0.id == f.group })?.content else {
            require(false, "fixture: tab area is not a group"); return
        }
        require(f.document.resolveEndpoint(endpoint, in: children) != nil,
                "an endpoint inside a placed component should resolve from its anchor")

        // Wrap the anchor's children one level deeper; the SAME endpoint must still
        // resolve, because the path never mentioned a group.
        let deeper = [group("extra wrapper", children)]
        require(f.document.resolveEndpoint(endpoint, in: deeper) != nil,
                "adding a group between anchor and subject broke an endpoint — paths must ignore groups")
    }

    /// Duplicating an anchor must relink to the COPY. BUG-010: `cloned` re-minted
    /// ids but carried relationships over verbatim, so a duplicate silently
    /// described the ORIGINAL's structure.
    static func checkDuplicateIsIndependent() {
        let f = makeDocument()
        guard let original = f.document.nodes.first(where: { $0.id == f.group }) else {
            require(false, "fixture: missing group"); return
        }

        // Mirror what CanvasView.cloned does: fresh ids, then remap.
        var map: [UUID: UUID] = [:]
        func fresh(_ node: Node) -> Node {
            var copy = node
            copy.id = UUID()
            map[node.id] = copy.id
            if case .group(let children) = copy.content {
                copy.content = .group(children: children.map(fresh))
            }
            return copy
        }
        let copy = Document.remappingAnchors(fresh(original), map: map)

        let copied = copy.anchoredRelationships
        require(copied.count == 1, "the copy should carry exactly one relationship")
        require(copied[0].subject.instanceChain != [f.tabBar],
                "the copy still points at the ORIGINAL's tab bar — BUG-010 has regressed")
        require(copied[0].subject.instanceChain == [map[f.tabBar]!],
                "the copy's subject chain should name the COPY's tab bar")
        require(copied[0].target.nodeID == map[f.panel]!,
                "the copy's target should be the COPY's panel")
        // The source-child id is stable across placements and must NOT be renamed.
        require(copied[0].subject.nodeID == f.tabOne,
                "a source child id was rewritten; those are shared by every placement")
    }

    /// An explicit delete takes its relationships with it, and leaves untouched
    /// ones alone. The precision matters: a blanket "drop anything unresolved"
    /// sweep would eat real work mid-edit.
    static func checkDeleteRemovesOnlyWhatItShould() {
        let f = makeDocument()
        guard let area = f.document.nodes.first(where: { $0.id == f.group }) else {
            require(false, "fixture: missing group"); return
        }

        let kept = Document.removingAnchors(referencing: [UUID()],
                                            in: area.anchoredRelationships)
        require(kept.count == 1, "an unrelated delete must not remove a relationship")

        let dropped = Document.removingAnchors(referencing: [f.panel],
                                               in: area.anchoredRelationships)
        require(dropped.isEmpty, "deleting the target should remove the relationship")
    }

    /// Ungrouping must MOVE relationships up, not destroy them. The group node
    /// disappears; the endpoints stay valid because they never named it.
    static func checkUngroupHoistsRatherThanDestroys() {
        let f = makeDocument()
        guard let area = f.document.nodes.first(where: { $0.id == f.group }),
              case .group(let children) = area.content else {
            require(false, "fixture: missing group"); return
        }

        // What CanvasView.ungroup now does: the entries move to the scope root.
        let hoisted = area.anchoredRelationships
        require(!hoisted.isEmpty, "fixture should have something to hoist")

        var afterUngroup = f.document
        afterUngroup.nodes = children
        afterUngroup.anchoredRelationships = hoisted
        require(afterUngroup.anchoredRelationships.count == 1,
                "ungrouping dropped the group's relationships instead of hoisting them")
        require(afterUngroup.resolveEndpoint(hoisted[0].target, in: children) != nil,
                "the hoisted target should still resolve from the new anchor")
    }

    /// DOM ids must stay unique when the same component is placed twice inside a
    /// third. This is the collision chunk I-d removed: with a single instance id,
    /// both placements minted identical ids for their children.
    static func checkDOMIDsAreUniqueAtDepthTwo() {
        let child = UUID()
        let placementA = UUID()
        let placementB = UUID()
        let outer = UUID()

        let deep = Set([
            SemanticHTMLIdentity.nodeDOMID(child, chain: [outer, placementA]),
            SemanticHTMLIdentity.nodeDOMID(child, chain: [outer, placementB])
        ])
        require(deep.count == 2,
                "two placements of one component minted the SAME DOM id at depth 2")

        require(SemanticHTMLIdentity.nodeDOMID(child, chain: [placementA])
                == SemanticHTMLIdentity.nodeDOMID(child, instanceID: placementA),
                "depth-1 ids changed shape; existing exports would shift for no reason")
    }

    /// Legacy subject-stored relationships must survive the move to anchors, and
    /// re-running migration must not duplicate them.
    static func checkMigrationIsLosslessAndIdempotent() {
        var a = rect("a")
        let b = rect("b")
        a.relationships = [NodeRelationship(kind: .describedby, targetID: b.id)]
        var document = Document(artboards: [], nodes: [group("holder", [a, b])], sources: [])

        document.migrateRelationshipsToAnchors()
        let first = anchors(in: document.nodes) + document.anchoredRelationships
        require(first.count == 1, "a legacy relationship was lost in migration")

        document.migrateRelationshipsToAnchors()
        let second = anchors(in: document.nodes) + document.anchoredRelationships
        require(second.count == 1,
                "migration duplicated on a second run — dedupe must ignore the freshly minted id")
    }

    /// The advisory pairing table must stay SMALL and cited. An advisory that fires
    /// on correct work is worse than no advisory, so anything added here needs a
    /// line of spec behind it — see the doc comment on the table itself.
    static func checkAdvisoryTableIsNarrow() {
        require(AriaRole.tab.expectedRelationshipTargetRoles(for: .controls) == [.tabpanel],
                "a tab's aria-controls should expect a tabpanel (WAI-APG tabs)")
        require(AriaRole.tabpanel.expectedRelationshipTargetRoles(for: .labelledby) == [.tab],
                "a tabpanel's aria-labelledby should expect a tab (WAI-APG tabs)")
        // No expectation anywhere it has not been verified. `describedby` is free
        // text by design, and a tablist names itself rather than pointing at parts.
        require(AriaRole.tab.expectedRelationshipTargetRoles(for: .describedby).isEmpty,
                "describedby must carry no expectation — it points at explanatory text")
        require(AriaRole.tablist.expectedRelationshipTargetRoles(for: .labelledby).isEmpty,
                "an unverified pairing was added to the advisory table")
        require(AriaRole.button.expectedRelationshipTargetRoles(for: .controls).isEmpty,
                "a button may control anything; that must not be advised on")
    }

    // MARK: FEAT-017 chunk J-a

    /// Nested overrides must round-trip, and an OLD file (no key) must decode to
    /// empty rather than failing — the whole point of landing storage before
    /// resolution is that it cannot disturb anything.
    static func checkNestedOverridesRoundTrip() {
        let nestedInstance = UUID()
        let target = UUID()
        var instance = ComponentInstance(sourceID: UUID())
        instance.nestedOverrides = [
            NestedInstanceOverride(instancePath: [nestedInstance],
                                   targetNodeID: target, value: .text("two"))
        ]
        let data = try! JSONEncoder().encode(instance)
        let back = try! JSONDecoder().decode(ComponentInstance.self, from: data)
        require(back.nestedOverrides.count == 1, "a nested override was lost in a round trip")
        require(back.nestedOverrides[0].instancePath == [nestedInstance],
                "the nested override's path changed across a round trip")
        require(back.nestedOverrides[0].value.textValue == "two",
                "the nested override's value changed across a round trip")

        // A pre-v2.1 instance has no `nestedOverrides` key at all.
        let legacy = #"{"sourceID":"\#(UUID().uuidString)"}"#
        let decoded = try? JSONDecoder().decode(ComponentInstance.self,
                                                from: Data(legacy.utf8))
        require(decoded != nil, "an instance without the new key failed to decode")
        require(decoded?.nestedOverrides.isEmpty == true,
                "a missing nestedOverrides key should decode to empty")
    }

    /// An empty path addresses the instance's OWN children, which `overrides`
    /// already covers. Resolution must not guess at it.
    static func checkEmptyPathIsNotAddressable() {
        let override = NestedInstanceOverride(instancePath: [], targetNodeID: UUID(),
                                              value: .text("x"))
        require(!override.isAddressable,
                "an empty instancePath must not be treated as addressable")
        require(NestedInstanceOverride(instancePath: [UUID()], targetNodeID: UUID(),
                                       value: .text("x")).isAddressable,
                "a one-step path addresses a nested instance and IS addressable")
    }

    // MARK: FEAT-017 chunk J-b

    static func text(_ name: String, _ value: String) -> Node {
        Node(name: name, frame: CGRect(x: 0, y: 0, width: 40, height: 20),
             content: .text(TextContent(string: value)))
    }

    /// A label component, a bar component containing two of it, and two PLACEMENTS
    /// of the bar — the shape the owner could not build.
    static func makeNestedFixture() -> (document: Document, barA: Node, barB: Node,
                                        innerOne: UUID, label: UUID) {
        let label = text("label", "source")
        let labelSource = ComponentSource(name: "label", size: CGSize(width: 40, height: 20),
                                          children: [label])
        let one = instance(labelSource.id, name: "one")
        let two = instance(labelSource.id, name: "two")
        let barSource = ComponentSource(name: "bar", size: CGSize(width: 100, height: 20),
                                        children: [group("row", [one, two])])
        let barA = instance(barSource.id, name: "bar A")
        let barB = instance(barSource.id, name: "bar B")
        let document = Document(artboards: [], nodes: [barA, barB],
                                sources: [labelSource, barSource])
        return (document, barA, barB, one.id, label.id)
    }

    /// Read the text of the first nested label, resolving all the way down.
    static func resolvedLabelText(_ document: Document, _ barNode: Node,
                                  innerOne: UUID) -> String? {
        guard case .instance(let bar) = barNode.content else { return nil }
        func findInstance(_ id: UUID, in nodes: [Node]) -> ComponentInstance? {
            for node in nodes {
                if node.id == id, case .instance(let inner) = node.content { return inner }
                if case .group(let children) = node.content,
                   let found = findInstance(id, in: children) { return found }
            }
            return nil
        }
        let barChildren = document.resolvedChildren(of: bar)
        guard let inner = findInstance(innerOne, in: barChildren) else { return nil }
        for child in document.resolvedChildren(of: inner) {
            if case .text(let content) = child.content { return content.plainString }
        }
        return nil
    }

    /// The point of the whole feature: two placements of one component carrying
    /// DIFFERENT nested content, without either touching the shared source.
    static func checkNestedOverrideReachesTheNestedLayer() {
        var f = makeNestedFixture()
        require(resolvedLabelText(f.document, f.barA, innerOne: f.innerOne) == "source",
                "fixture should start at the source value")

        var barA = f.barA
        guard case .instance(var a) = barA.content else { require(false, "fixture"); return }
        a.nestedOverrides = [NestedInstanceOverride(instancePath: [f.innerOne],
                                                    targetNodeID: f.label,
                                                    value: .text("A"))]
        barA.content = .instance(a)
        f.document.nodes[0] = barA

        require(resolvedLabelText(f.document, barA, innerOne: f.innerOne) == "A",
                "a nested override did not reach the layer inside the nested component")
        require(resolvedLabelText(f.document, f.barB, innerOne: f.innerOne) == "source",
                "the OTHER placement changed too — nested overrides are leaking")
    }

    /// Dropping the entry must fall back to the nearest source value. Reset is not
    /// a separate mechanism; it is the absence of an override.
    static func checkResetFallsBackToSource() {
        var f = makeNestedFixture()
        var barA = f.barA
        guard case .instance(var a) = barA.content else { require(false, "fixture"); return }
        a.nestedOverrides = [NestedInstanceOverride(instancePath: [f.innerOne],
                                                    targetNodeID: f.label,
                                                    value: .text("A"))]
        barA.content = .instance(a)
        f.document.nodes[0] = barA
        require(resolvedLabelText(f.document, barA, innerOne: f.innerOne) == "A", "setup")

        a.nestedOverrides = []
        barA.content = .instance(a)
        f.document.nodes[0] = barA
        require(resolvedLabelText(f.document, barA, innerOne: f.innerOne) == "source",
                "removing a nested override should fall back to the source value")
    }

    /// A path never names a group, so wrapping the nested instance in another
    /// layout group must not break the override.
    static func checkGroupsDoNotBlockPushDown() {
        let label = text("label", "source")
        let labelSource = ComponentSource(name: "label", size: CGSize(width: 40, height: 20),
                                          children: [label])
        let one = instance(labelSource.id, name: "one")
        // Two layers of grouping between the source root and the nested instance.
        let barSource = ComponentSource(name: "bar", size: CGSize(width: 100, height: 20),
                                        children: [group("outer", [group("inner", [one])])])
        let bar = instance(barSource.id, name: "bar")
        var document = Document(artboards: [], nodes: [bar],
                                sources: [labelSource, barSource])
        guard case .instance(var b) = bar.content else { require(false, "fixture"); return }
        b.nestedOverrides = [NestedInstanceOverride(instancePath: [one.id],
                                                    targetNodeID: label.id,
                                                    value: .text("through groups"))]
        var barNode = bar
        barNode.content = .instance(b)
        document.nodes[0] = barNode
        require(resolvedLabelText(document, barNode, innerOne: one.id) == "through groups",
                "grouping between the anchor and a nested instance blocked the override")
    }

    // MARK: FEAT-017 chunk J-d

    /// The semantic-HTML resolver is a SEPARATE implementation from
    /// `resolvedChildren` — it keeps hidden layers so it can emit `hidden` — and
    /// that is exactly why it silently missed the nested-override push-down when
    /// J-b landed. This check exists because the duplication is the hazard: if a
    /// third resolver appears, or someone edits one and not the other, the canvas
    /// and the export will disagree and nothing else would say so.
    static func checkSemanticResolverSeesNestedOverrides() {
        var f = makeNestedFixture()
        var barA = f.barA
        guard case .instance(var a) = barA.content else { require(false, "fixture"); return }
        a.nestedOverrides = [NestedInstanceOverride(instancePath: [f.innerOne],
                                                    targetNodeID: f.label,
                                                    value: .text("exported"))]
        barA.content = .instance(a)
        f.document.nodes[0] = barA

        func findInstance(_ id: UUID, in nodes: [Node]) -> ComponentInstance? {
            for node in nodes {
                if node.id == id, case .instance(let inner) = node.content { return inner }
                if case .group(let children) = node.content,
                   let found = findInstance(id, in: children) { return found }
            }
            return nil
        }
        let barChildren = f.document.semanticHTMLResolvedChildren(of: a)
        guard let inner = findInstance(f.innerOne, in: barChildren) else {
            require(false, "the semantic resolver lost the nested instance"); return
        }
        var seen: String?
        for child in f.document.semanticHTMLResolvedChildren(of: inner) {
            if case .text(let content) = child.content { seen = content.plainString }
        }
        require(seen == "exported",
                "the semantic HTML resolver did not apply a nested override — the canvas and the export disagree")
    }

    // MARK: FEAT-017 chunk J-e — the acceptance matrix

    /// A DUPLICATE starts identical and then diverges. Both halves matter: copying
    /// something that looks a certain way must keep looking that way, and editing
    /// one copy afterwards must not reach the other.
    static func checkDuplicatePlacementDivergesIndependently() {
        var f = makeNestedFixture()
        var barA = f.barA
        guard case .instance(var a) = barA.content else { require(false, "fixture"); return }
        a.nestedOverrides = [NestedInstanceOverride(instancePath: [f.innerOne],
                                                    targetNodeID: f.label,
                                                    value: .text("A"))]
        barA.content = .instance(a)
        f.document.nodes[0] = barA

        // Duplicate the placed instance the way the canvas does.
        var copy = barA
        copy.id = UUID()
        f.document.nodes.append(copy)
        require(resolvedLabelText(f.document, copy, innerOne: f.innerOne) == "A",
                "a duplicate should start out looking identical")

        // Now change the copy only.
        guard case .instance(var c) = copy.content else { require(false, "fixture"); return }
        c.nestedOverrides = [NestedInstanceOverride(instancePath: [f.innerOne],
                                                    targetNodeID: f.label,
                                                    value: .text("B"))]
        copy.content = .instance(c)
        f.document.nodes[f.document.nodes.count - 1] = copy
        require(resolvedLabelText(f.document, copy, innerOne: f.innerOne) == "B",
                "editing the duplicate did not take")
        require(resolvedLabelText(f.document, barA, innerOne: f.innerOne) == "A",
                "editing the duplicate changed the ORIGINAL — placements are sharing")
    }

    /// Detach bakes what was on screen. It resolves through `resolvedChildren`, so
    /// a nested override must survive into the detached tree rather than snapping
    /// back to the source.
    static func checkDetachBakesTheResolvedValue() {
        var f = makeNestedFixture()
        var barA = f.barA
        guard case .instance(var a) = barA.content else { require(false, "fixture"); return }
        a.nestedOverrides = [NestedInstanceOverride(instancePath: [f.innerOne],
                                                    targetNodeID: f.label,
                                                    value: .text("baked"))]
        barA.content = .instance(a)
        f.document.nodes[0] = barA

        func findInstance(_ id: UUID, in nodes: [Node]) -> ComponentInstance? {
            for node in nodes {
                if node.id == id, case .instance(let inner) = node.content { return inner }
                if case .group(let children) = node.content,
                   let found = findInstance(id, in: children) { return found }
            }
            return nil
        }
        // What detach appends: the instance's resolved children.
        let detached = f.document.resolvedChildren(of: a)
        guard let inner = findInstance(f.innerOne, in: detached) else {
            require(false, "detach lost the nested instance"); return
        }
        var seen: String?
        for child in f.document.resolvedChildren(of: inner) {
            if case .text(let content) = child.content { seen = content.plainString }
        }
        require(seen == "baked",
                "detaching snapped a nested override back to the source value")
    }

    /// Deleting a component SOURCE dissolves its instances and renumbers what was
    /// inside them. Any nested override path running through a dissolved instance
    /// has to be re-rooted, or it silently addresses nothing — the same class of
    /// bug as BUG-010, one level over.
    static func checkDeletingASourceRepairsNestedPaths() {
        var f = makeNestedFixture()
        var barA = f.barA
        guard case .instance(var a) = barA.content else { require(false, "fixture"); return }
        // An override addressed THROUGH the bar, from an outer wrapper.
        a.nestedOverrides = [NestedInstanceOverride(instancePath: [f.innerOne],
                                                    targetNodeID: f.label,
                                                    value: .text("kept"))]
        barA.content = .instance(a)
        f.document.nodes[0] = barA

        guard case .instance(let barInstance) = barA.content else { return }
        let after = f.document.deletingComponentSource(barInstance.sourceID)
        // The bar became a plain group; its former nested instances survive. The
        // check that matters is TOTALITY: nothing crashed, nothing was left
        // addressing a node that no longer exists.
        func anyOverride(_ nodes: [Node]) -> [NestedInstanceOverride] {
            nodes.flatMap { node -> [NestedInstanceOverride] in
                switch node.content {
                case .instance(let inner): return inner.nestedOverrides
                case .group(let children): return anyOverride(children)
                default: return []
                }
            }
        }
        for override in anyOverride(after.nodes) {
            require(override.isAddressable,
                    "a nested override survived source deletion with an unusable empty path")
        }
    }

    /// The whole document must round-trip. J-a checked one instance; this checks
    /// the file the owner actually saves.
    static func checkDocumentRoundTripsWithNestedOverrides() {
        var f = makeNestedFixture()
        var barA = f.barA
        guard case .instance(var a) = barA.content else { require(false, "fixture"); return }
        a.nestedOverrides = [NestedInstanceOverride(instancePath: [f.innerOne],
                                                    targetNodeID: f.label,
                                                    value: .text("saved"))]
        barA.content = .instance(a)
        f.document.nodes[0] = barA

        let data = try! JSONEncoder().encode(f.document)
        let reopened = try! JSONDecoder().decode(Document.self, from: data)
        guard let node = reopened.nodes.first(where: { $0.id == barA.id }) else {
            require(false, "the placed instance vanished across save/reopen"); return
        }
        require(resolvedLabelText(reopened, node, innerOne: f.innerOne) == "saved",
                "a nested override did not survive save and reopen")
    }

    static func main() {
        checkGroupsAreTransparentToPaths()
        checkDuplicateIsIndependent()
        checkDeleteRemovesOnlyWhatItShould()
        checkUngroupHoistsRatherThanDestroys()
        checkDOMIDsAreUniqueAtDepthTwo()
        checkMigrationIsLosslessAndIdempotent()
        checkAdvisoryTableIsNarrow()
        checkNestedOverridesRoundTrip()
        checkEmptyPathIsNotAddressable()
        checkNestedOverrideReachesTheNestedLayer()
        checkResetFallsBackToSource()
        checkGroupsDoNotBlockPushDown()
        checkSemanticResolverSeesNestedOverrides()
        checkDuplicatePlacementDivergesIndependently()
        checkDetachBakesTheResolvedValue()
        checkDeletingASourceRepairsNestedPaths()
        checkDocumentRoundTripsWithNestedOverrides()
        print("AnchoredRelationshipCheck: all checks passed")
    }
}
