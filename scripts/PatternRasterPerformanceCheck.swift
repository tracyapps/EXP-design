import AppKit

private func bitmap(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}
private func data(_ ctx: CGContext) -> [UInt8] {
    Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self),
                              count: ctx.bytesPerRow * ctx.height))
}
private func path(_ shape: PathShape, origin: CGPoint, zoom: CGFloat, pan: CGPoint) -> NSBezierPath {
    let p = NSBezierPath()
    func v(_ a: CGPoint) -> CGPoint { CGPoint(x: (origin.x + a.x) * zoom + pan.x, y: (origin.y + a.y) * zoom + pan.y) }
    func add(_ points: [PathPoint], closed: Bool) {
        guard let first = points.first else { return }
        p.move(to: v(first.point))
        for i in 1..<points.count {
            p.curve(to: v(points[i].point), controlPoint1: v(points[i-1].controlOut ?? points[i-1].point),
                    controlPoint2: v(points[i].controlIn ?? points[i].point))
        }
        if closed, points.count >= 2 {
            p.curve(to: v(first.point), controlPoint1: v(points.last!.controlOut ?? points.last!.point),
                    controlPoint2: v(first.controlIn ?? first.point)); p.close()
        }
    }
    if shape.isMultiContour { for c in shape.renderContours { add(c, closed: true) }; p.windingRule = .nonZero }
    else { add(shape.points, closed: shape.closed) }
    return p
}

