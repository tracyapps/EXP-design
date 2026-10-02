import AppKit

/// Render the existing dense pattern loop at the destination's exact pixel grid,
/// then submit one image to the canvas. Export and pattern lattices stay intact.
final class CanvasPatternRasterCache<Revision: Equatable> {
    private struct Entry {
        let ref: PatternRef
        let tile: CGImage
        let path: CGPath
        let winding: NSBezierPath.WindingRule
        let signature: [CGFloat]
        let image: CGImage
    }
    private var revision: Revision?
    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []
    private var cost = 0
    private let budget = 32 << 20

    @discardableResult
    func draw(nodeID: UUID, revision: Revision, ref: PatternRef, path: NSBezierPath,
              bounds: CGRect, patterns: PatternResolver?, space: CGAffineTransform,
              in ctx: CGContext) -> Bool {
        if self.revision != revision {
            self.revision = revision
            entries.removeAll(); order.removeAll(); cost = 0
        }
        guard let patterns, abs(space.determinant) > 1e-9 else { return false }
        let documentBounds = bounds.applying(space.inverted())
        let effective = space.concatenating(ctx.ctm)
        let scale = min(4, max(1, abs(effective.determinant).squareRoot()))
        guard let resolved = patterns.resolve(ref, documentBounds, scale),
              resolved.tileSize.width > 0.01, resolved.tileSize.height > 0.01,
              abs(resolved.transform.determinant) > 1e-9 else { return false }
        let region = documentBounds.applying(resolved.transform.inverted())
        let tw = resolved.tileSize.width, th = resolved.tileSize.height
        let ox = resolved.origin.x, oy = resolved.origin.y
        let columns = ceil((region.maxX - ox) / tw) - floor((region.minX - ox) / tw) + 1
        let rows = ceil((region.maxY - oy) / th) - floor((region.minY - oy) / th) + 1
        guard columns.isFinite, rows.isFinite, columns * rows >= 1024,
              columns * rows <= 40_000 else { return false }

        // Whole paint bounds keep stamps stable on pan. Large/high-zoom fills
        // retain the live path rather than allocate or undersample giant bitmaps.
        let pixels = bounds.applying(ctx.ctm).insetBy(dx: -2, dy: -2).integral
        guard pixels.width.isFinite, pixels.height.isFinite,
              pixels.width > 0, pixels.height > 0,
              pixels.width <= 2048, pixels.height <= 2048,
              pixels.width * pixels.height <= 1_048_576 else { return false }
        let width = Int(pixels.width), height = Int(pixels.height)
        let toStamp = ctx.ctm.concatenating(CGAffineTransform(translationX: -pixels.minX, y: -pixels.minY))
        var pathTransform = toStamp
        guard let localPath = path.cgPath.copy(using: &pathTransform) else { return false }
        let lattice = resolved.transform.concatenating(space).concatenating(toStamp)
        let signature = [pixels.width, pixels.height, lattice.a, lattice.b, lattice.c, lattice.d,
                         lattice.tx, lattice.ty, tw, th, ox, oy]
        let image: CGImage
        if let hit = entries[nodeID], hit.ref == ref, hit.tile === resolved.image,
           hit.winding == path.windingRule, hit.signature == signature,
           hit.path == localPath {
            image = hit.image
        } else {
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let bitmap = CGContext(data: nil, width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            bitmap.concatenate(toStamp)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)
            PaintRender.fill(.pattern(ref), path: path, bounds: bounds, in: bitmap,
                             patterns: PatternResolver { _, _, _ in resolved }, patternSpace: space)
            NSGraphicsContext.restoreGraphicsState()
            guard let stamp = bitmap.makeImage() else { return false }
            if let prior = entries[nodeID] { cost -= prior.image.bytesPerRow * prior.image.height }
            image = stamp
            entries[nodeID] = Entry(ref: ref, tile: resolved.image, path: localPath,
                                    winding: path.windingRule, signature: signature, image: stamp)
            cost += stamp.bytesPerRow * stamp.height
        }
        order.removeAll { $0 == nodeID }; order.append(nodeID)
        while cost > budget, order.count > 1 {
            if let old = entries.removeValue(forKey: order.removeFirst()) {
                cost -= old.image.bytesPerRow * old.image.height
            }
        }
        ctx.saveGState()
        ctx.concatenate(ctx.ctm.inverted())
        ctx.interpolationQuality = .none
        ctx.draw(image, in: pixels) // integer device pixels, no resampling
        ctx.restoreGState()
        return true
    }
}

private extension CGAffineTransform {
    var determinant: CGFloat { a * d - b * c }
}
