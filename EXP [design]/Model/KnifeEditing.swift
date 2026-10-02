import Foundation
import CoreGraphics

enum KnifeScope: String, CaseIterable {
    case top, group, all
    var label: String {
        switch self { case .top: "Top layer"; case .group: "All within group"; case .all: "All layers / groups" }
    }
}

struct KnifeSettings {
    var shapes = true
    var lines = true
    var paths = true
    var images = false
    var scope: KnifeScope = .top
    static var allTypes: Self { Self(images: true) }
}

struct KnifeLinePreview {
    var x: Double
    var y: Double
    var angle: Double = 0
    var length: Double
    var endpoints: (CGPoint, CGPoint) {
        let a = angle * .pi / 180, dx = cos(a) * length / 2, dy = sin(a) * length / 2
        return (CGPoint(x: x - dx, y: y - dy), CGPoint(x: x + dx, y: y + dy))
    }
}

/// Knife follows sampled pointer positions. No curve fitting, smoothing, stroke
/// width or raster resampling changes the cutter. Straight commands extend a line.
enum KnifeEditing {
    static func eligible(_ node: Node, settings: KnifeSettings) -> Bool {
        guard node.isVisible, !node.isLocked else { return false }
        switch node.content {
        case .rectangle, .ellipse, .polygon: return settings.shapes
        case .line: return settings.lines
        case .path: return settings.paths
        case .image: return settings.images
        case .group(let children):
            guard node.isMask else { return false }
            func locked(_ n: Node) -> Bool {
                if n.isLocked { return true }
                if case .group(let kids) = n.content { return kids.contains(where: locked) }
                return false
            }
            return !children.contains(where: locked) && children.contains { eligible($0, settings: settings) }
        default: return false
        }
    }

    static func selectedRoots(_ index: NodeTreeIndex, selected: Set<UUID>) -> [Node]? {
        guard !selected.isEmpty else { return nil }
        var ids = Set<UUID>()
        for id in selected {
            guard let entry = index.entries[id] else { return nil }
            // Selecting the clipping shape cuts the whole masked artwork into
            // independently movable pieces, rather than two additive clips.
            let target = entry.node.isMaskShape
                ? index.ancestorGroups(of: id).last(where: \.isMask)?.id ?? id : id
            ids.insert(target)
        }
        ids = ids.filter { !index.hasSelectedAncestor($0, selectedIDs: ids) }
        let roots = ids.sorted { index.entries[$0]!.paintOrder < index.entries[$1]!.paintOrder }
            .map { index.entries[$0]!.node }
        guard roots.allSatisfy({ eligible($0, settings: .allTypes) &&
            index.ancestorGroups(of: $0.id).allSatisfy({ $0.isVisible && !$0.isLocked }) }) else { return nil }
        return roots
    }

    /// The silhouette used by mask rendering; nested masks keep their own clip.
    static func silhouette(_ node: Node) -> CGPath? {
        if let shape = VectorPathGeometry.pathShape(from: node.content, size: node.frame.size) {
            return VectorPathGeometry.cgPath(from: shape)
        }
        if case .image = node.content {
            return CGPath(rect: CGRect(origin: .zero, size: node.frame.size), transform: nil)
        }
        guard case .group(let kids) = node.content else { return nil }
        let visible = kids.filter { $0.isVisible && (!node.isMask || $0.isMaskShape) }
        let paths = visible.compactMap { child -> CGPath? in
            guard let path = silhouette(child) else { return nil }
            return VectorPathGeometry.map(path) { VectorPathGeometry.pointToParent($0, node: child) }
        }
        guard let first = paths.first else { return nil }
        return paths.dropFirst().reduce(first) { $0.union($1, using: .winding) }
    }

    static func worldPath(_ node: Node, index: NodeTreeIndex) -> CGPath? {
        guard let local = silhouette(node) else { return nil }
        return VectorPathGeometry.map(local) { point in
            index.ancestorGroups(of: node.id).reversed().reduce(VectorPathGeometry.pointToParent(point, node: node)) {
                VectorPathGeometry.pointToParent($0, node: $1)
            }
        }
    }

