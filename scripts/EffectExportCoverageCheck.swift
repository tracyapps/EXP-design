// BUG-053 regression check: every effect kind renders in raster export and SVG,
// and no kind is ever silently dropped. This is the automated twin of
// docs/EXPORT-FIDELITY-TEST-FIXTURES.md Fixture A, plus the coverage gate the
// backlog's acceptance asks for — adding a new Effect.Kind without wiring every
// exporter fails here, because the sweep renders each kind through
// Kind.allCases and compares against a no-effect baseline.
//
// It also probes the two PDF-intermediate concerns recorded in BUG-053:
//   • the group-noise destination-in punch (Porter-Duff through PDF), and
//   • the preserve-transparency shadow knockout (.destinationOut through PDF).
import Foundation
import AppKit

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private let boardBG = RGBAColor(r: 32.0 / 255, g: 32.0 / 255, b: 32.0 / 255, a: 1)   // #202020
private let nodeFill = RGBAColor(r: 51.0 / 255, g: 85.0 / 255, b: 170.0 / 255, a: 1) // #3355AA

@main
private enum EffectExportCoverageCheck {
    static func main() {
        fixtureA()
        allKindsSweep()
        preserveTransparencyKnockout()
        groupNoisePunch()
        oversizedLayerBlur()
        gradientAlphaThroughPDF()
        blendedNoiseGrain()
        print("ok: fixture A — noise renders with grain and lift in raster export")
        print("ok: fixture A — dissolve renders as speckle in raster export")
        print("ok: every renderable effect kind changes raster AND SVG output")
        print("ok: group noise stays inside the group's own pixels through the PDF path")
        print("ok: preserve-transparency knockout erases (not paints) through the PDF path")
        print("ok: a layer too large for a full-resolution bitmap keeps its blur (degraded, not dropped)")
        print("ok: gradient-to-transparent keeps its alpha falloff through the PDF path")
        print("ok: Color-Dodge noise on a blended layer keeps its grain and blend math")
    }

    // MARK: Effect-blend noise on blended layers (BUG-057)

