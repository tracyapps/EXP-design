//
//  CurveFitting.swift
//  EXP [design]
//
//  FEAT-029 — fit a chain of cubic Béziers to a digitised polyline.
//
//  This is Philip J. Schneider's "An Algorithm for Automatically Fitting
//  Digitized Curves," Graphics Gems (Academic Press, 1990) — the same method
//  nearly every drawing application uses for a pencil/freehand tool, and the
//  reason a pencil stroke becomes a handful of well-placed anchors instead of
//  one anchor per captured sample.
//
//  Shape of the algorithm:
//    1. Parameterise the samples by chord length.
//    2. Solve a least-squares fit for the two control points, given fixed
//       endpoints and endpoint tangents.
//    3. Measure the worst deviation. If it is within tolerance, keep it.
//    4. If it is close, nudge the parameterisation (Newton-Raphson) and retry.
//    5. Otherwise split at the worst point and recurse on both halves.
//
//  Output is EXP's `PathPoint` convention: anchors and control points in the
//  SAME space the caller passed in, with `controlOut` belonging to the segment
//  that starts at an anchor and `controlIn` to the one that ends there. The
//  caller re-bases them into node-local space and refits the frame.
//
//  Pure geometry: no AppKit, no model mutation, no drawing. It is deliberately
//  testable on its own.
//

import Foundation
import CoreGraphics

enum CurveFitting {

    // MARK: Public entry point

    /// Fit `samples` with a chain of cubic Béziers and return them as anchors.
    ///
    /// - Parameters:
    ///   - samples: captured points, in any consistent space.
    ///   - tolerance: the largest deviation, in that space's units, a fitted
    ///     curve may have from the samples. Small = accurate and many anchors;
    ///     large = smooth and few. This is the one number a user should ever be
    ///     given control of (Illustrator calls it Fidelity).
    /// - Returns: anchors with control handles. Fewer than two usable samples
    ///   returns them unchanged as corner points rather than failing — a caller
    ///   should never get an empty path back from a stroke the user drew.
    static func fit(_ samples: [CGPoint], tolerance: CGFloat,
                    cornerAngle: CGFloat = defaultCornerAngle) -> [PathPoint] {
        let points = deduplicated(samples)
        guard points.count >= 2 else {
            return points.map { PathPoint(point: $0) }
        }
        // Two samples cannot describe a curve; a straight segment is the honest
        // answer and avoids inventing tangents from nothing.
        if points.count == 2 {
            return [PathPoint(point: points[0]), PathPoint(point: points[1])]
        }

        let errorSq = max(tolerance, 0.01) * max(tolerance, 0.01)
        var segments: [[CGPoint]] = []
        // Fit each run BETWEEN corners independently. This is the difference
        // between a pencil that can draw teeth and one that cannot: see
        // `cornerIndices` for why Schneider alone cannot.
        var breaks = [0]
        breaks.append(contentsOf: cornerIndices(points, angleDegrees: cornerAngle))
        breaks.append(points.count - 1)
        for k in 0..<(breaks.count - 1) {
            let first = breaks[k], last = breaks[k + 1]
            guard last > first else { continue }
            fitCubic(points, first: first, last: last,
                     tHat1: leftTangent(points, first),
                     tHat2: rightTangent(points, last),
                     errorSq: errorSq, depth: 0, into: &segments)
        }
        return anchors(from: segments)
    }

    // MARK: Corners

    /// Direction change, in degrees, above which a sample is a CORNER rather than
    /// part of a smooth curve.
    static let defaultCornerAngle: CGFloat = 55

    /// Samples looked at either side when measuring direction at a candidate
    /// corner. Adjacent samples alone are hopeless: at 1.5pt spacing, ordinary
    /// hand tremor turns a straight line into a corner every other point.
    private static let cornerWindow = 3

    /// Arms shorter than this have no meaningful direction, so they cannot vote
    /// on whether a sample is a corner.
    private static let cornerMinArm: CGFloat = 1.0