    static func candidates(_ index: NodeTreeIndex, settings: KnifeSettings) -> [Node] {
        index.entries.values.filter { entry in
            eligible(entry.node, settings: settings) && index.ancestorGroups(of: entry.node.id).allSatisfy {
                $0.isVisible && !$0.isLocked && !$0.isMask
            }
        }.sorted { $0.paintOrder < $1.paintOrder }.map(\.node)
    }

    static func hit(_ nodes: [Node], at point: CGPoint, settings: KnifeSettings) -> UUID? {
        let index = NodeTreeIndex(nodes)
        return candidates(index, settings: settings).reversed().first { node in
            guard let path = worldPath(node, index: index) else { return false }
            if VectorPathGeometry.isClosedVector(node.content) || node.isMask || { if case .image = node.content { return true }; return false }() {
                return path.contains(point, using: .winding)
            }
            return path.copy(strokingWithWidth: max(6, VectorPathGeometry.stroke(from: node.content)?.width ?? 0),
                             lineCap: .round, lineJoin: .round, miterLimit: 4).contains(point)
        }?.id
    }

    static func cut(_ nodes: [Node], selected: Set<UUID>? = nil, samples: [CGPoint],
                    straight: Bool = false, settings: KnifeSettings = .allTypes) -> VectorShapeEditing.Edit? {
        guard samples.count >= 2, samples.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let index = NodeTreeIndex(nodes)
        let roots: [Node]
        if let selected {
            guard let selection = selectedRoots(index, selected: selected) else { return nil }
            roots = selection
        } else { roots = candidates(index, settings: settings) }
        var hits: [(Node, [Node])] = []
        for node in roots {
            let chain = index.ancestorGroups(of: node.id)
            let local = samples.map { point in
                VectorPathGeometry.pointFromParent(chain.reduce(point) { VectorPathGeometry.pointFromParent($0, node: $1) }, node: node)
            }
            if let pieces = pieces(node, samples: local, straight: straight) { hits.append((node, pieces)) }
        }
        if selected == nil, let top = hits.last {
            switch settings.scope {
            case .top: hits = [top]
            case .group:
                if let group = index.entries[top.0.id]?.ancestors.first {
                    hits = hits.filter { index.entries[$0.0.id]?.ancestors.contains(group) == true }
                } else { hits = [top] }
            case .all: break
            }
        }
        guard !hits.isEmpty else { return nil }
        let replacements = Dictionary(uniqueKeysWithValues: hits.map { ($0.0.id, $0.1) })
        func replace(_ nodes: [Node]) -> [Node] {
            nodes.flatMap { node -> [Node] in
                if let pieces = replacements[node.id] { return pieces }
                var copy = node
                if case .group(let kids) = copy.content { copy.content = .group(children: replace(kids)) }
                return [copy]
            }
        }
        var selection = selected ?? []
        for (node, pieces) in hits {
            // Promotion of a selected mask child also removes its selection.
            let descendants = Set(index.entries.values.filter { $0.ancestors.contains(node.id) }.map { $0.node.id })
            selection.subtract(descendants); selection.remove(node.id)
            selection.formUnion(pieces.map(\.id))
        }
        return .init(nodes: replace(nodes), selection: selection, removedIDs: [])
    }

