import Foundation
import CoreGraphics

extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize { CGSize(width: maxWidth ?? 20, height: 20) }
    func measuredSize(boxWidth: CGFloat) -> CGSize { measuredSize(maxWidth: boxWidth) }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

// The previous recursive reads form an independent behavior oracle and baseline.
private func find(_ id: UUID, in nodes: [Node]) -> Node? {
    for node in nodes {
        if node.id == id { return node }
        if case .group(let children) = node.content, let found = find(id, in: children) { return found }
    }
    return nil
}
private func chain(_ id: UUID, in nodes: [Node], ancestors: [Node] = []) -> [Node]? {
    for node in nodes {
        if node.id == id { return ancestors }
        if case .group(let children) = node.content,
           let found = chain(id, in: children, ancestors: ancestors + [node]) { return found }
    }
    return nil
}
private func legacyReads(_ nodes: [Node], ids: Set<UUID>) -> (transform: [Node], style: [Node]) {
    let roots = ids.filter { id in !(chain(id, in: nodes) ?? []).contains { ids.contains($0.id) } }
    let transform = roots.filter { id in
        find(id, in: nodes) != nil && (chain(id, in: nodes) ?? []).reduce(0) { $0 + $1.rotation } == 0
    }.compactMap { id -> Node? in
        guard var node = find(id, in: nodes) else { return nil }
        let off = (chain(id, in: nodes) ?? []).reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.frame.minX, y: $0.y + $1.frame.minY)
        }
        node.frame = node.frame.offsetBy(dx: off.x, dy: off.y)
        return node
    }
    func flatten(_ node: Node) -> [Node] {
        if case .group(let children) = node.content { return [node] + children.flatMap(flatten) }
        return [node]
    }
    return (transform, roots.compactMap { find($0, in: nodes) }.flatMap(flatten))
}