    /// Indices where the stroke turns sharply enough to be a corner.
    ///
    /// WHY THIS EXISTS: Schneider's algorithm assumes smooth data. At a genuine
    /// corner it splits and then computes the shared tangent as the AVERAGE of the
    /// incoming and outgoing directions — which at a sharp corner describes
    /// neither, and very nearly cancels. The least-squares solve then hands back
    /// enormous handle lengths trying to satisfy an impossible tangent, and the
    /// result is a curve that balloons far outside the stroke that was drawn.
    /// Splitting at corners FIRST means each run is genuinely smooth, which is
    /// what the algorithm needs, and the two runs meet at an anchor whose two
    /// handles were fitted independently — the definition of a corner point.
    private static func cornerIndices(_ d: [CGPoint], angleDegrees: CGFloat) -> [Int] {
        guard d.count >= 3 else { return [] }
        let threshold = cos(min(max(angleDegrees, 1), 179) * .pi / 180)
        var corners: [Int] = []
        var i = 1
        while i < d.count - 1 {
            let back = d[max(0, i - cornerWindow)]
            let forward = d[min(d.count - 1, i + cornerWindow)]
            guard distance(d[i], back) >= cornerMinArm,
                  distance(forward, d[i]) >= cornerMinArm else { i += 1; continue }
            let incoming = normalize(sub(d[i], back))
            let outgoing = normalize(sub(forward, d[i]))
            if dot(incoming, outgoing) < threshold {
                corners.append(i)
                i += cornerWindow      // one corner must not fire several times
            } else {
                i += 1
            }
        }
        return corners
    }

    // MARK: Sample hygiene

    /// Drop repeated and near-repeated samples. A zero-length chord makes the
    /// tangent estimates undefined and the least-squares solve singular, so this
    /// is a correctness step, not an optimisation.
    private static func deduplicated(_ points: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        out.reserveCapacity(points.count)
        for p in points {
            if let last = out.last, hypot(p.x - last.x, p.y - last.y) < 0.001 { continue }
            out.append(p)
        }
        return out
    }

    // MARK: The recursion

    /// Recursion ceiling. Schneider's split is guaranteed to terminate because
    /// each half is strictly shorter, but a pathological stroke (a tight scribble
    /// with a very small tolerance) can still split far enough to cost real time
    /// for no visible gain. At the limit we accept the current fit rather than
    /// keep going — the result is slightly loose, never wrong, and never hangs.
    private static let maxDepth = 16

    /// Largest handle length the least-squares solve may produce, as a multiple of
    /// the segment's chord. For reference, a quarter-circle arc needs about 0.39×
    /// its chord and a half-circle about 0.67×, so 1.5 leaves real curves alone and
    /// only catches the runaway solutions.
    private static let maxHandleChordFactor: CGFloat = 1.5

    private static func fitCubic(_ d: [CGPoint], first: Int, last: Int,
                                 tHat1: CGPoint, tHat2: CGPoint,
                                 errorSq: CGFloat, depth: Int,
                                 into segments: inout [[CGPoint]]) {
        let count = last - first + 1

        // Two points: no interior samples to fit, so use Schneider's heuristic —
        // handles one third of the way along the chord, in the tangent directions.
        if count == 2 {
            let dist = distance(d[first], d[last]) / 3
            segments.append([d[first],
                             add(d[first], scale(tHat1, dist)),
                             add(d[last], scale(tHat2, dist)),
                             d[last]])
            return
        }

        var u = chordLengthParameterize(d, first: first, last: last)
        var bez = generateBezier(d, first: first, last: last, uPrime: u,
                                 tHat1: tHat1, tHat2: tHat2)
        var (maxErrorSq, splitPoint) = computeMaxError(d, first: first, last: last,
                                                       bez: bez, u: u)
        if maxErrorSq < errorSq {
            segments.append(bez)
            return
        }

        // Close enough to be worth saving: improve the parameterisation and retry.
        //
        // Schneider's original writes `iterationError = error * error`, which is
        // unit-ambiguous — `error` is compared against a SQUARED distance, so
        // squaring it again means something different at every scale. This uses an
        // explicit rule instead: attempt reparameterisation when the fit is within
        // 4× the tolerance in real distance (16× squared). That is a judgement
        // call, chosen to be scale-independent, not a value from the paper.
        if maxErrorSq < errorSq * 16 {
            for _ in 0..<4 {
                u = reparameterize(d, first: first, last: last, u: u, bez: bez)
                bez = generateBezier(d, first: first, last: last, uPrime: u,
                                     tHat1: tHat1, tHat2: tHat2)
                (maxErrorSq, splitPoint) = computeMaxError(d, first: first, last: last,
                                                           bez: bez, u: u)
                if maxErrorSq < errorSq {
                    segments.append(bez)
                    return
                }
            }
        }

        if depth >= maxDepth {
            segments.append(bez)
            return
        }

        // Split at the worst-fitting sample and fit each half. The shared tangent
        // at the split is averaged so the two halves meet smoothly instead of
        // showing a crease where the recursion happened to divide.
        let tHatCenter = centerTangent(d, splitPoint)
        fitCubic(d, first: first, last: splitPoint,
                 tHat1: tHat1, tHat2: tHatCenter,
                 errorSq: errorSq, depth: depth + 1, into: &segments)
        fitCubic(d, first: splitPoint, last: last,
                 tHat1: negate(tHatCenter), tHat2: tHat2,
                 errorSq: errorSq, depth: depth + 1, into: &segments)
    }

