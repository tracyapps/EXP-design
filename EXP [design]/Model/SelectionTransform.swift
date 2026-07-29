//
//  SelectionTransform.swift
//  EXP [design]
//
//  Pure geometry for scaling and rotating a SELECTION as a unit — multiple
//  top-level nodes at once, or a single group (scaling its children). Shared by
//  the canvas (live handle drags) and the Inspector (numeric W/H/rotation), so
//  both paths use exactly the same math.
//
//  Coordinate facts this relies on (see CanvasView):
//   • A top-level node's `frame` is in document space.
//   • A group's children live in the group's LOCAL space — a child point p maps
//     to the parent space as p + group.frame.origin. So scaling a group about an
//     external anchor = scale the group's frame about that anchor AND scale every
//     descendant's local frame/points about the group's local origin (0,0).
//   • Path points and line endpoints are in the node's local space (relative to
//     frame.origin), so they scale about (0,0).
//   • `node.rotation` is applied by the renderer about the node's frame centre,
//     so rotating a selection = move each node's centre about the pivot AND add
//     the same delta to each node's own rotation.
//

import Foundation
import CoreGraphics

enum SelectionTransform {

    enum AlignEdge {
        case left, hCenter, right, top, vCenter, bottom
    }

    // MARK: Bounds

    /// The axis-aligned document-space bounds a node occupies on screen. For a
    /// group this is the union of its descendants (so the box matches what's
    /// drawn even if the stored group frame lags), except managed auto-layout /
    /// auto-padding groups whose frame is the visible control surface. A node's
    /// own rotation is applied about its frame centre, so the box contains
    /// rotated content too.
    static func visualBounds(_ node: Node) -> CGRect {
        func bounds(_ n: Node, _ parentOrigin: CGPoint) -> CGRect {
            let absFrame = n.frame.offsetBy(dx: parentOrigin.x, dy: parentOrigin.y)
            var inner = absFrame
            if case .group(let kids) = n.content, !kids.isEmpty {
                if n.autoLayout != nil || n.autoPadding != nil {
                    inner = absFrame
                } else {
                    var u: CGRect?
                    for k in kids { let b = bounds(k, absFrame.origin); u = u?.union(b) ?? b }
                    inner = u ?? absFrame
                }
            }
            guard n.rotation != 0 else { return inner }
            // Rotate the (unrotated) bounds' corners about the node centre and take
            // their AABB — the box still encloses the rotated content.
            let c = CGPoint(x: absFrame.midX, y: absFrame.midY)
            let corners = [
                CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY),
                CGPoint(x: inner.maxX, y: inner.maxY), CGPoint(x: inner.minX, y: inner.maxY)
            ].map { rotate($0, around: c, deg: n.rotation) }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!,
                          width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        return bounds(node, .zero)
    }

    /// Union of `visualBounds` over several top-level nodes.
    static func unionBounds(_ nodes: [Node]) -> CGRect? {
        var u: CGRect?
        for n in nodes { let b = visualBounds(n); u = u?.union(b) ?? b }
        return u
    }

    // MARK: Align & distribute

    /// Translation deltas that align already-resolved visual bounds to `reference`.
    /// The caller chooses the shared coordinate space (a group's local space or
    /// document space), then writes each delta back through that node's parent.
    /// Keeping this math pure prevents nested canvas and inspector paths from
    /// quietly drifting back to top-level-only frame indexing.
    static func alignmentOffsets(_ items: [(id: UUID, bounds: CGRect)],
                                 edge: AlignEdge, reference: CGRect) -> [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        for item in items {
            let dx: CGFloat
            let dy: CGFloat
            switch edge {
            case .left:
                dx = reference.minX - item.bounds.minX; dy = 0
            case .hCenter:
                dx = reference.midX - item.bounds.midX; dy = 0
            case .right:
                dx = reference.maxX - item.bounds.maxX; dy = 0
            case .top:
                dx = 0; dy = reference.minY - item.bounds.minY
            case .vCenter:
                dx = 0; dy = reference.midY - item.bounds.midY
            case .bottom:
                dx = 0; dy = reference.maxY - item.bounds.maxY
            }
            result[item.id] = CGPoint(x: dx, y: dy)
        }
        return result
    }

    /// Translation deltas that equalize the gaps between visual bounds while
    /// keeping the two outer items fixed. Negative gaps are intentional when the
    /// selection is too tight and the items must overlap evenly.
    static func distributionOffsets(_ items: [(id: UUID, bounds: CGRect)],
                                    horizontal: Bool) -> [UUID: CGPoint] {
        guard items.count >= 3 else { return [:] }
        let sorted = items.sorted {
            horizontal ? $0.bounds.minX < $1.bounds.minX
                       : $0.bounds.minY < $1.bounds.minY
        }
        let span: CGFloat
        let used: CGFloat
        if horizontal {
            span = sorted.last!.bounds.maxX - sorted.first!.bounds.minX
            used = sorted.reduce(0) { $0 + $1.bounds.width }
        } else {
            span = sorted.last!.bounds.maxY - sorted.first!.bounds.minY
            used = sorted.reduce(0) { $0 + $1.bounds.height }
        }
        let gap = (span - used) / CGFloat(sorted.count - 1)
        var cursor = horizontal ? sorted.first!.bounds.minX : sorted.first!.bounds.minY
        var result: [UUID: CGPoint] = [:]
        for item in sorted {
            if horizontal {
                result[item.id] = CGPoint(x: cursor - item.bounds.minX, y: 0)
                cursor += item.bounds.width + gap
            } else {
                result[item.id] = CGPoint(x: 0, y: cursor - item.bounds.minY)
                cursor += item.bounds.height + gap
            }
        }
        return result
    }