    private static func pieces(_ node: Node, samples: [CGPoint], straight: Bool) -> [Node]? {
        let closed = VectorPathGeometry.isClosedVector(node.content)
        if !closed && !node.isMask {
            switch node.content {
            case .image: break
            default: return KnifePathGeometry.cutOpen(node, samples: samples, straight: straight)
            }
        }
        guard let path = silhouette(node), let halves = straight
            ? VectorPathGeometry.split(path, from: samples[0], to: samples.last!)
            : KnifePathGeometry.split(path, samples: samples) else { return nil }
        if closed {
            guard let style = VectorPathGeometry.pathShape(from: node.content, size: node.frame.size) else { return nil }
            return halves.enumerated().compactMap { i, half in
                KnifePathGeometry.pathPiece(node, path: half, style: style, index: i, closed: true)
            }
        }
        // Images and mask containers use ordinary editable mask groups. Retain
        // full pixels/content underneath; moving a piece moves its pixels too.
        return halves.enumerated().compactMap { i, half in
            guard let clip = VectorPathGeometry.pathShape(from: half, fill: .white, stroke: .clear, strokeWidth: 0) else { return nil }
            var piece = i == 0 ? node : Document.duplicatingNode(node)
            var content = piece
            content.id = UUID(); content.name = node.name
            content.frame = CGRect(x: -clip.bounds.minX, y: -clip.bounds.minY, width: node.frame.width, height: node.frame.height)
            content.rotation = 0; content.flipH = false; content.flipV = false
            content.opacity = 1; content.blendMode = .normal; content.effects = []
            content.isMaskShape = false; content.artboardID = nil
            content.relationships = []; content.anchoredRelationships = []
            let mask = Node(name: "Cut boundary", frame: CGRect(origin: .zero, size: clip.bounds.size),
                            isMaskShape: true, content: .path(clip.shape))
            piece.name = "\(node.name) \(i + 1)"
            KnifePathGeometry.reframe(&piece, bounds: clip.bounds, original: node)
            piece.content = .group(children: [content, mask]); piece.isMask = true
            piece.autoLayout = nil; piece.autoPadding = nil
            return piece
        }
    }
}

enum KnifePathGeometry {
    static func reframe(_ piece: inout Node, bounds: CGRect, original: Node) {
        let center = VectorPathGeometry.pointToParent(CGPoint(x: bounds.midX, y: bounds.midY), node: original)
        piece.frame = CGRect(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2,
                             width: bounds.width, height: bounds.height)
    }

    static func pathPiece(_ node: Node, path: CGPath, style: PathShape, index: Int, closed: Bool) -> Node? {
        guard var converted = VectorPathGeometry.pathShape(from: path, fill: style.fill, stroke: style.stroke,
                strokeWidth: style.strokeWidth, strokeAlignment: style.effectiveStrokeAlignment) else { return nil }
        VectorPathGeometry.copyStrokeStyle(from: style, to: &converted.shape)
        converted.shape.closed = closed
        var piece = index == 0 ? node : Document.duplicatingNode(node)
        reframe(&piece, bounds: converted.bounds, original: node)
        piece.name = "\(node.name) \(index + 1)"; piece.content = .path(converted.shape)
        return piece
    }