@main enum Check {
    static func main() throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        guard CommandLine.arguments.count > 1 else { fatalError("Pass the stress document containing jagged-alternations") }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard let root = document.pages.flatMap(\.nodes).first(where: { $0.name == "jagged-alternations" }) else {
            fatalError("Missing green-wave fixture")
        }
        var leaves: [(Node, PathShape, CGPoint)] = []
        func walk(_ node: Node, offset: CGPoint) {
            let origin = CGPoint(x: offset.x + node.frame.minX, y: offset.y + node.frame.minY)
            if case .path(let shape) = node.content, case .pattern = shape.fill { leaves.append((node, shape, origin)) }
            if case .group(let children) = node.content { for child in children { walk(child, offset: origin) } }
        }
        walk(root, offset: .zero)
        precondition(leaves.count == 6, "Expected six patterned waves")
        let tileStore = PatternTileStore()
        let patterns = tileStore.resolver(document: document)
        let cache = CanvasPatternRasterCache<Int>()
        var tileDraws = 0
        for (_, shape, origin) in leaves {
            guard case .pattern(let ref) = shape.fill,
                  let resolved = patterns.resolve(ref, path(shape, origin: origin, zoom: 1, pan: .zero).bounds, 1) else { fatalError("Missing wave pattern") }
            let region = path(shape, origin: origin, zoom: 1, pan: .zero).bounds.applying(resolved.transform.inverted())
            let cols = ceil((region.maxX - resolved.origin.x) / resolved.tileSize.width)
                - floor((region.minX - resolved.origin.x) / resolved.tileSize.width) + 1
            let rows = ceil((region.maxY - resolved.origin.y) / resolved.tileSize.height)
                - floor((region.minY - resolved.origin.y) / resolved.tileSize.height) + 1
            tileDraws += Int(cols * rows)
        }
        print("GREEN WAVE: six fill loops submit \(tileDraws) tile draws before caching")
        func render(cached: Bool, zoom: CGFloat, backing: CGFloat, shift: CGPoint = .zero, revision: Int = 1) -> (CGContext, Int) {
            let ctx = bitmap(1024)
            ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: backing, y: -backing)
            ctx.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            defer { NSGraphicsContext.restoreGraphicsState() }
            let pan = CGPoint(x: -12600 * zoom + 20 + shift.x, y: -17800 * zoom + 20 + shift.y)
            let space = CGAffineTransform(translationX: pan.x, y: pan.y).scaledBy(x: zoom, y: zoom)
            var accelerated = 0
            for (node, shape, origin) in leaves {
                let bez = path(shape, origin: origin, zoom: zoom, pan: pan)
                if case .pattern(let ref) = shape.fill,
                   cached && cache.draw(nodeID: node.id, revision: revision, ref: ref, path: bez,
                                        bounds: bez.bounds, patterns: patterns, space: space, in: ctx) {
                    accelerated += 1
                } else {
                    PaintRender.fill(shape.fill, path: bez, bounds: bez.bounds, in: ctx, patterns: patterns, patternSpace: space)
                }
                if case .solid(let color) = shape.stroke {
                    PaintRender.strokeAligned(bez, width: shape.strokeWidth * zoom,
                                              alignment: shape.effectiveStrokeAlignment,
                                              color: PaintRender.nsColor(color), join: shape.strokeJoin.cgLineJoin,
                                              cap: shape.strokeCap.cgLineCap, miterLimit: shape.strokeMiterLimit,
                                              pattern: shape.strokePattern, in: ctx)
                } else {
                    PaintRender.strokePaint(bez, width: shape.strokeWidth * zoom, alignment: shape.effectiveStrokeAlignment,
                                           paint: shape.stroke, bounds: bez.bounds, in: ctx, join: shape.strokeJoin.cgLineJoin,
                                           cap: shape.strokeCap.cgLineCap, miterLimit: shape.strokeMiterLimit,
                                           pattern: shape.strokePattern, patterns: patterns, patternSpace: space)
                }
            }
            return (ctx, accelerated)
        }
        for zoom: CGFloat in [0.02, 0.04, 0.13] {
            for backing: CGFloat in [1, 2] {
                for shift in [CGPoint.zero, CGPoint(x: 19, y: -13), CGPoint(x: 0.375, y: -0.625)] {
                    let old = data(render(cached: false, zoom: zoom, backing: backing, shift: shift).0)
                    let result = render(cached: true, zoom: zoom, backing: backing, shift: shift)
                    precondition(result.1 == (zoom == 0.13 && backing == 2 ? 0 : 6), "Cache/fallback eligibility")
                    let new = data(result.0)
                    let differences = zip(old,new).map { abs(Int($0) - Int($1)) }
                    let mean = Double(differences.reduce(0,+)) / Double(differences.count)
                    let maximum = differences.max()!
                    print(String(format: "PIXELS zoom %.2f backing %.0f shift %@ cached %d mean %.5f max %d",
                                 zoom, backing, String(describing: shift), result.1, mean, maximum))
                    precondition(maximum <= 4 && mean < 0.02, "Pattern pixels drifted")
                }
            }
        }
        for revision in [2, 3, 1] {
            let old = data(render(cached: false, zoom: 0.04, backing: 1).0)
            let new = data(render(cached: true, zoom: 0.04, backing: 1, revision: revision).0)
            precondition(zip(old,new).allSatisfy { abs(Int($0)-Int($1)) <= 4 }, "Revision invalidation")
        }
        // Same id/revision with different resolved pixels, shape, winding and
        // lattice must not reuse stale artwork (e.g. instance overrides).
        let testID = UUID(), testRef = PatternRef(patternID: UUID())
        let syntheticCache = CanvasPatternRasterCache<Int>()
        let tiles = [false, true].map { alternate -> CGImage in
            let tile = bitmap(16)
            tile.setFillColor(CGColor(red: alternate ? 0.9 : 0.1, green: 0.6, blue: 0.2, alpha: 0.65))
            tile.fill(CGRect(x: 1, y: 2, width: 10, height: 7))
            tile.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 0.35))
            tile.fill(CGRect(x: 8, y: 8, width: 5, height: 7))
            return tile.makeImage()!
        }
        for variant in [0, 0, 1, 2, 3, 0] {
            let p = NSBezierPath(ovalIn: CGRect(x: 17.375, y: 23.125, width: variant == 2 ? 165 : 140, height: 320))
            p.append(NSBezierPath(ovalIn: CGRect(x: 50, y: 60, width: 75, height: 95)))
            p.windingRule = variant == 3 ? .nonZero : .evenOdd
            let resolved = ResolvedPattern(image: tiles[variant == 1 ? 1 : 0],
                                           tileSize: CGSize(width: variant == 2 ? 2.5 : 2, height: 4),
                                           transform: CGAffineTransform(rotationAngle: 0.17),
                                           origin: CGPoint(x: variant == 2 ? 5 : 0, y: 0))
            let resolver = PatternResolver { _, _, _ in resolved }
            for background: CGFloat in [0.15, 1] {
                func fixture(_ cached: Bool) -> [UInt8] {
                    let ctx = bitmap(400)
                    ctx.translateBy(x: 0, y: 400); ctx.scaleBy(x: 1, y: -1)
                    ctx.setFillColor(CGColor(gray: background, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                    if cached {
                        precondition(syntheticCache.draw(nodeID: testID, revision: 1, ref: testRef, path: p,
                                                         bounds: p.bounds, patterns: resolver, space: .identity, in: ctx))
                    } else {
                        PaintRender.fill(.pattern(testRef), path: p, bounds: p.bounds, in: ctx,
                                         patterns: resolver, patternSpace: .identity)
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    return data(ctx)
                }
                let differences = zip(fixture(false), fixture(true)).map { abs(Int($0)-Int($1)) }
                let mean = Double(differences.reduce(0,+)) / Double(differences.count)
                let maximum = differences.max()!
                print(String(format: "ALPHA variant %d background %.2f mean %.5f max %d", variant, background, mean, maximum))
                precondition(maximum <= 4 && mean < 0.25, "Transparent/lattice/winding pixels drifted")
            }
        }
        let tiny = NSBezierPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        precondition(!syntheticCache.draw(nodeID: testID, revision: 1, ref: testRef, path: tiny,
                                         bounds: tiny.bounds, patterns: nil, space: .identity, in: bitmap(16)))
        let sparse = PatternResolver { _, _, _ in ResolvedPattern(image: tiles[0], tileSize: CGSize(width: 20, height: 20), transform: .identity) }
        precondition(!syntheticCache.draw(nodeID: testID, revision: 1, ref: testRef, path: tiny,
                                         bounds: tiny.bounds, patterns: sparse, space: .identity, in: bitmap(16)))
        func measure(_ cached: Bool, mode: String = "warm") -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            for i in 0..<20 {
                let zoom: CGFloat = mode == "zoom" ? 0.02 + CGFloat(i) * 0.001 : 0.04
                let shift = mode == "pan" ? CGPoint(x: i * 3, y: i * -2) : .zero
                _ = render(cached: cached, zoom: zoom, backing: 1, shift: shift,
                           revision: mode == "cold" ? 100 + i : 1)
            }
            return (CFAbsoluteTimeGetCurrent() - start) * 1000
        }
        let old = measure(false), new = measure(true)
        print(String(format: "GREEN WAVE: 20 complete six-path fill+stroke passes %.1fms → %.1fms (%.1fx)", old, new, old/new))
        for mode in ["pan", "zoom", "cold"] {
            let old = measure(false, mode: mode), new = measure(true, mode: mode)
            print(String(format: "GREEN WAVE %@: 20 passes %.1fms → %.1fms (%.1fx)", mode, old, new, old/new))
        }
        print("PASS: real wave paints; zoom/backing/pan/revision pixel parity within 4/255")
    }
}
