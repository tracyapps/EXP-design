import AppKit
import Observation

extension TextContent {
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize { CGSize(width: maxWidth ?? 20, height: 20) }
    func measuredSize(boxWidth: CGFloat) -> CGSize { measuredSize(maxWidth: boxWidth) }
}

@Observable final class Camera {
    var zoom: CGFloat = 0.04
    var panOffset = CGPoint(x: 1000, y: 600)
}

// Baseline: the original canvas builder, including observable camera reads for
// each point. The candidate method is extracted from the current CanvasView.
final class PathHarness {
    var app: Camera? = Camera()
    func docToViewPoint(_ p: CGPoint) -> CGPoint {
        guard let app else { return p }
        return CGPoint(x: p.x * app.zoom + app.panOffset.x,
                       y: p.y * app.zoom + app.panOffset.y)
    }
    func legacy(_ ps: PathShape, origin: CGPoint) -> NSBezierPath {
        let bez = NSBezierPath()
        func v(_ p: CGPoint) -> CGPoint {
            docToViewPoint(CGPoint(x: origin.x + p.x, y: origin.y + p.y))
        }
        func add(_ pts: [PathPoint], closed: Bool) {
            guard !pts.isEmpty else { return }
            bez.move(to: v(pts[0].point))
            for i in 1..<pts.count {
                let prev = pts[i - 1], cur = pts[i]
                bez.curve(to: v(cur.point), controlPoint1: v(prev.controlOut ?? prev.point),
                          controlPoint2: v(cur.controlIn ?? cur.point))
            }
            if closed && pts.count >= 2 {
                let last = pts[pts.count - 1], first = pts[0]
                bez.curve(to: v(first.point), controlPoint1: v(last.controlOut ?? last.point),
                          controlPoint2: v(first.controlIn ?? first.point))
                bez.close()
            }
        }
        if ps.isMultiContour {
            for c in ps.renderContours { add(c, closed: true) }
            bez.windingRule = .nonZero
        } else { add(ps.points, closed: ps.closed) }
        return bez
    }
    // PRODUCTION_METHOD
}

private func signature(_ path: NSBezierPath) -> [CGFloat] {
    var result: [CGFloat] = [CGFloat(path.windingRule.rawValue)]
    var points = [CGPoint](repeating: .zero, count: 3)
    for i in 0..<path.elementCount {
        let element = path.element(at: i, associatedPoints: &points)
        result.append(CGFloat(element.rawValue))
        let count = element == .cubicCurveTo ? 3 : (element == .closePath ? 0 : 1)
        for p in points.prefix(count) { result += [p.x, p.y] }
    }
    return result
}

@main struct Check {
    static func main() throws {
        let harness = PathHarness()
        var paths: [(Node, PathShape)] = []
        func walk(_ nodes: [Node]) {
            for n in nodes {
                if case .path(let p) = n.content { paths.append((n, p)) }
                if case .group(let children) = n.content { walk(children) }
            }
        }
        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let document = try JSONDecoder().decode(Document.self, from: data)
            for page in document.pages { walk(page.nodes) }
        }
        let points = [PathPoint(point: CGPoint(x: -10, y: 20), controlOut: CGPoint(x: 3, y: -50)),
                      PathPoint(point: CGPoint(x: 60, y: 70), controlIn: CGPoint(x: 90, y: 100))]
        var fixtures = [PathShape(points: []), PathShape(points: [points[0]]),
                        PathShape(points: points), PathShape(points: points, closed: true)]
        var multi = PathShape(points: points, closed: false)
        multi.contours = [points, [], points.reversed()]
        fixtures.append(multi)
        let allShapes = fixtures + paths.map(\.1)
        for zoom: CGFloat in [0.01, 0.04, 0.14, 1, 3.75] {
            harness.app?.zoom = zoom
            harness.app?.panOffset = CGPoint(x: -113.25, y: 807.5)
            for p in allShapes {
                let origin = CGPoint(x: 19931.52, y: -839)
                precondition(signature(harness.legacy(p, origin: origin)) ==
                             signature(harness.bezierPath(for: p, frameOrigin: origin)),
                             "Path commands/control points changed at zoom \(zoom)")
            }
        }
        harness.app = nil
        for p in fixtures {
            precondition(signature(harness.legacy(p, origin: .zero)) ==
                         signature(harness.bezierPath(for: p, frameOrigin: .zero)))
        }
        harness.app = Camera()
        func measure(_ candidate: Bool) -> (Double, Int) {
            var count = 0
            let start = CFAbsoluteTimeGetCurrent()
            // Mirrors the observation context surrounding SwiftUI canvas updates.
            withObservationTracking {
                for _ in 0..<10 {
                    for (n, p) in paths {
                        if candidate {
                            let needsOutline = n.effects.contains {
                                $0.isEnabled && ($0.kind == .dropShadow || $0.kind == .innerShadow ||
                                                 ($0.kind == .noise && $0.amount > 0))
                            }
                            if needsOutline && p.closed && p.points.count >= 2 {
                                count += harness.bezierPath(for: p, frameOrigin: n.frame.origin).elementCount
                            }
                            count += harness.bezierPath(for: p, frameOrigin: n.frame.origin).elementCount
                        } else {
                            if p.closed && p.points.count >= 2 {
                                count += harness.legacy(p, origin: n.frame.origin).elementCount
                            }
                            count += harness.legacy(p, origin: n.frame.origin).elementCount
                        }
                    }
                }
            } onChange: {}
            return ((CFAbsoluteTimeGetCurrent() - start) * 1000, count)
        }
        print("PASS: exact path commands, controls, closure and winding at five zooms; empty/open/multi-contour and nil camera")
        if !paths.isEmpty {
            let before = measure(false), after = measure(true)
            print(String(format: "STRESS: %d paths, ten geometry passes: legacy %.1fms, updated %.1fms (%.1fx); command counts %d → %d",
                         paths.count, before.0, after.0, before.0 / after.0, before.1, after.1))
        }
    }
}