    // MARK: Least-squares fit

    /// Solve for the two interior control points, with the endpoints and their
    /// tangent DIRECTIONS fixed; only the handle LENGTHS are unknown.
    private static func generateBezier(_ d: [CGPoint], first: Int, last: Int,
                                       uPrime: [CGFloat],
                                       tHat1: CGPoint, tHat2: CGPoint) -> [CGPoint] {
        let nPts = last - first + 1
        var a0: [CGPoint] = [], a1: [CGPoint] = []
        a0.reserveCapacity(nPts); a1.reserveCapacity(nPts)
        for i in 0..<nPts {
            a0.append(scale(tHat1, b1(uPrime[i])))
            a1.append(scale(tHat2, b2(uPrime[i])))
        }

        var c00: CGFloat = 0, c01: CGFloat = 0, c11: CGFloat = 0
        var x0: CGFloat = 0, x1: CGFloat = 0
        let p0 = d[first], p3 = d[last]
        for i in 0..<nPts {
            c00 += dot(a0[i], a0[i])
            c01 += dot(a0[i], a1[i])
            c11 += dot(a1[i], a1[i])
            let u = uPrime[i]
            // The part of the curve the fixed endpoints already account for.
            let base = add(scale(p0, b0(u) + b1(u)), scale(p3, b2(u) + b3(u)))
            let tmp = sub(d[first + i], base)
            x0 += dot(a0[i], tmp)
            x1 += dot(a1[i], tmp)
        }

        let detC0C1 = c00 * c11 - c01 * c01
        let detC0X  = c00 * x1 - c01 * x0
        let detXC1  = x0 * c11 - x1 * c01

        let alphaL = detC0C1 == 0 ? 0 : detXC1 / detC0C1
        let alphaR = detC0C1 == 0 ? 0 : detC0X / detC0C1

        // A negative or vanishing handle length means the least-squares solution
        // folded back on itself. Fall back to the same one-third heuristic the
        // two-point case uses rather than emitting a curve with inverted handles.
        let segLength = distance(p0, p3)
        let epsilon = 1e-6 * segLength
        if alphaL < epsilon || alphaR < epsilon {
            let dist = segLength / 3
            return [p0, add(p0, scale(tHat1, dist)), add(p3, scale(tHat2, dist)), p3]
        }
        // Clamp the handle length. Schneider's solve is UNBOUNDED, and an unbounded
        // handle is precisely the "one point flew off and drew a huge loop" failure:
        // when the data does not constrain the tangent, the least-squares answer can
        // put a control point far outside the stroke. A clamped handle merely fits
        // worse, which `computeMaxError` then resolves by splitting — strictly
        // better than emitting a loop nobody drew.
        let maxAlpha = segLength * maxHandleChordFactor
        return [p0,
                add(p0, scale(tHat1, min(alphaL, maxAlpha))),
                add(p3, scale(tHat2, min(alphaR, maxAlpha))),
                p3]
    }

    // MARK: Parameterisation

    private static func chordLengthParameterize(_ d: [CGPoint], first: Int, last: Int) -> [CGFloat] {
        var u: [CGFloat] = [0]
        u.reserveCapacity(last - first + 1)
        for i in (first + 1)...last {
            u.append(u[i - first - 1] + distance(d[i], d[i - 1]))
        }
        let total = u[last - first]
        guard total > 0 else {
            // Degenerate run: spread evenly rather than dividing by zero.
            let n = CGFloat(last - first)
            return (0...(last - first)).map { CGFloat($0) / max(n, 1) }
        }
        for i in 1...(last - first) { u[i] /= total }
        return u
    }

    private static func reparameterize(_ d: [CGPoint], first: Int, last: Int,
                                       u: [CGFloat], bez: [CGPoint]) -> [CGFloat] {
        (0...(last - first)).map { i in
            newtonRaphson(bez: bez, point: d[first + i], u: u[i])
        }
    }