    /// How far a node's outline paints beyond its geometry frame. Inside strokes
    /// add nothing; centered and outside strokes expand by their true outer reach.
    static func strokeOutset(for content: NodeContent) -> CGFloat {
        switch content {
        case .rectangle(let s): return s.strokeAlignment.reach(for: s.strokeWidth)
        case .ellipse(let s):   return s.strokeAlignment.reach(for: s.strokeWidth)
        case .polygon(let s):   return s.strokeAlignment.reach(for: s.strokeWidth)
        case .line(let s):      return s.strokeWidth / 2
        case .path(let s):      return s.effectiveStrokeAlignment.reach(for: s.strokeWidth)
        default:                return 0
        }
    }

    /// Inspector-facing outer bounds: the descendant union for groups, expanded
    /// to the painted outside edge of every outline. This deliberately excludes
    /// shadows/effects—the dimension is the object + outline, not a soft effect.
    static func paintedBounds(_ node: Node) -> CGRect {
        func bounds(_ n: Node, _ parentOrigin: CGPoint) -> CGRect {
            let absFrame = n.frame.offsetBy(dx: parentOrigin.x, dy: parentOrigin.y)
            var inner = absFrame.insetBy(dx: -strokeOutset(for: n.content),
                                         dy: -strokeOutset(for: n.content))
            if case .group(let kids) = n.content, !kids.isEmpty {
                if n.autoLayout != nil || n.autoPadding != nil {
                    inner = absFrame
                } else {
                    var union: CGRect?
                    for child in kids {
                        let b = bounds(child, absFrame.origin)
                        union = union?.union(b) ?? b
                    }
                    inner = union ?? absFrame
                }
            }
            guard n.rotation != 0 else { return inner }
            let center = CGPoint(x: absFrame.midX, y: absFrame.midY)
            let corners = [
                CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY),
                CGPoint(x: inner.maxX, y: inner.maxY), CGPoint(x: inner.minX, y: inner.maxY)
            ].map { rotate($0, around: center, deg: n.rotation) }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!,
                          width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        return bounds(node, .zero)
    }

    // MARK: Scale

    /// A copy of `base` scaled by (sx, sy) about document-space anchor `A`
    /// (a point that stays fixed — typically the opposite corner/edge of the
    /// selection box). Internal geometry (group children, path points, line
    /// endpoints) is scaled to match.
    static func scaled(_ base: Node, about A: CGPoint, sx: CGFloat, sy: CGFloat) -> Node {
        var n = base
        n.frame = CGRect(
            x: A.x + (base.frame.minX - A.x) * sx,
            y: A.y + (base.frame.minY - A.y) * sy,
            width: max(1, base.frame.width * sx),
            height: max(1, base.frame.height * sy)
        )
        scaleInternal(&n, sx, sy)
        return n
    }

    /// Scale geometry that lives in a node's LOCAL space (about its own origin),
    /// leaving `node.frame` to the caller.
    static func scaleInternal(_ node: inout Node, _ sx: CGFloat, _ sy: CGFloat) {
        switch node.content {
        case .path(var ps):
            ps.points = ps.points.map { scalePoint($0, sx, sy) }
            if let cs = ps.contours {
                ps.contours = cs.map { $0.map { scalePoint($0, sx, sy) } }
            }
            node.content = .path(ps)

        case .line(var ls):
            ls.start = CGPoint(x: ls.start.x * sx, y: ls.start.y * sy)
            ls.end   = CGPoint(x: ls.end.x * sx,   y: ls.end.y * sy)
            node.content = .line(ls)

        case .text(var tc):
            // Match single-node resize: a resized text box becomes fixed-width so
            // it keeps its frame instead of hugging one line.
            tc.box = .fixed
            node.content = .text(tc)

        case .group(var kids):
            for i in kids.indices {
                kids[i].frame = CGRect(
                    x: kids[i].frame.minX * sx,
                    y: kids[i].frame.minY * sy,
                    width: max(1, kids[i].frame.width * sx),
                    height: max(1, kids[i].frame.height * sy)
                )
                scaleInternal(&kids[i], sx, sy)
            }
            node.content = .group(children: kids)

        case .rectangle, .ellipse, .polygon, .instance, .image:
            break   // fully described by `frame`
        }
    }

    private static func scalePoint(_ p: PathPoint, _ sx: CGFloat, _ sy: CGFloat) -> PathPoint {
        var q = p
        q.point = CGPoint(x: p.point.x * sx, y: p.point.y * sy)
        q.controlIn = p.controlIn.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        q.controlOut = p.controlOut.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        return q
    }

    // MARK: Rotate

    /// Rotate `p` about `c` by `deg`, matching the canvas's flipped, clockwise-
    /// positive convention (identical to CanvasView.rotatePoint).
    static func rotate(_ p: CGPoint, around c: CGPoint, deg: Double) -> CGPoint {
        guard deg != 0 else { return p }
        let r = deg * .pi / 180, s = sin(r), co = cos(r)
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * co - dy * s, y: c.y + dx * s + dy * co)
    }

    /// A copy of `base` rotated by `deg` about document-space pivot `C`: its
    /// centre orbits the pivot and `deg` is added to its own rotation (so the
    /// renderer turns the content too — true for every shape incl. lines).
    static func rotated(_ base: Node, aboutDoc C: CGPoint, deg: Double) -> Node {
        var n = base
        let center = CGPoint(x: base.frame.midX, y: base.frame.midY)
        let nc = rotate(center, around: C, deg: deg)
        n.frame.origin = CGPoint(x: nc.x - base.frame.width / 2,
                                 y: nc.y - base.frame.height / 2)
        var rot = base.rotation + deg
        rot.formTruncatingRemainder(dividingBy: 360)
        if rot < 0 { rot += 360 }
        n.rotation = rot
        return n
    }
}
