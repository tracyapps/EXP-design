import Foundation
import CoreGraphics

/// Shared policy for menus, Inspector and mutations. A selected folder is an
/// explicit scope; incompatible/hidden/locked contents never vanish silently.
struct VectorOperationSelection {
    let roots: [Node]
    let shapes: [Node]

    static func closed(in index: NodeTreeIndex, selected: Set<UUID>,
                       includingGroups: Bool = false) -> Self? {
        guard !selected.isEmpty, selected.allSatisfy({ index.entries[$0] != nil }) else { return nil }
        let roots = selected.filter { !index.hasSelectedAncestor($0, selectedIDs: selected) }
            .sorted { index.entries[$0]!.paintOrder < index.entries[$1]!.paintOrder }
            .map { index.entries[$0]!.node }
        if !includingGroups && roots.count != selected.count { return nil }
        var shapes: [Node] = []
        func collect(_ node: Node) -> Bool {
            guard node.isVisible, !node.isLocked, !node.isMask, !node.isMaskShape else { return false }
            if case .group(let children) = node.content {
                guard includingGroups, node.opacity == 1, node.blendMode == .normal,
                      !node.effects.contains(where: { $0.isEnabled }),
                      node.autoPadding?.fill == nil,
                      (node.autoPadding?.strokeWidth ?? 0) == 0 else { return false }
                return children.allSatisfy(collect)
            }
            guard VectorPathGeometry.isClosedVector(node.content) else { return false }
            shapes.append(node)
            return true
        }
        for root in roots {
            guard index.ancestorGroups(of: root.id).allSatisfy({ $0.isVisible && !$0.isLocked }),
                  collect(root) else { return nil }
        }
        return Self(roots: roots, shapes: shapes)
    }
}

enum VectorShapeEditing {
    struct Edit {
        let nodes: [Node]
        let selection: Set<UUID>
        let removedIDs: Set<UUID>
    }

    static func documentPath(_ node: Node, index: NodeTreeIndex) -> CGPath? {
        guard let shape = VectorPathGeometry.pathShape(from: node.content, size: node.frame.size) else { return nil }
        return VectorPathGeometry.map(VectorPathGeometry.cgPath(from: shape)) { point in
            var result = VectorPathGeometry.pointToParent(point, node: node)
            for parent in index.ancestorGroups(of: node.id).reversed() {
                result = VectorPathGeometry.pointToParent(result, node: parent)
            }
            return result
        }
    }

    static func unite(_ nodes: [Node], selected: Set<UUID>) -> Edit? {
        let index = NodeTreeIndex(nodes)
        guard let operands = VectorOperationSelection.closed(in: index, selected: selected, includingGroups: true),
              operands.shapes.count >= 2, let style = operands.shapes.last,
              let identity = operands.roots.last,
              let sourceStyle = VectorPathGeometry.pathShape(from: style.content, size: style.frame.size) else { return nil }
        let paths = operands.shapes.compactMap { documentPath($0, index: index) }
        guard paths.count == operands.shapes.count else { return nil }
        let combined = paths.dropFirst().reduce(paths[0]) { $0.union($1, using: .winding) }
        let parents = Set(operands.roots.map { index.entries[$0.id]!.ancestors.last })
        let chain = parents.count == 1 ? index.ancestorGroups(of: identity.id) : []
        let output = VectorPathGeometry.map(combined) { point in
            chain.reduce(point) { VectorPathGeometry.pointFromParent($0, node: $1) }
        }
        guard var converted = VectorPathGeometry.pathShape(from: output, fill: sourceStyle.fill,
                                                            stroke: sourceStyle.stroke, strokeWidth: sourceStyle.strokeWidth,
                                                            strokeAlignment: sourceStyle.effectiveStrokeAlignment) else { return nil }
        VectorPathGeometry.copyStrokeStyle(from: sourceStyle, to: &converted.shape)
        // Preserve the selected folder's identity/metadata, while adopting the
        // frontmost shape's appearance, like Unite's existing style rule.
        var result = identity
        result.frame = converted.bounds; result.content = .path(converted.shape)
        result.rotation = 0; result.flipH = false; result.flipV = false
        result.autoLayout = nil; result.autoPadding = nil
        result.opacity = style.opacity; result.effects = style.effects; result.blendMode = style.blendMode
        var removed = Set<UUID>()
        func collectIDs(_ node: Node) {
            removed.insert(node.id)
            if case .group(let children) = node.content { children.forEach(collectIDs) }
        }
        operands.roots.forEach(collectIDs); removed.remove(result.id)
        let ids = Set(operands.roots.map(\.id))
        func replace(_ array: [Node]) -> [Node] {
            var output: [Node] = []
            let insertionID = array.last(where: { ids.contains($0.id) })?.id
            for var node in array {
                if ids.contains(node.id) {
                    if node.id == insertionID { output.append(result) }
                } else {
                    if case .group(let children) = node.content { node.content = .group(children: replace(children)) }
                    output.append(node)
                }
            }
            return output
        }
        let edited: [Node]
        if parents.count == 1 { edited = replace(nodes) }
        else { edited = replacing(nodes, with: Dictionary(uniqueKeysWithValues: ids.map { ($0, []) })) + [result] }
        return Edit(nodes: edited, selection: [result.id], removedIDs: removed)
    }

    /// The straight line extends through each selected shape. Geometry stays in
    /// its original parent, honoring both node and ancestor transforms.
    static func cut(_ nodes: [Node], selected: Set<UUID>, from start: CGPoint, to end: CGPoint) -> Edit? {
        KnifeEditing.cut(nodes, selected: selected, samples: [start,end], straight: true)
    }

    private static func replacing(_ nodes: [Node], with replacements: [UUID: [Node]]) -> [Node] {
        nodes.flatMap { node -> [Node] in
            if let replacement = replacements[node.id] { return replacement }
            var copy = node
            if case .group(let children) = node.content { copy.content = .group(children: replacing(children, with: replacements)) }
            return [copy]
        }
    }
}