@main private enum NodeTreePerformanceCheck {
    static func main() throws {
        let leaf = Node(name: "Leaf", frame: CGRect(x: 3, y: 4, width: 10, height: 20),
                        content: .rectangle(RectangleShape()))
        let sibling = Node(name: "Sibling", frame: CGRect(x: 30, y: 5, width: 15, height: 25),
                           content: .ellipse(EllipseShape()))
        var inner = Node(name: "Inner", frame: CGRect(x: 10, y: 20, width: 100, height: 100),
                         content: .group(children: [leaf]))
        var outer = Node(name: "Outer", frame: CGRect(x: 100, y: 200, width: 200, height: 200),
                         content: .group(children: [inner, sibling]))
        let missing = UUID()
        let nodes = [outer]
        let index = NodeTreeIndex(nodes)
        require(index.entries[leaf.id]?.offset == CGPoint(x: 110, y: 220), "nested document offset")
        require(index.ancestorGroups(of: leaf.id).map(\.id) == [outer.id, inner.id], "ancestor order")
        require(index.entries[missing] == nil, "missing node")
        for ids: Set<UUID> in [[], [leaf.id], [leaf.id, sibling.id], [outer.id, leaf.id], [missing]] {
            let reads = NodeSelectionReadSnapshot(index: index, selectedIDs: ids)
            let old = legacyReads(nodes, ids: ids)
            require(Set(reads.documentNodes.map(\.id)) == Set(old.transform.map(\.id)), "transform membership")
            require(reads.bounds == SelectionTransform.unionBounds(old.transform), "geometry parity")
            require(Set(reads.styleNodes.map(\.id)) == Set(old.style.map(\.id)), "style target parity")
        }
        let parentAndChild = NodeSelectionReadSnapshot(index: index, selectedIDs: [outer.id, leaf.id])
        require(parentAndChild.rootIDs == [outer.id] && parentAndChild.styleNodes.count == 4,
                "selected descendants must not be styled twice")
        outer.rotation = 30; outer.flipH = true
        inner.rotation = -30; outer.content = .group(children: [inner, sibling])
        let rotated = NodeTreeIndex([outer])
        require(rotated.entries[leaf.id]?.ancestorRotation == 0, "cancelled ancestor angles retain existing contract")
        require(rotated.ancestorGroups(of: leaf.id).first?.flipH == true, "flips survive indexed reads")
        require(NodeSelectionReadSnapshot(index: rotated, selectedIDs: [sibling.id]).transformIDs.isEmpty,
                "rotated-ancestor transform eligibility")

        struct Key: Equatable { let document: Int; let revision: Int; let page: Int; let scope: Int; let state: Int }
        let keys = [Key(document: 1, revision: 0, page: 0, scope: 0, state: 0),
                    Key(document: 1, revision: 1, page: 0, scope: 0, state: 0),
                    Key(document: 1, revision: 1, page: 1, scope: 0, state: 0),
                    Key(document: 1, revision: 1, page: 1, scope: 1, state: 0),
                    Key(document: 1, revision: 1, page: 1, scope: 1, state: 1),
                    Key(document: 2, revision: 1, page: 1, scope: 1, state: 1)]
        let cache = NodeTreeReadCache<Key>()
        var builds = 0
        for (i, key) in keys.enumerated() {
            var edited = leaf; edited.frame.origin.x = CGFloat(i * 10)
            let first = cache.selection(for: key, selectedIDs: [leaf.id]) { builds += 1; return [edited] }
            require(first.bounds?.minX == CGFloat(i * 10), "cache invalidation: \(i)")
            let again = cache.selection(for: key, selectedIDs: [leaf.id]) { fatalError("warm cache rebuilt") }
            require(first === again, "warm selection snapshot reuse")
            let empty = cache.selection(for: key, selectedIDs: []) { fatalError("selection-only change rebuilt tree") }
            require(empty.bounds == nil && empty.styleNodes.isEmpty, "deselect cache invalidation")
        }
        require(builds == keys.count, "one tree build per key")

        var moved = nodes
        NodeTreeMutation.apply([inner.id, sibling.id], in: &moved) { $0.frame.origin.x += 7 }
        require(find(inner.id, in: moved)?.frame.minX == 17, "nested move")
        require(find(sibling.id, in: moved)?.frame.minX == 37, "sibling move")
        require(find(leaf.id, in: moved)?.frame == leaf.frame, "untargeted child geometry")
        require(!NodeTreeMutation.apply([missing], in: &moved) { _ in fatalError("missing mutation") }, "missing-id no-op")
        var styled = nodes; var counts: [UUID: Int] = [:]
        func style(_ node: inout Node) {
            counts[node.id, default: 0] += 1; node.opacity = 0.4
            if case .group(var children) = node.content {
                for i in children.indices { style(&children[i]) }
                node.content = .group(children: children)
            }
        }
        NodeTreeMutation.apply(parentAndChild.rootIDs, in: &styled, style)
        require(counts.count == 4 && counts.values.allSatisfy { $0 == 1 }, "one style application per descendant")
        require(find(leaf.id, in: styled)?.opacity == 0.4, "nested style result")
        print("PASS: nested selection, transforms/flips, style targets, batch edits, revision/page/scope/state/document invalidation")

        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let document = try JSONDecoder().decode(Document.self, from: data)
            let nodes = document.pages[0].nodes
            let icons = Set(nodes.filter { $0.name.hasPrefix("np_") }.map(\.id))
            require(!icons.isEmpty, "benchmark has no icon selection")
            let repeats = 20
            var checksum = 0
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<repeats {
                let reads = legacyReads(nodes, ids: icons)
                checksum += reads.style.count
                checksum += Int(SelectionTransform.unionBounds(reads.transform)?.width ?? 0)
            }
            let before = ProcessInfo.processInfo.systemUptime - start
            let cache = NodeTreeReadCache<Int>()
            let afterStart = ProcessInfo.processInfo.systemUptime
            for _ in 0..<repeats {
                let reads = cache.selection(for: 0, selectedIDs: icons) { nodes }
                checksum += reads.styleNodes.count
                checksum += Int(reads.bounds?.width ?? 0)
            }
            let after = ProcessInfo.processInfo.systemUptime - afterStart
            let indexed = cache.selection(for: 0, selectedIDs: icons) { nodes }
            let old = legacyReads(nodes, ids: icons)
            require(indexed.bounds == SelectionTransform.unionBounds(old.transform), "stress selection bounds parity")
            require(Set(indexed.styleNodes.map(\.id)) == Set(old.style.map(\.id)), "stress style parity")
            print(String(format: "STRESS: %d roots, %d total nodes, %d selected icons; %d Inspector read sets: legacy %.1fms, indexed %.1fms (%.1fx); checksum %d",
                         nodes.count, NodeTreeIndex(nodes).entries.count, icons.count, repeats,
                         before * 1000, after * 1000, before / max(after, 0.000001), checksum))
            // One drag tick previously reflowed the complete tree per icon.
            // Publishing/SwiftUI costs are deliberately outside this benchmark.
            var oldMove = nodes
            func legacyMove(_ id: UUID, in nodes: inout [Node]) -> Bool {
                for i in nodes.indices {
                    if nodes[i].id == id {
                        nodes[i].frame.origin.x += 12; nodes[i].frame.origin.y += 8
                        return true
                    }
                    if case .group(var children) = nodes[i].content, legacyMove(id, in: &children) {
                        nodes[i].content = .group(children: children); return true
                    }
                }
                return false
            }
            let moveStart = ProcessInfo.processInfo.systemUptime
            for id in icons { _ = legacyMove(id, in: &oldMove); oldMove = document.reflowed(oldMove) }
            let moveBefore = ProcessInfo.processInfo.systemUptime - moveStart
            var newMove = nodes
            let newMoveStart = ProcessInfo.processInfo.systemUptime
            NodeTreeMutation.apply(icons, in: &newMove) {
                $0.frame.origin.x += 12; $0.frame.origin.y += 8
            }
            newMove = document.reflowed(newMove)
            let moveAfter = ProcessInfo.processInfo.systemUptime - newMoveStart
            let moveEncoder = JSONEncoder(); moveEncoder.outputFormatting = [.sortedKeys]
            let sameMove = try moveEncoder.encode(oldMove) == moveEncoder.encode(newMove)
            require(sameMove, "stress move must preserve complete resulting tree")
            print(String(format: "STRESS move tick including reflow: legacy %.1fms, batch %.1fms (%.1fx); full document JSON parity PASS",
                         moveBefore * 1000, moveAfter * 1000, moveBefore / max(moveAfter, 0.000001)))
            // Compare complete resulting JSON for a real bulk fill edit.
            var legacy = nodes; var batch = nodes
            func recolor(_ node: inout Node) {
                switch node.content {
                case .path(var shape): shape.fill = .solid(RGBAColor(r: 0.2, g: 0.6, b: 0.9, a: 1)); node.content = .path(shape)
                case .group(var children): for i in children.indices { recolor(&children[i]) }; node.content = .group(children: children)
                default: break
                }
            }
            func mutate(_ id: UUID, _ nodes: inout [Node]) -> Bool {
                for i in nodes.indices {
                    if nodes[i].id == id { recolor(&nodes[i]); return true }
                    if case .group(var children) = nodes[i].content, mutate(id, &children) {
                        nodes[i].content = .group(children: children); return true
                    }
                }
                return false
            }
            let fillStart = ProcessInfo.processInfo.systemUptime
            for id in indexed.rootIDs { _ = mutate(id, &legacy) }
            let fillBefore = ProcessInfo.processInfo.systemUptime - fillStart
            let fillAfterStart = ProcessInfo.processInfo.systemUptime
            NodeTreeMutation.apply(indexed.rootIDs, in: &batch, recolor)
            let fillAfter = ProcessInfo.processInfo.systemUptime - fillAfterStart
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let sameJSON = try encoder.encode(legacy) == encoder.encode(batch)
            require(sameJSON, "stress bulk fill must preserve all document data")
            print(String(format: "STRESS fill traversal: legacy %.1fms, batch %.1fms (%.1fx); full document JSON parity PASS",
                         fillBefore * 1000, fillAfter * 1000, fillBefore / max(fillAfter, 0.000001)))
        }
    }
}
