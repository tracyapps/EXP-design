//
//  AutoLayoutEngine.swift
//  EXP [design]
//
//  The reflow pass for frames. A `.group` node can carry two independent traits:
//   • `autoLayout`  — STACK the children along an axis (gap / distribution / align).
//   • `autoPadding` — HUG the children with per-side padding (+ a background).
//  A frame may use either, both, or neither. This runs bottom-up so a child frame
//  sizes itself before its parent measures it — so a change deep inside (text
//  growing, a tab renamed) ripples outward through nested bars / buttons.
//
//  Pure and idempotent: laying out an already-laid-out tree yields the same tree,
//  so it's safe to run on every commit.
//
//  Geometry: children live in the group's LOCAL space (origin at the group's
//  top-left — the same space `.group` draws them in). A hugging frame keeps its
//  top-left origin and grows right/down.
//

import Foundation
import CoreGraphics

enum AutoLayoutEngine {

    /// Reflow every frame in the tree (bottom-up). Plain groups / leaves pass through.
    static func reflowed(_ nodes: [Node]) -> [Node] {
        // Fast path: if no node in the tree manages a frame, reflow is the identity.
        // Returning the input avoids rebuilding the whole tree (and its per-node
        // allocations) on every commit / instance-resolve for the common case of
        // plain groups and leaves — `reflow` would otherwise re-wrap every group.
        guard nodes.contains(where: hasManagedFrame) else { return nodes }
        return nodes.map { reflow($0) }
    }

    /// True if this node (or any descendant) carries auto-layout or auto-padding —
    /// i.e. anything `reflow` would actually change.
    private static func hasManagedFrame(_ node: Node) -> Bool {
        if node.autoLayout != nil || node.autoPadding != nil { return true }
        if case .group(let kids) = node.content { return kids.contains(where: hasManagedFrame) }
        return false
    }

    private static func reflow(_ node: Node) -> Node {
        guard case .group(let children) = node.content else { return node }
        let laid = children.map { reflow($0) }            // size nested frames first
        var n = node
        n.content = .group(children: laid)
        if let al = node.autoLayout {
            n = stack(n, al, pad: node.autoPadding, children: laid)
        } else if let pad = node.autoPadding {
            n = padBlock(n, pad, children: laid)
        }
        return n
    }

    // MARK: Stack (autoLayout) — optionally inset by autoPadding

    static func stack(_ node: Node, _ al: AutoLayout, pad: AutoPadding?, children: [Node]) -> Node {
        let horizontal = al.direction == .horizontal

        // Total inset from the frame edge to the content = margin + padding (the
        // background box sits at the margin inset; padding is inside that).
        func inset(_ pad: CGFloat, _ margin: CGFloat) -> CGFloat { pad + margin }
        let padPrimaryStart = horizontal ? inset(pad?.paddingLeft ?? 0, pad?.marginLeft ?? 0)
                                         : inset(pad?.paddingTop ?? 0, pad?.marginTop ?? 0)
        let padPrimaryEnd   = horizontal ? inset(pad?.paddingRight ?? 0, pad?.marginRight ?? 0)
                                         : inset(pad?.paddingBottom ?? 0, pad?.marginBottom ?? 0)
        let padCrossStart   = horizontal ? inset(pad?.paddingTop ?? 0, pad?.marginTop ?? 0)
                                         : inset(pad?.paddingLeft ?? 0, pad?.marginLeft ?? 0)
        let padCrossEnd     = horizontal ? inset(pad?.paddingBottom ?? 0, pad?.marginBottom ?? 0)
                                         : inset(pad?.paddingRight ?? 0, pad?.marginRight ?? 0)

        func primarySize(_ s: CGSize) -> CGFloat { horizontal ? s.width : s.height }
        func crossSize(_ s: CGSize) -> CGFloat { horizontal ? s.height : s.width }

        // Order items by their CURRENT position along the axis (not array/z-order),
        // so layout matches the canvas arrangement and dragging one past another
        // reorders the stack. Ties keep array order.
        let indexed = children.enumerated().filter { $0.element.isVisible }
        let items = indexed.sorted { a, b in
            let pa = horizontal ? a.element.frame.minX : a.element.frame.minY
            let pb = horizontal ? b.element.frame.minX : b.element.frame.minY
            if pa != pb { return pa < pb }
            return a.offset < b.offset
        }.map { $0.element }

        guard !items.isEmpty else {
            var n = node
            let w = horizontal ? padPrimaryStart + padPrimaryEnd : padCrossStart + padCrossEnd
            let h = horizontal ? padCrossStart + padCrossEnd : padPrimaryStart + padPrimaryEnd
            n.frame.size = CGSize(width: max(1, w), height: max(1, h))
            return n
        }

        let primarySizes = items.map { primarySize($0.frame.size) }
        let maxCross = items.map { crossSize($0.frame.size) }.max() ?? 0
        let totalChildren = primarySizes.reduce(0, +)
        let n = items.count

        let framePrimary: CGFloat
        switch al.distribution {
        case .packed:
            let content = totalChildren + al.gap * CGFloat(max(0, n - 1))
            framePrimary = padPrimaryStart + content + padPrimaryEnd
        case .spaceBetween:
            framePrimary = max(primarySize(node.frame.size),
                               padPrimaryStart + totalChildren + padPrimaryEnd)
        }
        let frameCross = padCrossStart + maxCross + padCrossEnd

        var primaryPos: [CGFloat] = []
        switch al.distribution {
        case .packed:
            let content = totalChildren + al.gap * CGFloat(max(0, n - 1))
            let slack = framePrimary - padPrimaryStart - padPrimaryEnd - content
            var cursor = padPrimaryStart + alignOffset(al.primary, slack)
            for s in primarySizes { primaryPos.append(cursor); cursor += s + al.gap }
        case .spaceBetween:
            let free = framePrimary - padPrimaryStart - padPrimaryEnd - totalChildren
            if n == 1 {
                primaryPos = [padPrimaryStart + alignOffset(al.primary, max(0, free))]
            } else {
                let gapEach = max(0, free / CGFloat(n - 1))
                var cursor = padPrimaryStart
                for s in primarySizes { primaryPos.append(cursor); cursor += s + gapEach }
            }
        }

        var newOrigin: [UUID: CGPoint] = [:]
        for (i, item) in items.enumerated() {
            let cross = padCrossStart + alignOffset(al.cross, maxCross - crossSize(item.frame.size))
            newOrigin[item.id] = horizontal
                ? CGPoint(x: primaryPos[i], y: cross)
                : CGPoint(x: cross, y: primaryPos[i])
        }

        let newChildren = children.map { child -> Node in
            guard let o = newOrigin[child.id] else { return child }
            var c = child; c.frame.origin = o; return c
        }

        var out = node
        out.content = .group(children: newChildren)
        out.frame.size = CGSize(width: horizontal ? framePrimary : frameCross,
                                height: horizontal ? frameCross : framePrimary)
        return out
    }

