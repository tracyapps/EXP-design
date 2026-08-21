//
//  VectorPathGeometry.swift
//  EXP [design]
//
//  Shared conversion helpers for destructive vector operations. The output of
//  Outline Stroke and Pathfinder is always an ordinary editable PathShape — no
//  private/live effect is needed in the document schema.
//

import CoreGraphics
import Foundation

enum VectorBooleanOperation {
    case unite
    case subtract
    case intersect
    case exclude

    var actionName: String {
        switch self {
        case .unite: return "Unite Shapes"
        case .subtract: return "Subtract Shapes"
        case .intersect: return "Intersect Shapes"
        case .exclude: return "Exclude Overlap"
        }
    }
}

struct VectorStrokeGeometry {
    var color: RGBAColor
    var width: CGFloat
    var alignment: StrokeAlignment
    var join: CGLineJoin
    var cap: CGLineCap
}

enum VectorPathGeometry {
    /// Convert one of EXP's primitive vector payloads into the equivalent path.
    /// Kept outside CanvasView so Outline Stroke and Pathfinder use the exact
    /// same primitive geometry as Object -> Path -> Convert to Path.
    static func pathShape(from content: NodeContent, size: CGSize) -> PathShape? {
        let w = size.width, h = size.height
        switch content {
        case .rectangle(let s):
            let radii = s.effectiveRadii.clamped(to: size)
            let points: [PathPoint]
            if radii.isZero {
                points = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
                          CGPoint(x: w, y: h), CGPoint(x: 0, y: h)]
                    .map { PathPoint(point: $0) }
            } else {
                points = PathShape.roundedRectPoints(size: size, radii: radii)
            }
            return PathShape(points: points, closed: true, fill: s.fill,
                             stroke: s.stroke, strokeWidth: s.strokeWidth,
                             strokeAlignment: s.strokeAlignment)

        case .ellipse(let s):
            let kx = w / 2 * 0.5522847498, ky = h / 2 * 0.5522847498
            let top = CGPoint(x: w / 2, y: 0)
            let right = CGPoint(x: w, y: h / 2)
            let bottom = CGPoint(x: w / 2, y: h)
            let left = CGPoint(x: 0, y: h / 2)
            let points = [
                PathPoint(point: top,
                          controlIn: CGPoint(x: top.x - kx, y: top.y),
                          controlOut: CGPoint(x: top.x + kx, y: top.y)),
                PathPoint(point: right,
                          controlIn: CGPoint(x: right.x, y: right.y - ky),
                          controlOut: CGPoint(x: right.x, y: right.y + ky)),
                PathPoint(point: bottom,
                          controlIn: CGPoint(x: bottom.x + kx, y: bottom.y),
                          controlOut: CGPoint(x: bottom.x - kx, y: bottom.y)),
                PathPoint(point: left,
                          controlIn: CGPoint(x: left.x, y: left.y + ky),
                          controlOut: CGPoint(x: left.x, y: left.y - ky))
            ]
            return PathShape(points: points, closed: true, fill: s.fill,
                             stroke: s.stroke, strokeWidth: s.strokeWidth,
                             strokeAlignment: s.strokeAlignment)

        case .polygon(let s):
            let rect = CGRect(origin: .zero, size: size)
            return PathShape(points: s.vertices(in: rect).map { PathPoint(point: $0) },
                             closed: true, fill: s.fill, stroke: s.stroke,
                             strokeWidth: s.strokeWidth,
                             strokeAlignment: s.strokeAlignment)

        case .line(let s):
            return PathShape(points: [PathPoint(point: s.start), PathPoint(point: s.end)],
                             closed: false, fill: .clear, stroke: s.stroke,
                             strokeWidth: s.strokeWidth, strokePattern: s.strokePattern,
                             strokeCap: s.strokeCap,
                             startMarker: s.startMarker, endMarker: s.endMarker)

        case .path(let s):
            return s

        default:
            return nil
        }
    }

    static func stroke(from content: NodeContent) -> VectorStrokeGeometry? {
        switch content {
        case .rectangle(let s) where s.strokeWidth > 0:
            return VectorStrokeGeometry(color: s.stroke, width: s.strokeWidth,
                                        alignment: s.strokeAlignment,
                                        join: .miter, cap: .butt)
        case .ellipse(let s) where s.strokeWidth > 0:
            return VectorStrokeGeometry(color: s.stroke, width: s.strokeWidth,
                                        alignment: s.strokeAlignment,
                                        join: .miter, cap: .butt)
        case .polygon(let s) where s.strokeWidth > 0:
            return VectorStrokeGeometry(color: s.stroke, width: s.strokeWidth,
                                        alignment: s.strokeAlignment,
                                        join: .miter, cap: .butt)
        case .line(let s) where s.strokeWidth > 0:
            return VectorStrokeGeometry(color: s.stroke, width: s.strokeWidth,
                                        alignment: .center,
                                        join: .round, cap: s.strokeCap.cgLineCap)
        case .path(let s) where s.strokeWidth > 0:
            return VectorStrokeGeometry(color: s.stroke, width: s.strokeWidth,
                                        alignment: s.effectiveStrokeAlignment,
                                        join: .round, cap: s.strokeCap.cgLineCap)
        default:
            return nil
        }
    }

    static func fill(from content: NodeContent) -> Paint? {
        switch content {
        case .rectangle(let s): return s.fill
        case .ellipse(let s): return s.fill
        case .polygon(let s): return s.fill
        case .path(let s) where s.isMultiContour || s.closed: return s.fill
        default: return nil
        }
    }

    static func isClosedVector(_ content: NodeContent) -> Bool {
        switch content {
        case .rectangle, .ellipse, .polygon: return true
        case .path(let s): return s.isMultiContour || s.closed
        default: return false
        }
    }

    /// Construct the Core Graphics path for an EXP path in its node-local space.
    static func cgPath(from shape: PathShape) -> CGPath {
        let result = CGMutablePath()
        func add(_ points: [PathPoint], closed: Bool) {
            guard let first = points.first else { return }
            result.move(to: first.point)
            for i in 1..<points.count {
                let previous = points[i - 1], current = points[i]
                result.addCurve(to: current.point,
                                control1: previous.controlOut ?? previous.point,
                                control2: current.controlIn ?? current.point)
            }
            if closed, points.count >= 2 {
                let last = points[points.count - 1]
                result.addCurve(to: first.point,
                                control1: last.controlOut ?? last.point,
                                control2: first.controlIn ?? first.point)
                result.closeSubpath()
            }
        }
        if shape.isMultiContour {
            for contour in shape.renderContours { add(contour, closed: true) }
        } else {
            add(shape.points, closed: shape.closed)
        }
        return result
    }

    /// Copy a CGPath while mapping every anchor and control point. Unlike a
    /// bounding-box shortcut, this preserves Bézier geometry through nested
    /// rotations/flips and lets Pathfinder span different group levels.
    static func map(_ source: CGPath, _ transform: (CGPoint) -> CGPoint) -> CGPath {
        let result = CGMutablePath()
        source.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                result.move(to: transform(element.points[0]))
            case .addLineToPoint:
                result.addLine(to: transform(element.points[0]))
            case .addQuadCurveToPoint:
                result.addQuadCurve(to: transform(element.points[1]),
                                    control: transform(element.points[0]))
            case .addCurveToPoint:
                result.addCurve(to: transform(element.points[2]),
                                control1: transform(element.points[0]),
                                control2: transform(element.points[1]))
            case .closeSubpath:
                result.closeSubpath()
            @unknown default:
                break
            }
        }
        return result
    }

    /// The visible stroke converted into a filled outline. Inside/outside use
    /// the same 2x-band + clip/subtract geometry as PaintRender, so converting
    /// does not visually jump when a non-centered stroke is expanded.
    static func outlinedStroke(centerline: CGPath, shape: PathShape,
                               stroke: VectorStrokeGeometry) -> CGPath {
        let closed = shape.isMultiContour || shape.closed
        switch closed ? stroke.alignment : .center {
        case .center:
            return centerline.copy(strokingWithWidth: stroke.width,
                                   lineCap: stroke.cap, lineJoin: stroke.join,
                                   miterLimit: 10)
        case .inside:
            let band = centerline.copy(strokingWithWidth: stroke.width * 2,
                                       lineCap: stroke.cap, lineJoin: stroke.join,
                                       miterLimit: 10)
            return band.intersection(centerline, using: .winding)
        case .outside:
            let band = centerline.copy(strokingWithWidth: stroke.width * 2,
                                       lineCap: stroke.cap, lineJoin: stroke.join,
                                       miterLimit: 10)
            return band.subtracting(centerline, using: .winding)
        }
    }

    /// Convert Core Graphics output back to EXP's editable cubic-anchor model.
    /// Quadratic segments are promoted exactly to cubic segments.
    static func pathShape(from path: CGPath, fill: Paint,
                          stroke: RGBAColor = .black, strokeWidth: CGFloat = 0,
                          strokeAlignment: StrokeAlignment = .center) -> (shape: PathShape, bounds: CGRect)? {
        guard !path.isEmpty else { return nil }
        let bounds = path.boundingBoxOfPath.standardized
        guard !bounds.isNull, !bounds.isInfinite,
              bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite else { return nil }

        var contours: [[PathPoint]] = []
        var current: [PathPoint] = []
        var currentPoint: CGPoint?
        func local(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
        }
        func finishContour() {
            guard !current.isEmpty else { return }
            // Some producers explicitly line back to the first anchor before
            // closeSubpath. Avoid exposing that duplicate as a zero-length edge.
            if current.count > 1,
               hypot(current.last!.point.x - current.first!.point.x,
                     current.last!.point.y - current.first!.point.y) < 0.000_001 {
                let duplicate = current.removeLast()
                if duplicate.controlIn != nil { current[0].controlIn = duplicate.controlIn }
            }
            contours.append(current)
            current = []
            currentPoint = nil
        }

        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                finishContour()
                let p = element.points[0]
                current = [PathPoint(point: local(p))]
                currentPoint = p

            case .addLineToPoint:
                let p = element.points[0]
                current.append(PathPoint(point: local(p)))
                currentPoint = p

            case .addQuadCurveToPoint:
                guard let start = currentPoint, !current.isEmpty else { break }
                let control = element.points[0], end = element.points[1]
                let c1 = CGPoint(x: start.x + (control.x - start.x) * 2 / 3,
                                 y: start.y + (control.y - start.y) * 2 / 3)
                let c2 = CGPoint(x: end.x + (control.x - end.x) * 2 / 3,
                                 y: end.y + (control.y - end.y) * 2 / 3)
                current[current.count - 1].controlOut = local(c1)
                current.append(PathPoint(point: local(end), controlIn: local(c2)))
                currentPoint = end

            case .addCurveToPoint:
                guard !current.isEmpty else { break }
                current[current.count - 1].controlOut = local(element.points[0])
                current.append(PathPoint(point: local(element.points[2]),
                                         controlIn: local(element.points[1])))
                currentPoint = element.points[2]

            case .closeSubpath:
                finishContour()

            @unknown default:
                break
            }
        }
        finishContour()
        contours.removeAll { $0.count < 2 }
        guard let first = contours.first else { return nil }
        let multi = contours.count > 1 ? contours : nil
        return (PathShape(points: first, closed: true, fill: fill,
                          stroke: stroke, strokeWidth: strokeWidth,
                          strokeAlignment: strokeAlignment, contours: multi),
                CGRect(x: bounds.minX, y: bounds.minY,
                       width: max(1, bounds.width), height: max(1, bounds.height)))
    }
}