    /// The owner's FX-A-2 fixture: a gradient-to-transparent ellipse at Overlay
    /// blend carrying a Color-Dodge noise effect exported as a FLAT disc — two
    /// CG PDF-rasterizer defects stack: image draws inside a transparency group
    /// are resampled (grain smears to its local average) and in-group blend-mode
    /// image draws collapse. The blended-noise route composites offscreen and
    /// draws one image with the node blend directly. This probe renders the
    /// exact node both ways and compares grain statistics over the core.
    private static func blendedNoiseGrain() {
        let glow = GradientFill(kind: .radial, stops: [
            GradientStop(color: RGBAColor(r: 1, g: 0, b: 0, a: 1), position: 0),
            GradientStop(color: RGBAColor(r: 0.89, g: 0, b: 0, a: 0), position: 0.78)
        ])
        let rect = CGRect(x: 29, y: 17, width: 266, height: 266)
        let noise = Effect(kind: .noise, frequency: 0.9, octaves: 4, seed: 7004,
                           monochrome: true, amount: 1.0, blend: .colorDodge)
        let node = Node(name: "glow", frame: rect, effects: [noise], blendMode: .overlay,
                        content: .ellipse(EllipseShape(fill: .gradient(glow))))
        let board = Artboard(name: "FX-BN", frame: CGRect(x: 0, y: 0, width: 900, height: 300),
                             background: .solid(boardBG))
        let beneath = Node(name: "backdrop", frame: CGRect(x: 40, y: 50, width: 240, height: 200),
                           content: .rectangle(RectangleShape(
                               fill: .solid(nodeFill), stroke: nodeFill, strokeWidth: 0)))
        guard let png = ExportRenderer(document: Document(artboards: [board], nodes: [beneath, node]))
            .pngData(for: board, scale: 2),
              let rep = NSBitmapImageRep(data: png)
        else { require(false, "blended-noise probe produced no PNG"); return }

        // Canvas truth: same stack drawn straight into a bitmap (the canvas
        // route — PaintRender + EffectsRender, layer semantics native).
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let tctx = CGContext(data: nil, width: 900, height: 300, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { require(false, "blended-noise truth bitmap unavailable"); return }
        tctx.translateBy(x: 0, y: 300); tctx.scaleBy(x: 1, y: -1)
        tctx.setFillColor(CGColor(srgbRed: boardBG.r, green: boardBG.g, blue: boardBG.b, alpha: 1))
        tctx.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
        tctx.setFillColor(CGColor(srgbRed: nodeFill.r, green: nodeFill.g, blue: nodeFill.b, alpha: 1))
        tctx.fill(CGRect(x: 40, y: 50, width: 240, height: 200))
        tctx.saveGState()
        tctx.setBlendMode(.overlay)
        tctx.beginTransparencyLayer(auxiliaryInfo: nil)
        PaintRender.fill(.gradient(glow), path: NSBezierPath(ovalIn: rect), bounds: rect, in: tctx)
        let sil = Silhouette(rect: rect, shape: .oval)
        EffectsRender.drawNoise(noise, clip: sil.clip, rect: rect, modelSize: rect.size,
                                in: tctx, synchronous: true)
        tctx.endTransparencyLayer()
        tctx.restoreGState()
        guard let timg = tctx.makeImage() else {
            require(false, "blended-noise truth encode failed"); return
        }
        let trep = NSBitmapImageRep(cgImage: timg)

        // Grain lives in the green/blue channels (red is clamped by dodge).
        // Region: the ellipse core, ±15pt around its center.
        let cx = rect.midX, cy = rect.midY
        func stats(_ r: NSBitmapImageRep, pxPerPt: Int) -> (mean: Double, sd: Double) {
            var v: [Double] = []
            for dx in stride(from: -15, to: 15, by: 1) {
                for dy in stride(from: -15, to: 15, by: 1) {
                    if let c = r.colorAt(x: Int(cx) * pxPerPt + dx * pxPerPt, y: Int(cy) * pxPerPt + dy * pxPerPt) {
                        v.append(Double(c.greenComponent * 255))
                    }
                }
            }
            let n = Double(v.count)
            let m = v.reduce(0, +) / n
            let sd = (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / n).squareRoot()
            return (m, sd)
        }
        let t = stats(trep, pxPerPt: 1), e = stats(rep, pxPerPt: 2)
        require(e.sd > 1.5,
                "Color-Dodge grain collapsed in export (sd \(e.sd), truth \(t.sd)) — blended-noise route regressed")
        require(abs(e.mean - t.mean) < 6,
                "Color-Dodge blend math diverged (export mean \(e.mean) vs canvas truth \(t.mean))")
        require(e.sd > t.sd * 0.5 && e.sd < t.sd * 1.6,
                "grain amplitude diverged (export sd \(e.sd) vs truth \(t.sd))")
    }

    // MARK: Gradient alpha through the PDF intermediate (BUG-056)

    /// CG's PDF emitter drops CGGradient stop ALPHA (shadings carry none), so a
    /// gradient-to-transparent exported as a solid opaque blob. Prove the
    /// soft-mask route restores the exact falloff: export vs a direct-bitmap
    /// render of the same gradient (what the canvas draws).
    private static func gradientAlphaThroughPDF() {
        let glow = GradientFill(kind: .radial, stops: [
            GradientStop(color: RGBAColor(r: 1, g: 1, b: 1, a: 0.9), position: 0),
            GradientStop(color: RGBAColor(r: 1, g: 1, b: 1, a: 0.0), position: 1)
        ])
        let rect = CGRect(x: 60, y: 40, width: 180, height: 220)
        let node = Node(name: "glow", frame: rect,
                        content: .ellipse(EllipseShape(fill: .gradient(glow))))
        let board = Artboard(name: "FX-GA", frame: CGRect(x: 0, y: 0, width: 900, height: 300),
                             background: .solid(boardBG))
        let png = ExportRenderer(document: Document(artboards: [board], nodes: [node]))
            .pngData(for: board, scale: 1)
        require(png != nil, "gradient-alpha probe produced no PNG data")

        // Direct-bitmap truth: same gradient, same clip, straight into a bitmap
        // (the canvas route — no PDF involved).
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let bctx = CGContext(data: nil, width: 900, height: 300, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { require(false, "gradient-alpha truth bitmap unavailable"); return }
        bctx.translateBy(x: 0, y: 300); bctx.scaleBy(x: 1, y: -1)
        bctx.setFillColor(CGColor(srgbRed: boardBG.r, green: boardBG.g, blue: boardBG.b, alpha: 1))
        bctx.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
        bctx.addPath(CGPath(ellipseIn: rect, transform: nil)); bctx.clip()
        PaintRender.drawGradient(glow, in: rect, ctx: bctx)
        guard let truthImg = bctx.makeImage(),
              let truthData = NSBitmapImageRep(cgImage: truthImg)
              .representation(using: .png, properties: [:]),
              let truthPNG = NSBitmapImageRep(data: truthData)
        else { require(false, "gradient-alpha truth encode failed"); return }

        for r in [0, 20, 40, 60, 80] {
            let e = pixel(png!, 150 - r, 150).0
            let t = pixel(truthPNG, 150 - r, 150).0
            require(abs(e - t) <= 3.0,
                    "gradient alpha falloff diverged at radius \(r): export \(e) vs canvas-truth \(t)")
        }
        // And it must actually FALLOFF (the pre-fix export was flat 100).
        let head = pixel(png!, 150, 150).0, tail = pixel(png!, 70, 150).0
        require(head - tail > 25,
                "gradient-to-transparent exported flat (head \(head) vs tail \(tail)) — alpha dropped again")

        // 2×/3× exports must stay SMOOTH: the PDF rasterizer nearest-samples the
        // soft mask when scaling, so the mask is baked at 3× supersample. If that
        // regresses, the falloff advances in wide constant runs (measured pre-fix:
        // uniform 2px runs at 2×, 3px at 3× — "choppy" gradients). Quantization
        // naturally produces runs of 1–4; fail only on runs no smooth 8-bit ramp
        // can produce.
        for scale in [2, 3] {
            guard let scaled = ExportRenderer(document: Document(artboards: [board], nodes: [node]))
                .pngData(for: board, scale: CGFloat(scale)),
                  let rep = NSBitmapImageRep(data: scaled)
            else { require(false, "gradient-alpha \(scale)× probe produced no PNG"); return }
            let cy = 150 * scale, cx = 150 * scale
            var vals: [Int] = []
            for i in 0..<(60 * scale) {
                vals.append(Int(rep.colorAt(x: cx - i, y: cy)!.redComponent * 255))
            }
            var run = 1, longRuns = 0
            for i in 1..<vals.count {
                if vals[i] == vals[i - 1] { run += 1 } else { if run >= 6 { longRuns += 1 }; run = 1 }
            }
            if run >= 6 { longRuns += 1 }
            require(longRuns == 0,
                    "gradient falloff stepped at \(scale)× export (\(longRuns) runs ≥6 identical px) — mask supersample regressed")
        }
    }

    // MARK: Fixture A (automated) — plain vs noise@colorDodge vs dissolve

    private static func fixtureA() {
        let board = Artboard(name: "FX-A", frame: CGRect(x: 0, y: 0, width: 900, height: 300),
                             background: .solid(boardBG))
        func rect(_ x: CGFloat, _ name: String, _ effects: [Effect]) -> Node {
            Node(name: name, frame: CGRect(x: x, y: 50, width: 240, height: 200),
                 effects: effects,
                 content: .rectangle(RectangleShape(fill: .solid(nodeFill),
                                                   stroke: nodeFill, strokeWidth: 0)))
        }
        let nodes = [
            rect(40, "A1-plain", []),
            rect(330, "A2-noise-dodge", [Effect(kind: .noise, amount: 0.6, blend: .colorDodge)]),
            rect(620, "A3-dissolve", [Effect(kind: .dissolve, amount: 0.5)])
        ]
        let doc = Document(artboards: [board], nodes: nodes)
        let png = ExportRenderer(document: doc).pngData(for: board, scale: 1)
        require(png != nil, "fixture A produced no PNG data")

        // Interior sampling insets 30pt so antialiased edges never pollute stats.
        let a1 = stats(png!, CGRect(x: 70, y: 80, width: 180, height: 140))
        let a2 = stats(png!, CGRect(x: 360, y: 80, width: 180, height: 140))

        require(a1.variance.0 < 5 && a1.variance.1 < 5 && a1.variance.2 < 5,
                "A1-plain is not flat — baseline is unstable, stats above are meaningless")
        require(a2.variance.2 > 100,
                "A2-noise-dodge shows no grain in raster export (variance \(a2.variance.2)) — BUG-053 regressions")
        require(a2.mean.2 > a1.mean.2 + 10,
                "A2-noise-dodge does not lift its backdrop at Color Dodge (mean blue \(a2.mean.2) vs \(a1.mean.2))")

        let bg = mixture(png!, CGRect(x: 650, y: 80, width: 180, height: 140),
                         color: (32, 32, 32), tolerance: 6)
        let fill = mixture(png!, CGRect(x: 650, y: 80, width: 180, height: 140),
                           color: (51, 85, 170), tolerance: 14)
        require(bg > 0.15 && bg < 0.85,
                "A3-dissolve shows no background speckle in raster export (bg fraction \(bg)) — BUG-053 regressions")
        require(fill > 0.15 && fill < 0.85,
                "A3-dissolve removed the wrong fraction (fill fraction \(fill))")
    }

    // MARK: Every renderable kind must move raster AND SVG output

    private static func allKindsSweep() {
        // backgroundBlur is globally feature-flagged off (canvas and every
        // exporter) — it is deliberately exempt until the flag ships on.
        let renderable = Effect.Kind.allCases.filter { $0 != .backgroundBlur }
        let params: [Effect.Kind: Effect] = [
            .dropShadow: Effect(kind: .dropShadow, color: RGBAColor(r: 0, g: 0, b: 0, a: 0.8),
                                dx: 12, dy: 12, blur: 16),
            .innerShadow: Effect(kind: .innerShadow, color: RGBAColor(r: 0, g: 0, b: 0, a: 0.8),
                                 dx: 0, dy: 0, blur: 16),
            .layerBlur: Effect(kind: .layerBlur, blur: 12),
            .noise: Effect(kind: .noise, amount: 0.6),
            .dissolve: Effect(kind: .dissolve, amount: 0.5)
        ]
        let svgNeedles: [Effect.Kind: [String]] = [
            .dropShadow: ["feOffset", "feFlood"],
            .innerShadow: ["feFlood"],
            .layerBlur: ["feGaussianBlur"],
            .noise: ["feTurbulence", "feBlend"],
            .dissolve: ["feTurbulence", "feComponentTransfer"]
        ]
        // Shared geometry; sample box grown 30pt past the node so shadow/blur
        // halos outside the fill are measured too.
        let frame = CGRect(x: 60, y: 50, width: 240, height: 200)
        let sample = CGRect(x: 30, y: 20, width: 300, height: 260)
        func build(_ effects: [Effect]) -> (Document, Artboard) {
            let board = Artboard(name: "sweep", frame: CGRect(x: 0, y: 0, width: 360, height: 320),
                                 background: .solid(boardBG))
            let node = Node(name: "sweep-node", frame: frame, effects: effects,
                            content: .rectangle(RectangleShape(fill: .solid(nodeFill),
                                                               stroke: nodeFill, strokeWidth: 0)))
            return (Document(artboards: [board], nodes: [node]), board)
        }

        let (baseDoc, baseBoard) = build([])
        let basePNG = ExportRenderer(document: baseDoc).pngData(for: baseBoard, scale: 1)
        let baseSVG = ExportRenderer(document: baseDoc).svgString(for: baseBoard)
        require(basePNG != nil, "sweep baseline produced no PNG data")

        for kind in renderable {
            guard let effect = params[kind], let needles = svgNeedles[kind] else {
                require(false, "sweep is missing parameters for \(kind) — update EffectExportCoverageCheck")
                continue
            }
            let (doc, board) = build([effect])
            let png = ExportRenderer(document: doc).pngData(for: board, scale: 1)
            let svg = ExportRenderer(document: doc).svgString(for: board)
            require(png != nil, "\(kind) sweep produced no PNG data")

            let a = stats(basePNG!, sample), b = stats(png!, sample)
            let meanShift = abs(a.mean.0 - b.mean.0) + abs(a.mean.1 - b.mean.1) + abs(a.mean.2 - b.mean.2)
            let varShift = abs(a.variance.0 - b.variance.0) + abs(a.variance.1 - b.variance.1)
                + abs(a.variance.2 - b.variance.2)
            require(meanShift > 1.5 || varShift > 100,
                    "\(kind) leaves raster export pixel-identical to no-effect — an exporter silently drops it")

            for needle in needles {
                require(svg.contains(needle),
                        "\(kind) SVG export lost its \(needle) primitive")
            }
            require(svg != baseSVG, "\(kind) SVG export is identical to no-effect baseline")
        }
    }

    // MARK: Group noise punch (Porter-Duff .destinationIn through the PDF path)

    private static func groupNoisePunch() {
        let board = Artboard(name: "FX-G", frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                             background: .solid(boardBG))
        let child = Node(name: "g-child", frame: CGRect(x: 20, y: 20, width: 100, height: 100),
                         content: .rectangle(RectangleShape(fill: .solid(nodeFill),
                                                            stroke: nodeFill, strokeWidth: 0)))
        let group = Node(name: "g-noise", frame: CGRect(x: 40, y: 50, width: 240, height: 200),
                         effects: [Effect(kind: .noise, amount: 0.5)],
                         content: .group(children: [child]))
        let doc = Document(artboards: [board], nodes: [group])
        let png = ExportRenderer(document: doc).pngData(for: board, scale: 1)
        require(png != nil, "group-noise probe produced no PNG data")

        // Child frame in board coords: (60,70)-(160,170). Noise must live there…
        let inside = stats(png!, CGRect(x: 80, y: 90, width: 60, height: 60))
        require(abs(inside.mean.2 - 32.0) + abs(inside.mean.0 - 32.0) > 5,
                "group noise vanished from its own content pixels")
        // …and NOWHERE else inside the group frame. If the destination-in punch
        // fell back to Normal when CG emitted it to PDF, grain would leak here.
        let outside = stats(png!, CGRect(x: 180, y: 180, width: 70, height: 50))
        require(abs(outside.mean.0 - 32.0) < 2 && abs(outside.mean.1 - 32.0) < 2
                && abs(outside.mean.2 - 32.0) < 2 && outside.variance.2 < 5,
                "group noise leaked outside the group's content — the PDF destination-in punch failed")
    }

    // MARK: Preserve-transparency knockout (.destinationOut through the PDF path)

    private static func preserveTransparencyKnockout() {
        let board = Artboard(name: "FX-K", frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                             background: .solid(boardBG))
        let halfFill = RGBAColor(r: nodeFill.r, g: nodeFill.g, b: nodeFill.b, a: 0.5)
        let node = Node(name: "k-node", frame: CGRect(x: 60, y: 60, width: 200, height: 200),
                        effects: [Effect(kind: .dropShadow,
                                          color: RGBAColor(r: 0, g: 0, b: 0, a: 0.8),
                                          dx: 6, dy: 6, blur: 10, preserveTransparency: true)],
                        content: .rectangle(RectangleShape(fill: .solid(halfFill),
                                                           stroke: halfFill, strokeWidth: 0)))
        let doc = Document(artboards: [board], nodes: [node])
        let png = ExportRenderer(document: doc).pngData(for: board, scale: 1)
        require(png != nil, "knockout probe produced no PNG data")

        // Center of the node: the semi-transparent fill over the background —
        // roughly (42, 59, 101). Three failure modes are distinguishable by the
        // red channel: knockout silently ignored leaves the shadow under the
        // fill (red ≈ 26, the measured pre-fix value); a Normal fallback paints
        // the black knockout silhouette (red ≈ 0). Honored ≈ 42.
        let c = pixel(png!, 160, 160)
        require(c.0 > 35 && c.2 > 85 && c.2 - c.0 > 40,
                "preserve-transparency knockout wrong at the node center (\(c)) — honored ≈ (42,59,101), ignored ≈ (26,42,85), black ≈ (0,0,0)")
    }

    // MARK: Oversized layer blur degrades in resolution, never drops (BUG-054)

    private static func oversizedLayerBlur() {
        // 13,000pt wide trips maxLayerDimension (12,000) at export's scale 1 —
        // before the BUG-054 fix this failed OPEN and the layer rendered with
        // no blur at all.
        let board = Artboard(name: "FX-L", frame: CGRect(x: 0, y: 0, width: 13200, height: 300),
                             background: .solid(boardBG))
        let node = Node(name: "L-wide", frame: CGRect(x: 100, y: 50, width: 13000, height: 200),
                        effects: [Effect(kind: .layerBlur, blur: 20)],
                        content: .rectangle(RectangleShape(fill: .solid(nodeFill),
                                                           stroke: nodeFill, strokeWidth: 0)))
        let doc = Document(artboards: [board], nodes: [node])
        let png = ExportRenderer(document: doc).pngData(for: board, scale: 1)
        require(png != nil, "oversized-layer probe produced no PNG data")

        // A real blur softens the node's long edge: a few points OUTSIDE the
        // frame carry partial fill, and the fill a few points INSIDE is mixed
        // toward the background. Unblurred (the old fail-open), outside stays
        // exactly background.
        let outside = pixel(png!, 6600, 45)   // 5pt above the node's top edge
        let inside = pixel(png!, 6600, 58)    // 8pt inside
        let dOutside = abs(outside.0 - 32) + abs(outside.1 - 32) + abs(outside.2 - 32)
        let dInside = abs(inside.0 - 51) + abs(inside.1 - 85) + abs(inside.2 - 170)
        require(dOutside > 12,
                "oversized layer blur dropped — pixels outside the node are pure background (\(outside))")
        require(dInside > 12,
                "oversized layer blur dropped — pixels inside the node are pure fill (\(inside))")
    }

    // MARK: Pixel plumbing

    /// Mean and variance (0–255 scale) per channel over a region in artboard
    /// points, y measured from the top (matches NSBitmapImageRep rows).
    private static func stats(_ png: Data, _ region: CGRect)
        -> (mean: (Double, Double, Double), variance: (Double, Double, Double)) {
        let rep = NSBitmapImageRep(data: png)!
        var sums = [Double](repeating: 0, count: 3), sqs = [Double](repeating: 0, count: 3)
        var n = 0.0
        var x = region.minX
        while x < region.maxX {
            var y = region.minY
            while y < region.maxY {
                let c = pixel(png, Int(x), Int(y), rep: rep)
                sums[0] += c.0; sums[1] += c.1; sums[2] += c.2
                sqs[0] += c.0 * c.0; sqs[1] += c.1 * c.1; sqs[2] += c.2 * c.2
                n += 1
                y += 3
            }
            x += 3
        }
        var mean: (Double, Double, Double) = (0, 0, 0), variance: (Double, Double, Double) = (0, 0, 0)
        mean.0 = sums[0] / n; mean.1 = sums[1] / n; mean.2 = sums[2] / n
        variance.0 = sqs[0] / n - mean.0 * mean.0
        variance.1 = sqs[1] / n - mean.1 * mean.1
        variance.2 = sqs[2] / n - mean.2 * mean.2
        return (mean, variance)
    }

    /// Fraction of sampled pixels within `tolerance` (0–255) of a color.
    private static func mixture(_ png: Data, _ region: CGRect,
                                color: (Double, Double, Double), tolerance: Double) -> Double {
        let rep = NSBitmapImageRep(data: png)!
        var hit = 0.0, n = 0.0
        var x = region.minX
        while x < region.maxX {
            var y = region.minY
            while y < region.maxY {
                let c = pixel(png, Int(x), Int(y), rep: rep)
                let d = max(abs(c.0 - color.0), abs(c.1 - color.1), abs(c.2 - color.2))
                if d <= tolerance { hit += 1 }
                n += 1
                y += 2
            }
            x += 2
        }
        return hit / n
    }

    private static func pixel(_ png: Data, _ x: Int, _ y: Int,
                              rep: NSBitmapImageRep? = nil) -> (Double, Double, Double) {
        let r = rep ?? NSBitmapImageRep(data: png)!
        let c = r.colorAt(x: x, y: y)!
        return (Double(c.redComponent * 255), Double(c.greenComponent * 255), Double(c.blueComponent * 255))
    }

    /// Rep-direct variant for callers that already decoded (the gradient truth
    /// bitmap arrives as a rep, not a PNG payload).
    private static func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (Double, Double, Double) {
        let c = rep.colorAt(x: x, y: y)!
        return (Double(c.redComponent * 255), Double(c.greenComponent * 255), Double(c.blueComponent * 255))
    }
}