    // MARK: Pad block (autoPadding without autoLayout)

    /// Pad around the children's CURRENT arrangement (no stacking). Box model:
    /// frame = content + padding (the background box) + margin (transparent). The
    /// content stays fixed in document space; the frame grows outward.
    static func padBlock(_ node: Node, _ pad: AutoPadding, children: [Node]) -> Node {
        let visible = children.filter { $0.isVisible }
        var boundsOpt: CGRect?
        for f in visible.map(\.frame) { boundsOpt = boundsOpt?.union(f) ?? f }
        guard let bounds = boundsOpt else {
            var n = node
            n.frame.size = CGSize(width: max(1, pad.paddingLeft + pad.paddingRight + pad.marginW),
                                  height: max(1, pad.paddingTop + pad.paddingBottom + pad.marginH))
            return n
        }
        // Where the content's top-left sits inside the frame (margin then padding).
        let insetX = pad.marginLeft + pad.paddingLeft
        let insetY = pad.marginTop + pad.paddingTop
        let dx = insetX - bounds.minX
        let dy = insetY - bounds.minY
        let newChildren = children.map { child -> Node in
            var c = child; c.frame.origin = CGPoint(x: child.frame.minX + dx, y: child.frame.minY + dy); return c
        }
        var out = node
        out.content = .group(children: newChildren)
        // Anchor content in document space; frame grows outward as padding/margin change.
        out.frame.origin = CGPoint(x: node.frame.minX + bounds.minX - insetX,
                                   y: node.frame.minY + bounds.minY - insetY)
        out.frame.size = CGSize(
            width: bounds.width + pad.paddingLeft + pad.paddingRight + pad.marginW,
            height: bounds.height + pad.paddingTop + pad.paddingBottom + pad.marginH)
        return out
    }

    private static func alignOffset(_ a: AutoLayout.Align, _ slack: CGFloat) -> CGFloat {
        switch a {
        case .start:  return 0
        case .center: return slack / 2
        case .end:    return slack
        }
    }

    // MARK: Enabling auto padding (absorb an enclosing background)

    /// Turn on auto padding for a group. If a child is a filled shape that ENCLOSES
    /// the others (the classic button/pill background), absorb its fill/corner/stroke
    /// into the frame's background and drop it as a child — so the frame hugs the
    /// remaining CONTENT (the text) and the background is the frame itself (which
    /// then follows the padding). Shared by the canvas action AND the inspector
    /// toggle so both behave identically.
    static func enableAutoPadding(on g: inout Node) {
        guard case .group(var kids) = g.content else { g.autoPadding = AutoPadding(); return }
        var pad = AutoPadding()
        if kids.count >= 2, let bgIdx = backgroundChildIndex(in: kids),
           let style = backgroundStyle(of: kids[bgIdx]) {
            pad.fill = style.fill
            pad.cornerRadius = style.corner
            pad.stroke = style.stroke
            pad.strokeWidth = style.strokeWidth
            kids.remove(at: bgIdx)
        }
        g.content = .group(children: kids)
        g.autoPadding = pad
    }

    /// The child acting as the group's background: the largest filled shape that
    /// (roughly) encloses all the other children. nil if none qualifies.
    static func backgroundChildIndex(in kids: [Node]) -> Int? {
        var best: Int?
        var bestArea: CGFloat = 0
        for i in kids.indices {
            guard backgroundStyle(of: kids[i]) != nil else { continue }
            let others = kids.enumerated().filter { $0.offset != i }.map { $0.element.frame }
            var u: CGRect?
            for f in others { u = u?.union(f) ?? f }
            guard let union = u else { continue }
            let f = kids[i].frame
            let tol = max(2, min(f.width, f.height) * 0.1)
            guard f.insetBy(dx: -tol, dy: -tol).contains(union) else { continue }
            let area = f.width * f.height
            if area > bestArea { bestArea = area; best = i }
        }
        return best
    }

    /// The frame-style of a filled shape we can absorb as a frame background.
    static func backgroundStyle(of node: Node)
        -> (fill: Paint?, corner: CGFloat, stroke: RGBAColor?, strokeWidth: CGFloat)? {
        switch node.content {
        case .rectangle(let s): return (s.fill, s.cornerRadius, s.stroke, s.strokeWidth)
        case .ellipse(let s):   return (s.fill, 0, s.stroke, s.strokeWidth)
        case .path(let s):      return (s.fill, 0, s.stroke, s.strokeWidth)
        default:                return nil
        }
    }
}