    /// Close an open cutter along the target's bounding-box perimeter. The only
    /// interior boundary is the sampled stroke: no extrapolation or fitted curves.
    /// A closed loop can also cut out an interior piece.
    static func split(_ path: CGPath, samples: [CGPoint]) -> [CGPath]? {
        guard samples.count >= 2, !path.isEmpty else { return nil }
        let box = path.boundingBoxOfPath
        guard box.width > 1e-7, box.height > 1e-7 else { return nil }
        let cutter = CGMutablePath()
        let first = samples[0], last = samples.last!
        let isLoop = samples.count > 3 && hypot(last.x - first.x, last.y - first.y) < 1e-7
        if isLoop {
            cutter.move(to: first); samples.dropFirst().forEach { cutter.addLine(to: $0) }; cutter.closeSubpath()
        } else {
            guard !box.contains(first), !box.contains(last) else { return nil }
            var enters: [(Int, CGFloat, CGPoint)] = [], exits: [(Int, CGFloat, CGPoint)] = []
            for i in 0..<(samples.count - 1) {
                if let (lo, hi) = clipSegment(samples[i], samples[i + 1], box: box), hi - lo > 1e-10 {
                    enters.append((i, lo, mix(samples[i], samples[i + 1], lo)))
                    exits.append((i, hi, mix(samples[i], samples[i + 1], hi)))
                }
            }
            guard let entry = enters.first, let exit = exits.last else { return nil }
            cutter.move(to: entry.2)
            if entry.0 < exit.0 {
                for i in (entry.0 + 1)...exit.0 { cutter.addLine(to: samples[i]) }
            }
            cutter.addLine(to: exit.2)
            // Clockwise perimeter from exit to entry; Boolean complement gives
            // the other side, including multiple contours on either side.
            let w = box.width, h = box.height, perimeter = 2 * (w + h)
            func position(_ p: CGPoint) -> CGFloat {
                if abs(p.y - box.minY) < 1e-6 { return p.x - box.minX }
                if abs(p.x - box.maxX) < 1e-6 { return w + p.y - box.minY }
                if abs(p.y - box.maxY) < 1e-6 { return w + h + box.maxX - p.x }
                return 2 * w + h + box.maxY - p.y
            }
            let from = position(exit.2), rawTo = position(entry.2), to = rawTo <= from ? rawTo + perimeter : rawTo
            let corners: [(CGFloat, CGPoint)] = [(w, CGPoint(x: box.maxX,y: box.minY)),
                (w+h, CGPoint(x: box.maxX,y: box.maxY)), (2*w+h, CGPoint(x: box.minX,y: box.maxY)),
                (perimeter, CGPoint(x: box.minX,y: box.minY))]
            for lap in 0...1 {
                for (t, p) in corners where t + CGFloat(lap) * perimeter > from + 1e-7 && t + CGFloat(lap) * perimeter < to - 1e-7 {
                    cutter.addLine(to: p)
                }
            }
            cutter.closeSubpath()
        }
        let halves = [path.intersection(cutter, using: .winding), path.subtracting(cutter, using: .winding)]
        guard halves.allSatisfy({ !$0.isEmpty && $0.boundingBoxOfPath.width > 1e-7 && $0.boundingBoxOfPath.height > 1e-7 }) else { return nil }
        return halves
    }

