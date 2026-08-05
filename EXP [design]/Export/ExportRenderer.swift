//
//  ExportRenderer.swift
//  EXP [design]
//
//  Renders an artboard to PNG, PDF, or SVG.
//
//  Strategy:
//   • PDF — draw the artboard into a flipped offscreen NSView and use AppKit's
//     `dataWithPDF(inside:)`. Vector, and text/flip are handled correctly.
//   • PNG — rasterize that vector PDF into a bitmap at the requested scale, so a
//     2× export is crisp (we're scaling vectors, not upscaling pixels).
//   • SVG — emit directly from the model. SVG is y-down with a top-left origin,
//     exactly like our coordinate system, so it's a near 1:1 mapping (the model
//     was built for this).
//
//  Everything renders in ARTBOARD-LOCAL coordinates: the artboard's origin maps
//  to (0,0) and the output size is the artboard's frame size.
//

import AppKit
import PDFKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable {
    case png, pdf, svg, jpg

    var ext: String { rawValue }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .pdf: return .pdf
        case .svg: return UTType(filenameExtension: "svg") ?? .data
        case .jpg: return .jpeg
        }
    }

    init?(ext: String) {
        switch ext.lowercased() {
        case "png": self = .png
        case "pdf": self = .pdf
        case "svg": self = .svg
        case "jpg", "jpeg": self = .jpg
        default: return nil
        }
    }
}

struct ExportRenderer {
    let document: Document

    func data(for artboard: Artboard, format: ExportFormat, scale: CGFloat,
              includeNotes: Bool = false, transparentPNGBackground: Bool = false) -> Data? {
        switch format {
        case .pdf: return pdfData(for: artboard, includeNotes: includeNotes)
        case .png: return pngData(for: artboard, scale: scale,
                                  transparentBackground: transparentPNGBackground)
        case .jpg: return jpgData(for: artboard, scale: scale)
        case .svg: return svgString(for: artboard).data(using: .utf8)
        }
    }

    // MARK: PDF (vector via a flipped offscreen view)

    func pdfData(for artboard: Artboard, drawBackground: Bool = true) -> Data {
        let view = ExportRenderView(document: document, artboard: artboard,
                                    drawBackground: drawBackground)
        return view.dataWithPDF(inside: view.bounds)
    }

    /// One artboard as PDF; when `includeNotes` and the board has notes, a second
    /// "speaker notes" page is appended (PowerPoint-style).
    func pdfData(for artboard: Artboard, includeNotes: Bool) -> Data {
        let boardPDF = pdfData(for: artboard)
        guard includeNotes, !artboard.notes.isEmpty, let notesPDF = notesPDFData(for: artboard) else {
            return boardPDF
        }
        let combined = PDFDocument()
        appendFirstPage(of: boardPDF, to: combined)
        appendFirstPage(of: notesPDF, to: combined)
        return combined.dataRepresentation() ?? boardPDF
    }

    /// One multi-page PDF with a page per artboard (optionally a notes page after
    /// each board that has notes). Pages are rendered individually then merged
    /// with PDFKit — no flip/text headaches.
    func multiPagePDFData(for artboards: [Artboard], includeNotes: Bool = false) -> Data? {
        let combined = PDFDocument()
        for artboard in artboards {
            appendFirstPage(of: pdfData(for: artboard), to: combined)
            if includeNotes, !artboard.notes.isEmpty, let notesPDF = notesPDFData(for: artboard) {
                appendFirstPage(of: notesPDF, to: combined)
            }
        }
        return combined.pageCount > 0 ? combined.dataRepresentation() : nil
    }

    private func appendFirstPage(of data: Data, to doc: PDFDocument) {
        if let src = PDFDocument(data: data), let page = src.page(at: 0) {
            doc.insert(page, at: doc.pageCount)
        }
    }

    /// A Letter-portrait "notes" page: board name as a heading + the notes body.
    func notesPDFData(for artboard: Artboard) -> Data? {
        guard !artboard.notes.isEmpty else { return nil }
        let view = NotesRenderView(title: artboard.name, notes: artboard.notes)
        return view.dataWithPDF(inside: view.bounds)
    }

    // MARK: PNG (rasterize the vector PDF at scale)

