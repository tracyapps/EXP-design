import Foundation
import CoreGraphics

/// A read-only view of one editable tree. Build once per model revision rather
/// than walking the entire document for every selected layer and Inspector field.
struct NodeTreeIndex {
    struct Entry {
        let node: Node
        let ancestors: [UUID]
        let offset: CGPoint
        let ancestorRotation: Double
        let paintOrder: Int
    }

    private(set) var entries: [UUID: Entry] = [:]

    init(_ nodes: [Node]) {
        var ancestors: [UUID] = []
        func walk(_ nodes: [Node], offset: CGPoint, rotation: Double) {
            for node in nodes {
                // Match the existing depth-first lookup if an invalid tree repeats an id.
                if entries[node.id] == nil {
                    entries[node.id] = Entry(node: node, ancestors: ancestors,
                                             offset: offset, ancestorRotation: rotation, paintOrder: entries.count)
                }
                if case .group(let children) = node.content {
                    ancestors.append(node.id)
                    walk(children, offset: CGPoint(x: offset.x + node.frame.minX,
                                                   y: offset.y + node.frame.minY),
                         rotation: rotation + node.rotation)
                    ancestors.removeLast()
                }
            }
        }
        walk(nodes, offset: .zero, rotation: 0)
    }

    func hasSelectedAncestor(_ id: UUID, selectedIDs: Set<UUID>) -> Bool {
        entries[id]?.ancestors.contains(where: selectedIDs.contains) ?? false
    }

    func ancestorGroups(of id: UUID) -> [Node] {
        entries[id]?.ancestors.compactMap { entries[$0]?.node } ?? []
    }
}

/// Selection-derived reads share the same snapshot, including recursive style
/// targets and geometry. No observable state is changed when a field reads it.
final class NodeSelectionReadSnapshot {
    let selectedNodes: [Node]
    let rootIDs: Set<UUID>
    let transformIDs: [UUID]
    let documentNodes: [Node]
    let styleNodes: [Node]
    lazy var bounds: CGRect? = SelectionTransform.unionBounds(documentNodes)

    init(index: NodeTreeIndex, selectedIDs: Set<UUID>) {
        selectedNodes = selectedIDs.compactMap { index.entries[$0]?.node }
        rootIDs = selectedIDs.filter {
            index.entries[$0] != nil && !index.hasSelectedAncestor($0, selectedIDs: selectedIDs)
        }
        transformIDs = rootIDs.filter { index.entries[$0]?.ancestorRotation == 0 }
        documentNodes = transformIDs.compactMap {
            guard let entry = index.entries[$0] else { return nil }
            var node = entry.node
            node.frame = node.frame.offsetBy(dx: entry.offset.x, dy: entry.offset.y)
            return node
        }
        var targets: [Node] = []
        func append(_ node: Node) {
            targets.append(node)
            if case .group(let children) = node.content {
                for child in children { append(child) }
            }
        }
        for id in rootIDs {
            if let node = index.entries[id]?.node { append(node) }
        }
        styleNodes = targets
    }
}

/// Each canvas/panel owns a cache. The caller's key must include document identity,
/// revision, page, editing scope, and component state. Camera changes are absent.
final class NodeTreeReadCache<Key: Equatable> {
    private var key: Key?
    private var index = NodeTreeIndex([])
    private var selectedIDs: Set<UUID>?
    private var snapshot: NodeSelectionReadSnapshot?

    func tree(for key: Key, nodes: () -> [Node]) -> NodeTreeIndex {
        if self.key != key {
            index = NodeTreeIndex(nodes())
            self.key = key
            selectedIDs = nil
            snapshot = nil
        }
        return index
    }

    func selection(for key: Key, selectedIDs: Set<UUID>, nodes: () -> [Node]) -> NodeSelectionReadSnapshot {
        let index = tree(for: key, nodes: nodes)
        if self.selectedIDs != selectedIDs || snapshot == nil {
            snapshot = NodeSelectionReadSnapshot(index: index, selectedIDs: selectedIDs)
            self.selectedIDs = selectedIDs
        }
        return snapshot!
    }
}

enum NodeTreeMutation {
    /// Apply a batch in one tree traversal; only changed group arrays are copied.
    /// Geometry edits visit explicit child targets even when their parent is also
    /// targeted. Style callers pass roots and apply their existing subtree rule.
    @discardableResult
    static func apply(_ ids: Set<UUID>, in nodes: inout [Node],
                      _ change: (inout Node) -> Void) -> Bool {
        guard !ids.isEmpty else { return false }
        var changed = false
        for i in nodes.indices {
            if ids.contains(nodes[i].id) { change(&nodes[i]); changed = true }
            if case .group(var children) = nodes[i].content,
               apply(ids, in: &children, change) {
                nodes[i].content = .group(children: children)
                changed = true
            }
        }
        return changed
    }
}