    static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x-a.x)*t, y: a.y + (b.y-a.y)*t)
    }

    private static func clipSegment(_ a: CGPoint, _ b: CGPoint, box: CGRect) -> (CGFloat, CGFloat)? {
        var lo: CGFloat = 0, hi: CGFloat = 1
        let dx = b.x-a.x, dy = b.y-a.y
        for (p,q) in [(-dx,a.x-box.minX),(dx,box.maxX-a.x),(-dy,a.y-box.minY),(dy,box.maxY-a.y)] {
            if abs(p) < 1e-12 { if q < 0 { return nil }; continue }
            let t = q/p
            if p < 0 { lo = max(lo,t) } else { hi = min(hi,t) }
            if lo > hi { return nil }
        }
        return (lo,hi)
    }

    private struct Curve {
        var a, b, c, d: CGPoint
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1-t
            return CGPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x,
                           y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y)
        }
        func split(_ t: CGFloat) -> (Self, Self) {
            let ab = mix(a,b,t), bc = mix(b,c,t), cd = mix(c,d,t)
            let abc = mix(ab,bc,t), bcd = mix(bc,cd,t), p = mix(abc,bcd,t)
            return (Self(a:a,b:ab,c:abc,d:p), Self(a:p,b:bcd,c:cd,d:d))
        }
        func roots(from p: CGPoint, to q: CGPoint, infinite: Bool) -> [CGFloat] {
            let dx = q.x-p.x, dy = q.y-p.y, length2 = dx*dx+dy*dy
            guard length2 > 1e-12 else { return [] }
            func signed(_ r: CGPoint) -> CGFloat { (r.x-p.x)*dy - (r.y-p.y)*dx }
            let s0 = signed(a), s1 = signed(b), s2 = signed(c), s3 = signed(d)
            let A = -s0+3*s1-3*s2+s3, B = 3*s0-6*s1+3*s2, C = -3*s0+3*s1
            // Partition at derivative extrema; each interval is monotonic.
            var partitions: [CGFloat] = [0,1]
            if abs(A) > 1e-12 {
                let discriminant = 4*B*B-12*A*C
                if discriminant >= 0 {
                    partitions += [(-2*B-sqrt(discriminant))/(6*A),(-2*B+sqrt(discriminant))/(6*A)].filter { $0 > 0 && $0 < 1 }
                }
            } else if abs(B) > 1e-12 {
                let t = -C/(2*B); if t > 0 && t < 1 { partitions.append(t) }
            }
            partitions.sort()
            func value(_ t: CGFloat) -> CGFloat { ((A*t+B)*t+C)*t+s0 }
            var roots: [CGFloat] = []
            let epsilon = sqrt(length2)*1e-8
            // Collinear strokes overlap, rather than crossing: do not fragment.
            if [s0,s1,s2,s3].allSatisfy({ abs($0) < epsilon }) { return [] }
            for i in 0..<(partitions.count-1) {
                var lo = partitions[i], hi = partitions[i+1]
                if abs(value(lo)) < epsilon { roots.append(lo) }
                if value(lo)*value(hi) < 0 {
                    let negative = value(lo) < 0
                    for _ in 0..<45 {
                        let mid = (lo+hi)/2
                        if (value(mid) < 0) == negative { lo = mid } else { hi = mid }
                    }
                    roots.append((lo+hi)/2)
                }
                if abs(value(hi)) < epsilon { roots.append(hi) }
            }
            return roots.filter { t in
                let r = point(t), along = ((r.x-p.x)*dx+(r.y-p.y)*dy)/length2
                return t > 1e-8 && t < 1-1e-8 && (infinite || (along >= -1e-8 && along <= 1+1e-8))
            }
        }
    }

    /// Intersect each original cubic with the cutter, then split it with de
    /// Casteljau. The original curve stays exact; no flattened output is stored.
    static func cutOpen(_ node: Node, samples: [CGPoint], straight: Bool) -> [Node]? {
        guard let style = VectorPathGeometry.pathShape(from: node.content, size: node.frame.size),
              !style.closed, !style.isMultiContour, style.points.count >= 2 else { return nil }
        var chunks: [[Curve]] = [[]], cutCount = 0
        let pts = style.points
        for i in 0..<(pts.count-1) {
            let a = pts[i], d = pts[i+1]
            let original = Curve(a:a.point, b:a.controlOut ?? mix(a.point,d.point,1/3),
                                 c:d.controlIn ?? mix(a.point,d.point,2/3), d:d.point)
            var roots: [CGFloat] = []
            let segments = straight ? [0] : Array(0..<(samples.count-1))
            for j in segments { roots += original.roots(from: samples[j], to: straight ? samples.last! : samples[j+1], infinite: straight) }
            roots.sort(); roots = roots.reduce([]) { values, t in values.last.map { abs($0-t) < 1e-7 } == true ? values : values + [t] }
            var curve = original, previous: CGFloat = 0
            for t in roots {
                let (left,right) = curve.split((t-previous)/(1-previous))
                chunks[chunks.count-1].append(left); chunks.append([])
                cutCount += 1; curve = right; previous = t
            }
            chunks[chunks.count-1].append(curve)
            // Cutter through an existing anchor must also separate the path.
            if i < pts.count-2 {
                let p = d.point
                let crossed = segments.contains { j in
                    let a = samples[j], b = straight ? samples.last! : samples[j+1]
                    let dx = b.x-a.x, dy = b.y-a.y, ll = dx*dx+dy*dy
                    guard ll > 1e-12 else { return false }
                    let t = ((p.x-a.x)*dx+(p.y-a.y)*dy)/ll
                    return (straight || (t >= 0 && t <= 1)) && hypot(p.x-(a.x+dx*t),p.y-(a.y+dy*t)) < 1e-7
                }
                if crossed { chunks.append([]); cutCount += 1 }
            }
        }
        guard cutCount > 0 else { return nil }
        return chunks.filter { !$0.isEmpty }.enumerated().compactMap { index, curves in
            let path = CGMutablePath(); path.move(to: curves[0].a)
            for c in curves { path.addCurve(to:c.d, control1:c.b, control2:c.c) }
            guard var piece = pathPiece(node, path:path, style:style, index:index, closed:false), case .path(var p) = piece.content else { return nil }
            if index > 0 { p.startMarker = .none }
            if index < chunks.count-1 { p.endMarker = .none }
            piece.content = .path(p); return piece
        }
    }
}