    /// One Newton-Raphson step toward the parameter whose curve point is closest
    /// to `point` — the standard refinement that lets a fit converge without
    /// splitting.
    private static func newtonRaphson(bez: [CGPoint], point: CGPoint, u: CGFloat) -> CGFloat {
        let qu = evaluate(bez, u)
        // First and second derivative control polygons.
        var q1: [CGPoint] = []
        for i in 0..<3 { q1.append(scale(sub(bez[i + 1], bez[i]), 3)) }
        var q2: [CGPoint] = []
        for i in 0..<2 { q2.append(scale(sub(q1[i + 1], q1[i]), 2)) }

        let q1u = evaluate(q1, u)
        let q2u = evaluate(q2, u)
        let diff = sub(qu, point)
        let numerator = dot(diff, q1u)
        let denominator = dot(q1u, q1u) + dot(diff, q2u)
        guard denominator != 0 else { return u }
        return u - numerator / denominator
    }

    // MARK: Error

    /// Worst squared deviation of the samples from the fitted curve, and the
    /// index where it happens (the split point if the fit is rejected).
    private static func computeMaxError(_ d: [CGPoint], first: Int, last: Int,
                                        bez: [CGPoint], u: [CGFloat]) -> (CGFloat, Int) {
        var maxDistSq: CGFloat = 0
        var splitPoint = (last - first + 1) / 2 + first
        guard last - first >= 2 else { return (0, splitPoint) }
        for i in (first + 1)..<last {
            let p = evaluate(bez, u[i - first])
            let v = sub(p, d[i])
            let distSq = dot(v, v)
            if distSq >= maxDistSq {
                maxDistSq = distSq
                splitPoint = i
            }
        }
        return (maxDistSq, splitPoint)
    }

    // MARK: Bézier evaluation (de Casteljau, any degree)

    private static func evaluate(_ control: [CGPoint], _ t: CGFloat) -> CGPoint {
        var v = control
        guard !v.isEmpty else { return .zero }
        for k in 1..<v.count {
            for i in 0..<(v.count - k) {
                v[i] = CGPoint(x: (1 - t) * v[i].x + t * v[i + 1].x,
                               y: (1 - t) * v[i].y + t * v[i + 1].y)
            }
        }
        return v[0]
    }

    // Cubic Bernstein basis.
    private static func b0(_ u: CGFloat) -> CGFloat { let t = 1 - u; return t * t * t }
    private static func b1(_ u: CGFloat) -> CGFloat { let t = 1 - u; return 3 * u * t * t }
    private static func b2(_ u: CGFloat) -> CGFloat { let t = 1 - u; return 3 * u * u * t }
    private static func b3(_ u: CGFloat) -> CGFloat { u * u * u }

    // MARK: Tangents

    private static func leftTangent(_ d: [CGPoint], _ end: Int) -> CGPoint {
        normalize(sub(d[end + 1], d[end]))
    }

    private static func rightTangent(_ d: [CGPoint], _ end: Int) -> CGPoint {
        normalize(sub(d[end - 1], d[end]))
    }

    private static func centerTangent(_ d: [CGPoint], _ center: Int) -> CGPoint {
        let v1 = sub(d[center - 1], d[center])
        let v2 = sub(d[center], d[center + 1])
        let avg = CGPoint(x: (v1.x + v2.x) / 2, y: (v1.y + v2.y) / 2)
        return normalize(avg)
    }

    // MARK: Segments → anchors

    /// Convert consecutive [P0,C1,C2,P3] segments into EXP anchors. Interior
    /// anchors carry the incoming segment's C2 as `controlIn` and the outgoing
    /// segment's C1 as `controlOut`, which is exactly the pair the node tool
    /// then lets a designer drag.
    private static func anchors(from segments: [[CGPoint]]) -> [PathPoint] {
        guard let firstSegment = segments.first else { return [] }
        var out: [PathPoint] = [PathPoint(point: firstSegment[0],
                                          controlIn: nil,
                                          controlOut: firstSegment[1])]
        for (index, seg) in segments.enumerated() {
            let isLast = index == segments.count - 1
            let nextOut = isLast ? nil : segments[index + 1][1]
            out.append(PathPoint(point: seg[3], controlIn: seg[2], controlOut: nextOut))
        }
        return out
    }

    // MARK: Small vector helpers (local on purpose — no shared-namespace churn)

    private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x + b.x, y: a.y + b.y)
    }
    private static func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x - b.x, y: a.y - b.y)
    }
    private static func scale(_ a: CGPoint, _ s: CGFloat) -> CGPoint {
        CGPoint(x: a.x * s, y: a.y * s)
    }
    private static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        a.x * b.x + a.y * b.y
    }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
    private static func negate(_ a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }
    private static func normalize(_ a: CGPoint) -> CGPoint {
        let len = hypot(a.x, a.y)
        guard len > 0 else { return .zero }
        return CGPoint(x: a.x / len, y: a.y / len)
    }
}