    func pngData(for artboard: Artboard, scale: CGFloat,
                 transparentBackground: Bool = false) -> Data? {
        let w = artboard.frame.width, h = artboard.frame.height
        guard w > 0, h > 0,
              let image = NSImage(data: pdfData(for: artboard,
                                                drawBackground: !transparentBackground)) else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: w, height: h)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: w, height: h))
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    // MARK: JPG (rasterize like PNG, but flattened onto white — JPEG has no alpha)

    func jpgData(for artboard: Artboard, scale: CGFloat, quality: CGFloat = 0.9) -> Data? {
        let w = artboard.frame.width, h = artboard.frame.height
        guard w > 0, h > 0,
              let image = NSImage(data: pdfData(for: artboard, drawBackground: true)) else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: w, height: h)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // JPEG can't be transparent — fill white first so any transparency in the
        // board (or its background) flattens to white rather than black.
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: quality])
    }

    // MARK: SVG (emit from the model)

    func svgString(for artboard: Artboard) -> String {
        let w = artboard.frame.width, h = artboard.frame.height
        let origin = CGPoint(x: -artboard.frame.minX, y: -artboard.frame.minY)
        var defs: [String] = []
        // SVG export is transparent by default: game assets and layered comps
        // almost always want no board fill behind the shapes. (The artboard's
        // own `background` is intentionally NOT emitted — add a shape layer if
        // you want a real background.) PNG/PDF still fill via `drawBackground`.
        var body = ""
        let page = document.page(containingArtboard: artboard.id)
        for node in page?.nodes ?? [] where node.isVisible
            && document.owningArtboard(of: node, on: page?.id)?.id == artboard.id {
            body += svgElement(node, offset: origin, defs: &defs)
        }
        let tokenStyle = svgTokenStyle()
        let defsBlock = defs.isEmpty ? "" : "<defs>\n\(defs.joined())</defs>\n"
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(num(w))" height="\(num(h))" viewBox="0 0 \(num(w)) \(num(h))">
        \(tokenStyle)\(defsBlock)\(body)</svg>
        """
    }

    private func svgElement(_ node: Node, offset: CGPoint, defs: inout [String]) -> String {
        let f = node.frame.offsetBy(dx: offset.x, dy: offset.y)
        let inner: String
        switch node.content {
        case .rectangle(let s):
            if s.hasPerCornerRadii {
                // v1.3 per-corner radii: <rect rx> can't express them — emit an
                // arc path. Inside/outside strokes reuse the generic clip/mask
                // helper (exact), same as polygon/path.
                let d = svgRoundedRectData(f, s.effectiveRadii)
                let shape = "<path d=\"\(d)\""
                if s.strokeWidth > 0, s.strokeAlignment != .center {
                    inner = "\(shape)\(paintFillAttr(s.fill, &defs))/>\n"
                        + svgAlignedStrokeCopy(shape: shape, closer: "/>", bounds: f,
                                               stroke: s.stroke, width: s.strokeWidth,
                                               alignment: s.strokeAlignment,
                                               pattern: s.strokePattern,
                                               join: "miter", defs: &defs)
                } else {
                    inner = "\(shape)\(paintFillAttr(s.fill, &defs))\(strokeAttr(s.stroke, s.strokeWidth, s.strokePattern))/>\n"
                }
            } else
            // Stroke alignment: SVG only strokes centered, so inside/outside are
            // emitted EXACTLY by offsetting the stroked copy's geometry ±w/2
            // (fill stays at the true frame; corner radius shifts with the edge).
            if s.strokeWidth > 0, s.strokeAlignment != .center {
                let d = s.strokeWidth / 2 * (s.strokeAlignment == .inside ? 1 : -1)
                let sr = f.insetBy(dx: d, dy: d)
                let radius = s.effectiveRadii.clamped(to: f.size).topLeft
                let srx = min(max(0, radius - d),
                              max(0, min(sr.width, sr.height) / 2))
                let fillRx = radius > 0 ? " rx=\"\(num(radius))\"" : ""
                let strokeRx = srx > 0 ? " rx=\"\(num(srx))\"" : ""
                inner = "<rect x=\"\(num(f.minX))\" y=\"\(num(f.minY))\" width=\"\(num(f.width))\" height=\"\(num(f.height))\"\(fillRx)\(paintFillAttr(s.fill, &defs))/>\n"
                    + "<rect x=\"\(num(sr.minX))\" y=\"\(num(sr.minY))\" width=\"\(num(sr.width))\" height=\"\(num(sr.height))\"\(strokeRx) fill=\"none\"\(strokeAttr(s.stroke, s.strokeWidth, s.strokePattern))/>\n"
            } else {
                let radius = s.effectiveRadii.clamped(to: f.size).topLeft
                let rx = radius > 0 ? " rx=\"\(num(radius))\"" : ""
                inner = "<rect x=\"\(num(f.minX))\" y=\"\(num(f.minY))\" width=\"\(num(f.width))\" height=\"\(num(f.height))\"\(rx)\(paintFillAttr(s.fill, &defs))\(strokeAttr(s.stroke, s.strokeWidth, s.strokePattern))/>\n"
            }
        case .ellipse(let s):
            if s.strokeWidth > 0, s.strokeAlignment != .center {
                let d = s.strokeWidth / 2 * (s.strokeAlignment == .inside ? 1 : -1)
                inner = "<ellipse cx=\"\(num(f.midX))\" cy=\"\(num(f.midY))\" rx=\"\(num(f.width / 2))\" ry=\"\(num(f.height / 2))\"\(paintFillAttr(s.fill, &defs))/>\n"
                    + "<ellipse cx=\"\(num(f.midX))\" cy=\"\(num(f.midY))\" rx=\"\(num(max(0, f.width / 2 - d)))\" ry=\"\(num(max(0, f.height / 2 - d)))\" fill=\"none\"\(strokeAttr(s.stroke, s.strokeWidth, s.strokePattern))/>\n"
            } else {
                inner = "<ellipse cx=\"\(num(f.midX))\" cy=\"\(num(f.midY))\" rx=\"\(num(f.width / 2))\" ry=\"\(num(f.height / 2))\"\(paintFillAttr(s.fill, &defs))\(strokeAttr(s.stroke, s.strokeWidth, s.strokePattern))/>\n"
            }
        case .polygon(let s):
            let pts = s.vertices(in: f).map { "\(num($0.x)),\(num($0.y))" }.joined(separator: " ")
            if s.strokeWidth > 0, s.strokeAlignment != .center {
                // Same trick as the canvas: 2× width clipped/masked to one side.
                let shape = "<polygon points=\"\(pts)\""
                inner = "\(shape)\(paintFillAttr(s.fill, &defs))/>\n"
                    + svgAlignedStrokeCopy(shape: shape, closer: "/>", bounds: f,
                                           stroke: s.stroke, width: s.strokeWidth,
                                           alignment: s.strokeAlignment,
                                           pattern: s.strokePattern,
                                           join: "miter", defs: &defs)
            } else {
                inner = "<polygon points=\"\(pts)\"\(paintFillAttr(s.fill, &defs))\(strokeAttr(s.stroke, s.strokeWidth, s.strokePattern)) stroke-linejoin=\"miter\"/>\n"
            }
        case .line(let ls):
            let a = CGPoint(x: f.minX + ls.start.x, y: f.minY + ls.start.y)
            let b = CGPoint(x: f.minX + ls.end.x, y: f.minY + ls.end.y)
            inner = "<line x1=\"\(num(a.x))\" y1=\"\(num(a.y))\" x2=\"\(num(b.x))\" y2=\"\(num(b.y))\"\(strokeAttr(ls.stroke, ls.strokeWidth, ls.strokePattern))/>\n"
        case .path(let ps):
            let d = svgPathData(ps, origin: f.origin)
            let fills = ps.isMultiContour || ps.closed
            let fill = fills ? paintFillAttr(ps.fill, &defs) : " fill=\"none\""
            if ps.strokeWidth > 0, ps.effectiveStrokeAlignment != .center {
                let shape = "<path d=\"\(d)\""
                inner = "\(shape)\(fill)/>\n"
                    + svgAlignedStrokeCopy(shape: shape, closer: "/>", bounds: f,
                                           stroke: ps.stroke, width: ps.strokeWidth,
                                           alignment: ps.effectiveStrokeAlignment,
                                           pattern: ps.strokePattern,
                                           join: "round", defs: &defs)
            } else {
                // Nonzero is SVG's default fill-rule, matching font-glyph winding.
                inner = "<path d=\"\(d)\"\(fill)\(strokeAttr(ps.stroke, ps.strokeWidth, ps.strokePattern)) stroke-linejoin=\"round\"/>\n"
            }
        case .text(let t):
            let baseline = f.minY + t.firstRun.fontSize * 0.8
            let cased = t.displayStrings()
            let spans = t.runs.enumerated().map { i, run -> String in
                let font = run.nsFont()
                let family = run.fontName.isEmpty ? "-apple-system, sans-serif" : (font.familyName ?? "sans-serif")
                let sym = font.fontDescriptor.symbolicTraits
                let weight = sym.contains(.bold) ? " font-weight=\"bold\"" : ""
                let style = sym.contains(.italic) ? " font-style=\"italic\"" : ""
                let underline = run.underline ? " text-decoration=\"underline\"" : ""
                return "<tspan font-family=\"\(escape(family))\" font-size=\"\(num(run.fontSize))\"\(weight)\(style)\(underline)\(fillAttr(run.color))>\(escape(cased[i]))</tspan>"
            }.joined()
            inner = "<text x=\"\(num(f.minX))\" y=\"\(num(baseline))\">\(spans)</text>\n"
        case .group(let children):
            var prefix = ""
            if let pad = node.autoPadding, pad.fill != nil || pad.strokeWidth > 0 {
                let fillStr: String
                if let p = pad.fill { fillStr = paintFillAttr(p, &defs) } else { fillStr = " fill=\"none\"" }
                // Background box = frame inset by the margin.
                let bx = f.minX + pad.marginLeft, by = f.minY + pad.marginTop
                let bw = max(0, f.width - pad.marginW), bh = max(0, f.height - pad.marginH)
                let baseRect = "<rect x=\"\(num(bx))\" y=\"\(num(by))\" width=\"\(num(bw))\" height=\"\(num(bh))\""
                let rx = pad.cornerRadius > 0 ? " rx=\"\(num(pad.cornerRadius))\"" : ""
                prefix = "\(baseRect)\(rx)\(fillStr)/>\n"
                if pad.strokeWidth > 0, let stroke = pad.stroke {
                    let delta = pad.strokeAlignment == .center ? 0
                        : pad.strokeWidth / 2 * (pad.strokeAlignment == .inside ? 1 : -1)
                    let sx = bx + delta, sy = by + delta
                    let sw = max(0, bw - 2 * delta), sh = max(0, bh - 2 * delta)
                    let sr = max(0, pad.cornerRadius - delta)
                    let srx = sr > 0 ? " rx=\"\(num(sr))\"" : ""
                    prefix += "<rect x=\"\(num(sx))\" y=\"\(num(sy))\" width=\"\(num(sw))\" height=\"\(num(sh))\"\(srx) fill=\"none\"\(strokeAttr(stroke, pad.strokeWidth, pad.strokePattern))/>\n"
                }
            }
            inner = prefix + children.filter { $0.isVisible }
                .map { svgElement($0, offset: f.origin, defs: &defs) }.joined()
        case .instance(let inst):
            var out = ""
            for child in document.resolvedChildren(of: inst) {
                out += svgElement(child, offset: f.origin, defs: &defs)
            }
            inner = out
        case .image(let img):
            // Embed as a base64 PNG data URI (re-encoded for a reliable MIME type).
            let b64: String
            if let ns = NSImage(data: img.data), let tiff = ns.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                b64 = png.base64EncodedString()
            } else {
                b64 = img.data.base64EncodedString()
            }
            inner = "<image x=\"\(num(f.minX))\" y=\"\(num(f.minY))\" width=\"\(num(f.width))\" height=\"\(num(f.height))\" preserveAspectRatio=\"none\" href=\"data:image/png;base64,\(b64)\"/>\n"
        }
        var tParts: [String] = []
        if node.rotation != 0 {
            tParts.append("rotate(\(num(CGFloat(node.rotation))) \(num(f.midX)) \(num(f.midY)))")
        }
        if node.flipH || node.flipV {
            let sx = node.flipH ? -1 : 1, sy = node.flipV ? -1 : 1
            tParts.append("translate(\(num(f.midX)) \(num(f.midY))) scale(\(sx) \(sy)) translate(\(num(-f.midX)) \(num(-f.midY)))")
        }
        let transform = tParts.isEmpty ? "" : " transform=\"\(tParts.joined(separator: " "))\""
        let opacity = node.opacity < 0.999 ? " opacity=\"\(num(CGFloat(node.opacity)))\"" : ""
        let blend = node.blendMode != .normal ? " style=\"mix-blend-mode:\(node.blendMode.cssName)\"" : ""
        let filter = svgEffectsFilter(node.effects, &defs)
        // Every EXP layer gets a CSS-safe class derived from its layer name.
        // Classes intentionally may repeat: unlike IDs, duplicate layer names are
        // valid and useful selectors in hand-edited SVG/CSS.
        let layerClass = svgLayerClass(node.name)
        return "<g class=\"\(layerClass)\"\(transform)\(opacity)\(blend)\(filter)>\n\(inner)</g>\n"
    }

    /// Build an SVG `<filter>` for a node's effects and return the
    /// ` filter="url(#id)"` attribute (empty when there are none).
    ///
    /// Primitive order mirrors the raster render exactly:
    ///   1. dissolve — feTurbulence thresholded (feComponentTransfer on alpha)
    ///      and composited `in` against the source, so every later primitive
    ///      (shadows included) sees the dissolved node;
    ///   2. drop shadows under / inner shadows over the (dissolved) source,
    ///      merged with feMerge;
    ///   3. noise — feTurbulence, alpha scaled to `amount`, clipped to the
    ///      source's silhouette, feBlend-ed over the merged result with the
    ///      effect's own blend mode.
    /// `color-interpolation-filters="sRGB"` keeps browsers compositing in the
    /// same space Core Graphics does (the SVG default is linearRGB).
    /// feTurbulence parameters come straight from the Effect fields — the same
    /// numbers `TurbulenceNoise` renders with (see that file for the phase
    /// caveat: SVG samples user space, the canvas samples node-local space).
    private func svgEffectsFilter(_ effects: [Effect], _ defs: inout [String]) -> String {
        let shadows = effects.filter { $0.isEnabled && ($0.kind == .dropShadow || $0.kind == .innerShadow) }
        let layerBlurs = effects.filter { $0.isEnabled && $0.kind == .layerBlur && $0.blur > 0 }
        let dissolves = effects.filter { $0.isEnabled && $0.kind == .dissolve && $0.amount > 0 }
        let noises = effects.filter { $0.isEnabled && $0.kind == .noise && $0.amount > 0 }
        guard !shadows.isEmpty || !layerBlurs.isEmpty || !dissolves.isEmpty || !noises.isEmpty else { return "" }
        let id = "fx\(defs.count)"
        var prims = ""

        func turbulence(_ e: Effect, result: String) -> String {
            "<feTurbulence type=\"\(e.turbulenceType.rawValue)\" baseFrequency=\"\(num(e.frequency))\" numOctaves=\"\(e.octaves)\" seed=\"\(e.seed)\" result=\"\(result)\"/>\n"
        }

        // 1) Layer blur: direct SVG round-trip for standalone feGaussianBlur.
        var src = "SourceGraphic"   // what "the node" means for everything below
        for (i, e) in layerBlurs.enumerated() {
            let r = "l\(i)"
            prims += "<feGaussianBlur in=\"\(src)\" stdDeviation=\"\(num(e.blur))\" result=\"\(r)\"/>\n"
            src = r
        }

        // 2) Dissolve: threshold turbulence into a hard alpha mask, knock the
        //    source through it. Chained, so stacked dissolves intersect.
        for (i, e) in dissolves.enumerated() {
            let r = "d\(i)"
            prims += turbulence(e, result: "\(r)t")
            // A' = R of the turbulence (grayscale channel 0 — matches TurbulenceNoise).
            prims += "<feColorMatrix in=\"\(r)t\" type=\"matrix\" values=\"0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  1 0 0 0 0\" result=\"\(r)a\"/>\n"
            // Steep linear ramp ≈ step(threshold): survives where noise ≥ amount.
            let intercept = -255.0 * Double(e.amount) + 0.5
            prims += "<feComponentTransfer in=\"\(r)a\" result=\"\(r)m\"><feFuncA type=\"linear\" slope=\"255\" intercept=\"\(num(CGFloat(intercept)))\"/></feComponentTransfer>\n"
            prims += "<feComposite in=\"\(src)\" in2=\"\(r)m\" operator=\"in\" result=\"\(r)\"/>\n"
            src = r
        }

        // 3) Shadows (cast from the filtered source's alpha).
        var under: [String] = []   // drop-shadow results (below source)
        var over: [String] = []    // inner-shadow results (above source)
        for (i, e) in shadows.enumerated() {
            let r = "s\(i)", std = num(e.blur / 2)
            let flood = "<feFlood flood-color=\"\(hex(e.color))\" flood-opacity=\"\(num(CGFloat(e.color.a)))\" result=\"\(r)c\"/>\n"
            let alphaSrc = src == "SourceGraphic" ? "SourceAlpha" : src
            if e.kind == .dropShadow {
                let castFrom: String
                if e.spread != 0 {
                    prims += "<feMorphology in=\"\(alphaSrc)\" operator=\"\(e.spread > 0 ? "dilate" : "erode")\" radius=\"\(num(abs(e.spread)))\" result=\"\(r)d\"/>\n"
                    castFrom = "\(r)d"
                } else { castFrom = alphaSrc }
                prims += "<feGaussianBlur in=\"\(castFrom)\" stdDeviation=\"\(std)\" result=\"\(r)b\"/>\n"
                prims += "<feOffset in=\"\(r)b\" dx=\"\(num(e.dx))\" dy=\"\(num(e.dy))\" result=\"\(r)o\"/>\n"
                prims += flood
                if e.preserveTransparency {
                    // Same semantics as the raster knockout: shadow minus the
                    // source's alpha (partial alpha knocks proportionally).
                    prims += "<feComposite in=\"\(r)c\" in2=\"\(r)o\" operator=\"in\" result=\"\(r)f\"/>\n"
                    prims += "<feComposite in=\"\(r)f\" in2=\"\(alphaSrc)\" operator=\"out\" result=\"\(r)\"/>\n"
                } else {
                    prims += "<feComposite in=\"\(r)c\" in2=\"\(r)o\" operator=\"in\" result=\"\(r)\"/>\n"
                }
                under.append(r)
            } else {
                prims += "<feGaussianBlur in=\"\(alphaSrc)\" stdDeviation=\"\(std)\" result=\"\(r)b\"/>\n"
                prims += "<feOffset in=\"\(r)b\" dx=\"\(num(e.dx))\" dy=\"\(num(e.dy))\" result=\"\(r)o\"/>\n"
                prims += "<feComposite in=\"\(alphaSrc)\" in2=\"\(r)o\" operator=\"out\" result=\"\(r)i\"/>\n"
                prims += flood
                prims += "<feComposite in=\"\(r)c\" in2=\"\(r)i\" operator=\"in\" result=\"\(r)\"/>\n"
                over.append(r)
            }
        }
        let order = under + [src] + over
        let merge = order.map { "<feMergeNode in=\"\($0)\"/>\n" }.joined()
        prims += "<feMerge result=\"base\">\n\(merge)</feMerge>\n"

        // 4) Noise: turbulence at the effect's amount, clipped to the node,
        //    blended over everything merged so far.
        var base = "base"
        for (i, e) in noises.enumerated() {
            let r = "n\(i)"
            prims += turbulence(e, result: "\(r)t")
            let a = num(CGFloat(min(1, max(0, e.amount))))
            // Monochrome: R drives all of RGB. Color: RGB pass through.
            // Either way alpha becomes a flat `amount` (matches ctx.setAlpha).
            let rows = e.monochrome
                ? "1 0 0 0 0  1 0 0 0 0  1 0 0 0 0  0 0 0 0 \(a)"
                : "1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 \(a)"
            prims += "<feColorMatrix in=\"\(r)t\" type=\"matrix\" values=\"\(rows)\" result=\"\(r)c\"/>\n"
            let clipTo = src == "SourceGraphic" ? "SourceAlpha" : src
            prims += "<feComposite in=\"\(r)c\" in2=\"\(clipTo)\" operator=\"in\" result=\"\(r)x\"/>\n"
            prims += "<feBlend in=\"\(r)x\" in2=\"\(base)\" mode=\"\(e.blend.cssName)\" result=\"\(r)\"/>\n"
            base = r
        }

        defs.append("  <filter id=\"\(id)\" x=\"-50%\" y=\"-50%\" width=\"200%\" height=\"200%\" color-interpolation-filters=\"sRGB\">\n\(prims)  </filter>\n")
        return " filter=\"url(#\(id))\""
    }

    /// Fill attribute for a Paint, registering a gradient `<def>` when needed.
    /// Gradients use objectBoundingBox units so one def fits any element size.
    private func paintFillAttr(_ paint: Paint, _ defs: inout [String]) -> String {
        switch paint {
        case .solid(let c):
            return fillAttr(c)
        case .gradient(let g):
            let id = "grad\(defs.count)"
            defs.append(svgGradientDef(g, id: id))
            return " fill=\"url(#\(id))\""
        }
    }

    private func svgGradientDef(_ g: GradientFill, id: String) -> String {
        let stops = g.sortedStops.map { stop -> String in
            "    <stop offset=\"\(num(CGFloat(stop.position)))\" stop-color=\"\(hex(stop.color))\"\(opacityAttr("stop-opacity", stop.color.a))/>\n"
        }.joined()
        switch g.kind {
        case .linear:
            let a = g.angle * .pi / 180
            let dx = CGFloat(cos(a)) * 0.5, dy = CGFloat(sin(a)) * 0.5
            let x1 = 0.5 - dx, y1 = 0.5 - dy, x2 = 0.5 + dx, y2 = 0.5 + dy
            return "  <linearGradient id=\"\(id)\" x1=\"\(num(x1))\" y1=\"\(num(y1))\" x2=\"\(num(x2))\" y2=\"\(num(y2))\">\n\(stops)  </linearGradient>\n"
        case .radial:
            return "  <radialGradient id=\"\(id)\" cx=\"0.5\" cy=\"0.5\" r=\"0.5\">\n\(stops)  </radialGradient>\n"
        }
    }

    private func svgPathData(_ ps: PathShape, origin: CGPoint) -> String {
        func a(_ local: CGPoint) -> CGPoint { CGPoint(x: origin.x + local.x, y: origin.y + local.y) }
        func contourData(_ pts: [PathPoint], closed: Bool) -> String {
            guard !pts.isEmpty else { return "" }
            var d = "M \(num(a(pts[0].point).x)) \(num(a(pts[0].point).y))"
            func seg(_ prev: PathPoint, _ cur: PathPoint) {
                let c1 = a(prev.controlOut ?? prev.point), c2 = a(cur.controlIn ?? cur.point), p = a(cur.point)
                d += " C \(num(c1.x)) \(num(c1.y)) \(num(c2.x)) \(num(c2.y)) \(num(p.x)) \(num(p.y))"
            }
            for i in 1..<pts.count { seg(pts[i - 1], pts[i]) }
            if closed && pts.count >= 2 { seg(pts[pts.count - 1], pts[0]); d += " Z" }
            return d
        }
        if ps.isMultiContour {
            return ps.renderContours.map { contourData($0, closed: true) }.joined(separator: " ")
        }
        return contourData(ps.points, closed: ps.closed)
    }

    // MARK: SVG attribute helpers

    private func fillAttr(_ c: RGBAColor) -> String {
        if let binding = DesignLanguageIO.firstAssetBinding(
            matching: .solid(c), in: document.designLanguage) {
            let fallback = DesignLanguageIO.css(for: .solid(c))
            return " fill=\"var(--\(binding.variableName), \(fallback))\""
        }
        return " fill=\"\(hex(c))\"\(opacityAttr("fill-opacity", c.a))"
    }

    private func strokeAttr(_ c: RGBAColor, _ width: CGFloat,
                            _ pattern: StrokePattern = .solid) -> String {
        guard width > 0 else { return "" }
        let rhythm: String
        switch pattern {
        case .solid: rhythm = ""
        case .dashed:
            rhythm = " stroke-dasharray=\"\(num(max(3, width * 3))) \(num(max(2, width * 2)))\" stroke-linecap=\"butt\""
        case .dotted:
            rhythm = " stroke-dasharray=\"0.001 \(num(max(2, width * 2.25)))\" stroke-linecap=\"round\""
        }
        if let binding = DesignLanguageIO.firstAssetBinding(
            matching: .solid(c), in: document.designLanguage) {
            let fallback = DesignLanguageIO.css(for: .solid(c))
            return " stroke=\"var(--\(binding.variableName), \(fallback))\" stroke-width=\"\(num(width))\"\(rhythm)"
        }
        return " stroke=\"\(hex(c))\"\(opacityAttr("stroke-opacity", c.a)) stroke-width=\"\(num(width))\"\(rhythm)"
    }

    /// Standalone SVGs carry the same color-token names as semantic HTML/CSS.
    /// Every usage still includes its literal fallback, so the artwork remains
    /// portable if a downstream tool drops or overrides this style block.
    private func svgTokenStyle() -> String {
        let lines = DesignLanguageIO.cssAssetBindings(document.designLanguage)
            .compactMap { binding -> String? in
                guard case .solid = binding.paint else { return nil }
                return "  --\(binding.variableName): \(DesignLanguageIO.css(for: binding.paint));"
            }
        guard !lines.isEmpty else { return "" }
        return "<style>\n:root {\n\(lines.joined(separator: "\n"))\n}\n</style>\n"
    }

    /// SVG path data for a per-corner rounded rect (A-command arcs, clockwise,
    /// zero-radius corners emitted as plain line joins).
    private func svgRoundedRectData(_ r: CGRect, _ radii: CornerRadii) -> String {
        let c = radii.clamped(to: r.size)
        func arc(_ radius: CGFloat, _ x: CGFloat, _ y: CGFloat) -> String {
            "A\(num(radius)),\(num(radius)) 0 0 1 \(num(x)),\(num(y))"
        }
        var d = "M\(num(r.minX + c.topLeft)),\(num(r.minY))"
        d += "H\(num(r.maxX - c.topRight))"
        if c.topRight > 0 { d += arc(c.topRight, r.maxX, r.minY + c.topRight) }
        d += "V\(num(r.maxY - c.bottomRight))"
        if c.bottomRight > 0 { d += arc(c.bottomRight, r.maxX - c.bottomRight, r.maxY) }
        d += "H\(num(r.minX + c.bottomLeft))"
        if c.bottomLeft > 0 { d += arc(c.bottomLeft, r.minX, r.maxY - c.bottomLeft) }
        d += "V\(num(r.minY + c.topLeft))"
        if c.topLeft > 0 { d += arc(c.topLeft, r.minX + c.topLeft, r.minY) }
        return d + "Z"
    }

    /// Inside/outside stroke for arbitrary closed outlines (polygon/path), the
    /// same construction the canvas uses, in SVG form:
    ///   inside  → the shape as a `clipPath`, stroke at 2× width (outer half
    ///             clipped away — exact);
    ///   outside → a `mask` of (padded white rect − shape), stroke at 2× width
    ///             (inner half masked away — exact).
    /// `shape` is the element WITHOUT its closing "/>" (e.g. `<path d="…"`).
    private func svgAlignedStrokeCopy(shape: String, closer: String, bounds: CGRect,
                                      stroke: RGBAColor, width: CGFloat,
                                      alignment: StrokeAlignment, pattern: StrokePattern,
                                      join: String,
                                      defs: inout [String]) -> String {
        let strokeAttrs = " fill=\"none\"\(strokeAttr(stroke, width * 2, pattern)) stroke-linejoin=\"\(join)\""
        switch alignment {
        case .center:
            return "\(shape)\(strokeAttrs)\(closer)\n"
        case .inside:
            let id = "strokeclip\(defs.count)"
            defs.append("<clipPath id=\"\(id)\">\(shape)\(closer)</clipPath>\n")
            return "\(shape)\(strokeAttrs) clip-path=\"url(#\(id))\"\(closer)\n"
        case .outside:
            let id = "strokemask\(defs.count)"
            let pad = width * 2 + 8
            let b = bounds.insetBy(dx: -pad, dy: -pad)
            defs.append("<mask id=\"\(id)\" maskUnits=\"userSpaceOnUse\" x=\"\(num(b.minX))\" y=\"\(num(b.minY))\" width=\"\(num(b.width))\" height=\"\(num(b.height))\">"
                + "<rect x=\"\(num(b.minX))\" y=\"\(num(b.minY))\" width=\"\(num(b.width))\" height=\"\(num(b.height))\" fill=\"white\"/>"
                + "\(shape) fill=\"black\"\(closer)</mask>\n")
            return "\(shape)\(strokeAttrs) mask=\"url(#\(id))\"\(closer)\n"
        }
    }
    private func opacityAttr(_ name: String, _ a: Double) -> String { a < 1 ? " \(name)=\"\(num(CGFloat(a)))\"" : "" }
    private func hex(_ c: RGBAColor) -> String {
        let r = Int((c.r * 255).rounded())
        let g = Int((c.g * 255).rounded())
        let b = Int((c.b * 255).rounded())
        return String(format: "#%02X%02X%02X", r as CVarArg, g as CVarArg, b as CVarArg)
    }
    private func num(_ v: CGFloat) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(Double(r))
    }
    private func escape(_ s: String) -> String {
        return s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// A stable, readable CSS class. The `layer-` prefix keeps filenames that
    /// begin with digits valid without CSS escaping; punctuation/whitespace fold
    /// into one hyphen while Unicode letters and numbers remain meaningful.
    private func svgLayerClass(_ name: String) -> String {
        let parts = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let slug = parts.joined(separator: "-")
        return slug.isEmpty ? "layer" : "layer-\(slug)"
    }
}

// MARK: - Offscreen render view (flipped → matches our y-down model)

final class ExportRenderView: NSView {
    let document: Document
    let artboard: Artboard
    let drawBackground: Bool

    override var isFlipped: Bool { true }

    init(document: Document, artboard: Artboard, drawBackground: Bool = true) {
        self.document = document
        self.artboard = artboard
        self.drawBackground = drawBackground
        super.init(frame: CGRect(origin: .zero, size: artboard.frame.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if drawBackground {
            PaintRender.fillRect(artboard.background, rect: bounds, in: ctx)
        }
        ctx.clip(to: bounds)
        let off = CGPoint(x: -artboard.frame.minX, y: -artboard.frame.minY)
        let page = document.page(containingArtboard: artboard.id)
        for node in page?.nodes ?? [] where node.isVisible
            && document.owningArtboard(of: node, on: page?.id)?.id == artboard.id {
            drawExportNode(node, offset: off, in: ctx)
        }
    }

    /// Conservative export-space bounds of everything a node can paint — the
    /// clip for its opacity/blend transparency layer. Mirrors the canvas's
    /// `paintBoundsView` (leaf margin / recursive group union / instance frame).
    private func exportPaintBounds(_ node: Node, offset: CGPoint) -> CGRect {
        let rect = node.frame.offsetBy(dx: offset.x, dy: offset.y)
        switch node.content {
        case .group(let children):
            let childOffset = CGPoint(x: rect.minX, y: rect.minY)
            var b = rect
            for child in children where child.isVisible {
                b = b.union(exportPaintBounds(child, offset: childOffset))
            }
            if node.rotation != 0 {
                let grow = hypot(b.width, b.height) / 2
                b = b.insetBy(dx: -grow, dy: -grow)
            }
            return b.insetBy(dx: -2, dy: -2)
        case .instance(let inst):
            // Export draws instance children UNCLIPPED (unlike the canvas, which
            // clips to the viewBox), so bound by the resolved children's union.
            var b = rect
            for child in document.resolvedChildren(of: inst) where child.isVisible {
                b = b.union(exportPaintBounds(child, offset: rect.origin))
            }
            return b.insetBy(dx: -2, dy: -2)
        default:
            var m: CGFloat = 2
            for e in node.effects where e.isEnabled && e.kind == .dropShadow {
                m = max(m, max(abs(e.dx), abs(e.dy)) + e.blur * 3 + e.spread + 2)
            }
            for e in node.effects where e.isEnabled && e.kind == .layerBlur {
                m = max(m, e.blur * 3 + 2)
            }
            m += strokeHalfWidth(node.content)
            if node.rotation != 0 { m += hypot(rect.width, rect.height) / 2 }
            return rect.insetBy(dx: -m, dy: -m)
        }
    }

    /// Mirrors CanvasView.isSinglePaintOp — one fill OR one stroke, no effects.
    private func exportIsSinglePaintOp(_ node: Node) -> Bool {
        guard !node.effects.contains(where: { $0.isEnabled }) else { return false }
        func strokeOp(_ w: CGFloat, _ c: RGBAColor) -> Bool { w > 0 && c.a > 0 }
        func fillOp(_ p: Paint) -> Bool {
            if case .solid(let c) = p { return c.a > 0 }
            return true
        }
        switch node.content {
        case .rectangle(let s): return !(fillOp(s.fill) && strokeOp(s.strokeWidth, s.stroke))
        case .ellipse(let s):   return !(fillOp(s.fill) && strokeOp(s.strokeWidth, s.stroke))
        case .polygon(let s):   return !(fillOp(s.fill) && strokeOp(s.strokeWidth, s.stroke))
        case .path(let s):      return !(fillOp(s.fill) && strokeOp(s.strokeWidth, s.stroke))
        case .line:             return true
        case .image:            return true
        default:                return false
        }
    }

    /// Half the stroke width for stroked leaf content, else 0 — mirrors the
    /// canvas's `strokeReach` (used to bound the opacity/blend layer clip).
    private func strokeHalfWidth(_ c: NodeContent) -> CGFloat {
        switch c {
        case .rectangle(let s): return s.strokeWidth / 2
        case .ellipse(let s):   return s.strokeWidth / 2
        case .polygon(let s):   return s.strokeWidth / 2
        case .line(let s):      return s.strokeWidth / 2
        case .path(let s):      return s.strokeWidth / 2
        default:                return 0
        }
    }

    private func drawExportNode(_ node: Node, offset: CGPoint, in ctx: CGContext) {
        let rect = node.frame.offsetBy(dx: offset.x, dy: offset.y)
        let groupAlpha = max(0, min(1, CGFloat(node.opacity)))
        let needsGroup = groupAlpha < 0.999 || node.blendMode != .normal
        // Single-compositing-op nodes (one fill OR one stroke, no effects) get
        // plain context alpha/blend instead of a transparency layer — identical
        // pixels, no layer buffer. Mirrors CanvasView.isSinglePaintOp.
        let usesLayer = needsGroup && !exportIsSinglePaintOp(node)
        if !usesLayer && needsGroup {
            ctx.saveGState()
            ctx.setAlpha(groupAlpha)
            ctx.setBlendMode(node.blendMode.cg)
        }
        defer { if !usesLayer && needsGroup { ctx.restoreGState() } }
        if usesLayer {
            ctx.saveGState()
            // Bound the layer's buffer to the node's paint reach. An unclipped
            // transparency layer allocates a surface the size of the current
            // clip — the whole export canvas — per semi-transparent node, which
            // makes big exports crawl for the same reason it made the canvas
            // snapshot take seconds. Conservative for every node kind (leaf
            // margin / recursive group union / instance frame); correctness first.
            ctx.clip(to: exportPaintBounds(node, offset: offset))
            ctx.setAlpha(groupAlpha)
            ctx.setBlendMode(node.blendMode.cg)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer { if usesLayer { ctx.endTransparencyLayer(); ctx.restoreGState() } }
        let rotating = node.rotation != 0
        let flipping = node.flipH || node.flipV
        if rotating || flipping {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            if rotating { ctx.rotate(by: CGFloat(node.rotation * .pi / 180)) }
            if flipping { ctx.scaleBy(x: node.flipH ? -1 : 1, y: node.flipV ? -1 : 1) }
            ctx.translateBy(x: -c.x, y: -c.y)
        }
        defer { if rotating || flipping { ctx.restoreGState() } }

        // Effects (scale 1 — export is in model points). Mirrors the canvas.
        let enabled = node.effects.filter { $0.isEnabled }
        let sil = exportSilhouette(node, rect: rect)
        for e in enabled where e.kind == .dropShadow {
            if let s = sil {
                let outset = s.path(spread: CGFloat(e.spread))
                EffectsRender.drawDropShadow(e, scale: 1, in: ctx,
                                             castBounds: outset.boundingBoxOfPath,
                                             knockout: {
                    // True silhouette (spread 0) — mirrors the canvas.
                    ctx.addPath(s.path(spread: 0)); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
                }) {
                    ctx.addPath(outset); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
                }
            } else {
                EffectsRender.drawDropShadow(e, scale: 1, in: ctx, castBounds: rect,
                                             knockout: {
                    self.drawExportNodeContent(node, rect: rect, in: ctx)
                }) {
                    self.drawExportNodeContent(node, rect: rect, in: ctx)
                }
            }
        }

        let layerBlurs = enabled.filter { $0.kind == .layerBlur && $0.blur > 0 }
        if layerBlurs.isEmpty {
            drawExportNodeContent(node, rect: rect, in: ctx)
        } else {
            EffectsRender.drawLayerBlur(layerBlurs,
                                        bounds: exportPaintBounds(node, offset: offset),
                                        deviceScale: 1, in: ctx) { blurContext in
                self.drawExportNodeContent(node, rect: rect, in: blurContext)
            }
        }

        if let s = sil {
            for e in enabled where e.kind == .innerShadow {
                EffectsRender.drawInnerShadow(e, clip: s.clip, hole: s.path(spread: -CGFloat(e.spread)),
                                              in: ctx, scale: 1)
            }
        }
    }

    private func exportSilhouette(_ node: Node, rect: CGRect) -> Silhouette? {
        switch node.content {
        case .rectangle(let s):
            return Silhouette(rect: rect, shape: .perCornerRect(s.effectiveRadii))
        case .ellipse:          return Silhouette(rect: rect, shape: .oval)
        case .polygon(let s):   return Silhouette(rect: rect, shape: .custom(Self.polygonPath(s.vertices(in: rect)).cgPath))
        case .path(let ps) where ps.closed && ps.points.count >= 2:
            return Silhouette(rect: rect, shape: .custom(nsPath(ps, origin: rect.origin).cgPath))
        case .image:            return Silhouette(rect: rect, shape: .roundRect(radius: 0))
        default: return nil
        }
    }

    private func drawExportNodeContent(_ node: Node, rect: CGRect, in ctx: CGContext) {
        switch node.content {
        case .rectangle(let s):
            let path = NSBezierPath(cgPath: s.effectiveRadii.path(in: rect))
            PaintRender.fill(s.fill, path: path, bounds: rect, in: ctx)
            if s.strokeWidth > 0 {
                PaintRender.strokeAligned(path, width: s.strokeWidth,
                                          alignment: s.strokeAlignment, color: s.stroke.ns,
                                          pattern: s.strokePattern, in: ctx)
            }
        case .ellipse(let s):
            let path = NSBezierPath(ovalIn: rect)
            PaintRender.fill(s.fill, path: path, bounds: rect, in: ctx)
            if s.strokeWidth > 0 {
                PaintRender.strokeAligned(path, width: s.strokeWidth,
                                          alignment: s.strokeAlignment, color: s.stroke.ns,
                                          pattern: s.strokePattern, in: ctx)
            }
        case .polygon(let s):
            let path = Self.polygonPath(s.vertices(in: rect))
            PaintRender.fill(s.fill, path: path, bounds: rect, in: ctx)
            if s.strokeWidth > 0 {
                PaintRender.strokeAligned(path, width: s.strokeWidth,
                                          alignment: s.strokeAlignment, color: s.stroke.ns,
                                          join: .miter, pattern: s.strokePattern, in: ctx)
            }
        case .line(let ls):
            let path = NSBezierPath()
            path.move(to: CGPoint(x: rect.minX + ls.start.x, y: rect.minY + ls.start.y))
            path.line(to: CGPoint(x: rect.minX + ls.end.x, y: rect.minY + ls.end.y))
            ctx.saveGState()
            ctx.setStrokeColor(ls.stroke.ns.cgColor)
            ctx.setLineWidth(max(0.1, ls.strokeWidth))
            PaintRender.configureStrokePattern(ls.strokePattern,
                                               width: max(0.1, ls.strokeWidth),
                                               fallbackCap: .round, in: ctx)
            ctx.addPath(path.cgPath); ctx.strokePath(); ctx.restoreGState()
        case .path(let ps):
            let path = nsPath(ps, origin: rect.origin)
            if ps.isMultiContour || (ps.closed && ps.points.count >= 2) {
                PaintRender.fill(ps.fill, path: path, bounds: path.bounds, in: ctx)
            }
            if ps.strokeWidth > 0 {
                PaintRender.strokeAligned(path, width: ps.strokeWidth,
                                          alignment: ps.effectiveStrokeAlignment, color: ps.stroke.ns,
                                          join: .round, cap: .round,
                                          pattern: ps.strokePattern, in: ctx)
            }
        case .text(let t):
            t.attributedString().draw(in: rect)
        case .group(let children):
            if let pad = node.autoPadding, pad.fill != nil || pad.strokeWidth > 0 {
                let box = CGRect(x: rect.minX + pad.marginLeft, y: rect.minY + pad.marginTop,
                                 width: max(0, rect.width - pad.marginW),
                                 height: max(0, rect.height - pad.marginH))
                let path = NSBezierPath(roundedRect: box, xRadius: pad.cornerRadius, yRadius: pad.cornerRadius)
                if let fill = pad.fill { PaintRender.fill(fill, path: path, bounds: box, in: ctx) }
                if pad.strokeWidth > 0, let stroke = pad.stroke {
                    PaintRender.strokeAligned(path, width: pad.strokeWidth,
                                              alignment: pad.strokeAlignment,
                                              color: stroke.ns,
                                              pattern: pad.strokePattern, in: ctx)
                }
            }
            if node.isMask {
                // Clip content children to the mask shape(s)' union (raster export).
                let clip = CGMutablePath()
                for child in children where child.isMaskShape && child.isVisible {
                    appendExportSilhouette(of: child, offset: rect.origin, base: .identity, into: clip)
                }
                ctx.saveGState()
                if !clip.isEmpty { ctx.addPath(clip); ctx.clip() }
                for child in children where !child.isMaskShape && child.isVisible {
                    drawExportNode(child, offset: rect.origin, in: ctx)
                }
                ctx.restoreGState()
            } else {
                for child in children where child.isVisible { drawExportNode(child, offset: rect.origin, in: ctx) }
            }
        case .instance(let inst):
            for child in document.resolvedChildren(of: inst) {
                drawExportNode(child, offset: rect.origin, in: ctx)
            }
        case .image(let img):
            if let ns = NSImage(data: img.data),
               let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.saveGState()
                ctx.translateBy(x: rect.minX, y: rect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
                ctx.restoreGState()
            }
        }
    }

    /// Mask clip silhouette in export (1:1) space — mirrors the canvas's
    /// `appendSilhouette`, including per-node rotation/flip about each node's center
    /// composed with ancestor transforms via `base`.
    private func appendExportSilhouette(of node: Node, offset: CGPoint,
                                        base: CGAffineTransform, into path: CGMutablePath) {
        let r = node.frame.offsetBy(dx: offset.x, dy: offset.y)
        let c = CGPoint(x: r.midX, y: r.midY)
        var t = CGAffineTransform.identity.translatedBy(x: c.x, y: c.y)
        if node.rotation != 0 { t = t.rotated(by: CGFloat(node.rotation * .pi / 180)) }
        if node.flipH || node.flipV { t = t.scaledBy(x: node.flipH ? -1 : 1, y: node.flipV ? -1 : 1) }
        t = t.translatedBy(x: -c.x, y: -c.y)
        let m = t.concatenating(base)
        switch node.content {
        case .group(let kids):
            for k in kids where k.isVisible { appendExportSilhouette(of: k, offset: r.origin, base: m, into: path) }
        case .rectangle(let s):
            path.addPath(s.effectiveRadii.path(in: r), transform: m)
        case .ellipse:
            path.addPath(CGPath(ellipseIn: r, transform: nil), transform: m)
        case .polygon(let s):
            path.addPath(Self.polygonPath(s.vertices(in: r)).cgPath, transform: m)
        case .path(let ps) where ps.isMultiContour || (ps.closed && ps.points.count >= 2):
            path.addPath(nsPath(ps, origin: r.origin).cgPath, transform: m)
        default:
            path.addPath(CGPath(rect: r, transform: nil), transform: m)
        }
    }

    static func polygonPath(_ verts: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = verts.first else { return path }
        path.move(to: first)
        for v in verts.dropFirst() { path.line(to: v) }
        path.close()
        return path
    }

    private func nsPath(_ ps: PathShape, origin: CGPoint) -> NSBezierPath {
        let path = NSBezierPath()
        func a(_ l: CGPoint) -> CGPoint { CGPoint(x: origin.x + l.x, y: origin.y + l.y) }
        func addContour(_ pts: [PathPoint], closed: Bool) {
            guard !pts.isEmpty else { return }
            path.move(to: a(pts[0].point))
            for i in 1..<pts.count {
                let prev = pts[i - 1], cur = pts[i]
                path.curve(to: a(cur.point), controlPoint1: a(prev.controlOut ?? prev.point), controlPoint2: a(cur.controlIn ?? cur.point))
            }
            if closed && pts.count >= 2 {
                let last = pts[pts.count - 1], first = pts[0]
                path.curve(to: a(first.point), controlPoint1: a(last.controlOut ?? last.point), controlPoint2: a(first.controlIn ?? first.point))
                path.close()
            }
        }
        if ps.isMultiContour {
            for c in ps.renderContours { addContour(c, closed: true) }
            path.windingRule = .nonZero          // font glyphs use nonzero winding
        } else {
            addContour(ps.points, closed: ps.closed)
        }
        return path
    }
}

private extension RGBAColor {
    var ns: NSColor { NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }
}

// MARK: - Notes page (Letter portrait, flipped → correct text)

final class NotesRenderView: NSView {
    let title: String
    let notes: String

    override var isFlipped: Bool { true }

    init(title: String, notes: String) {
        self.title = title
        self.notes = notes
        super.init(frame: CGRect(x: 0, y: 0, width: 612, height: 792))   // US Letter @72dpi
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let margin: CGFloat = 54
        let textWidth = bounds.width - margin * 2

        let header = "Notes — \(title)"
        (header as NSString).draw(
            in: CGRect(x: margin, y: margin, width: textWidth, height: 26),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.black])

        // Hairline under the heading.
        let rule = NSBezierPath()
        rule.move(to: CGPoint(x: margin, y: margin + 34))
        rule.line(to: CGPoint(x: bounds.width - margin, y: margin + 34))
        NSColor.gray.withAlphaComponent(0.4).setStroke()
        rule.lineWidth = 0.5
        rule.stroke()

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        (notes as NSString).draw(
            in: CGRect(x: margin, y: margin + 46, width: textWidth, height: bounds.height - margin * 2 - 46),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                             .foregroundColor: NSColor.black,
                             .paragraphStyle: para])
    }
}
