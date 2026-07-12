//
//  PDFImporter.swift
//  EXP [design]
//
//  Imports a PDF as EDITABLE native layers (mirrors SVGImporter's spirit).
//
//  Strategy (v1 — see ROADMAP "PDF import"):
//   • Each page's content stream is walked with a CGPDFScanner. Path-construction
//     and painting operators become editable Path layers; text-showing operators
//     become editable Text layers (system-font fallback when the PDF's font isn't
//     installed). Solid colors (gray/RGB/CMYK), the q/Q graphics-state stack, cm
//     transforms, and nested Form XObjects are all handled.
//   • Anything this pass can't yet reconstruct FAITHFULLY — image XObjects,
//     axial/radial shadings & pattern (gradient) fills, soft masks, or a rotated
//     page — flips that ONE page to a faithful flat raster instead of shipping a
//     broken partial reconstruction. Pure vector/text pages come in fully
//     editable. (Peeling images/gradients out of mixed pages is the planned
//     next iteration toward full fidelity.)
//
//  Coordinates: PDF user space is y-UP from the crop-box origin; our document
//  space is y-DOWN from the page's top-left. `m0` performs that flip so emitted
//  geometry lands in document points, same convention as SVGImporter.
//

import Foundation
import CoreGraphics
import CoreText
import AppKit
import PDFKit

enum PDFImporter {

    /// One imported page: its size in points and the editable nodes that make it
    /// up (already in PAGE-LOCAL document space — top-left origin). The caller
    /// offsets these into an artboard, or wraps them in a group for paste/drop.
    struct Page { let size: CGSize; let nodes: [Node] }

    // MARK: Public entry points

    /// Number of pages, or 0 if the data isn't a readable PDF.
    static func pageCount(from data: Data) -> Int {
        guard let doc = document(from: data) else { return 0 }
        return doc.numberOfPages
    }

    /// Import the requested pages (1-based; nil = all) as editable nodes. Returns
    /// nil only if the data isn't a usable PDF.
    static func importPages(from data: Data, pages: [Int]? = nil,
                            rasterScale: CGFloat = 2) -> [Page]? {
        guard let doc = document(from: data) else { return nil }
        let pdfkit = PDFDocument(data: data)   // reference renderer for raster fallback
        let wanted = (pages ?? Array(1...max(1, doc.numberOfPages)))
            .filter { $0 >= 1 && $0 <= doc.numberOfPages }
        var out: [Page] = []
        for n in wanted {
            guard let page = doc.page(at: n) else { continue }
            out.append(importOne(page, pdfKitPage: pdfkit?.page(at: n - 1), rasterScale: rasterScale))
        }
        return out
    }

    /// Import a single page's content wrapped in ONE group node at the origin —
    /// used when a PDF is pasted or dragged in from another app (Illustrator,
    /// Figma, Sketch, Preview all put `com.adobe.pdf` on the pasteboard for a
    /// vector copy). Mirrors `SVGImporter.importGroup`.
    static func importGroup(from data: Data, page: Int = 1) -> Node? {
        guard let pages = importPages(from: data, pages: [page]), let p = pages.first,
              !p.nodes.isEmpty else { return nil }
        return groupFromNodes(p.nodes, name: "PDF")
    }

    /// Lay imported pages out left-to-right as artboards (each page → one board),
    /// returning the boards plus every page's nodes offset into document space at
    /// the board's position. Used by both "open a PDF as a new document" and
    /// "Import PDF… into the current document".
    static func layout(_ pages: [Page], origin: CGPoint = .zero, gap: CGFloat = 120,
                       namePrefix: String = "Page") -> (artboards: [Artboard], nodes: [Node]) {
        var boards: [Artboard] = []
        var nodes: [Node] = []
        var x = origin.x
        for (idx, page) in pages.enumerated() {
            let frame = CGRect(x: x, y: origin.y, width: page.size.width, height: page.size.height)
            boards.append(Artboard(name: "\(namePrefix) \(idx + 1)", frame: frame))
            for n in page.nodes {
                var c = n
                c.frame.origin.x += frame.origin.x
                c.frame.origin.y += frame.origin.y
                nodes.append(c)
            }
            x += page.size.width + gap
        }
        return (boards, nodes)
    }

    // MARK: Per-page import

    private static func importOne(_ page: CGPDFPage, pdfKitPage: PDFPage?, rasterScale: CGFloat) -> Page {
        let box = page.getBoxRect(.cropBox)
        var size = CGSize(width: abs(box.width), height: abs(box.height))
        // Guard a corrupt/absurd page box (would make a NaN artboard rect → hang).
        if !size.width.isFinite || !size.height.isFinite || size.width < 1 || size.height < 1
            || size.width > 200_000 || size.height > 200_000 {
            size = CGSize(width: 612, height: 792)   // US-Letter fallback
        }
        // A rotated page is rasterized (the editable path math assumes an
        // un-rotated page); PDFKit's raster honors /Rotate.
        let rotated = page.rotationAngle % 360 != 0

        if !rotated {
            let scan = PageScan(cropBox: box)
            scan.run(page)
            if !scan.needsRaster, !scan.nodes.isEmpty {
                return Page(size: size, nodes: scan.nodes)
            }
        }
        // Raster fallback (whole page → one image node), or a blank page.
        if let png = rasterPNG(pdfKitPage, scale: rasterScale) {
            let node = Node(name: "PDF Page",
                            frame: CGRect(origin: .zero, size: size),
                            content: .image(ImageContent(data: png, naturalSize: size)))
            return Page(size: size, nodes: [node])
        }
        return Page(size: size, nodes: [])
    }

    // MARK: PDF document handle

    private static func document(from data: Data) -> CGPDFDocument? {
        guard let provider = CGDataProvider(data: data as CFData),
              let doc = CGPDFDocument(provider), doc.numberOfPages > 0 else { return nil }
        return doc
    }

    // MARK: Raster fallback (PDFKit — upright + rotation-correct)

    /// Render a page to upright PNG bytes via PDFKit (the reference renderer, so
    /// orientation and /Rotate are always right — the earlier hand-rolled CGContext
    /// flip came out upside-down). Returns nil on failure.
    static func rasterPNG(_ page: PDFPage?, scale: CGFloat) -> Data? {
        guard let page else { return nil }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        // Cap the longest side so a large page can't build a giant bitmap. 2560px
        // keeps a page crisp at normal zoom while holding one raster to ~26MB
        // decoded (4096 was ~67MB — several of those spiked memory on import).
        let maxPx: CGFloat = 2560
        let longest = max(bounds.width, bounds.height)
        let effScale = longest > 0 ? min(scale, maxPx / longest) : scale
        let px = NSSize(width: max(1, bounds.width * effScale), height: max(1, bounds.height * effScale))
        let img = page.thumbnail(of: px, for: .cropBox)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Raster PNG for a single page of raw PDF data (1-based). Used by paste/drop's
    /// fallback so we NEVER hand raw PDF bytes to an image node (NSImage would treat
    /// them as a PDF-backed image, which errors + beach-balls the canvas on redraw).
    static func rasterPNGForPage(from data: Data, page: Int = 1, scale: CGFloat = 2) -> Data? {
        guard let pdf = PDFDocument(data: data) else { return nil }
        return rasterPNG(pdf.page(at: page - 1), scale: scale)
    }

    // MARK: Group wrapper (paste / drop)

    /// Wrap loose nodes (page-local coords) into a group at the origin, children
    /// re-based to the group's bounds. Mirrors `SVGImporter.groupNode`.
    private static func groupFromNodes(_ nodes: [Node], name: String) -> Node? {
        guard let first = nodes.first else { return nil }
        let bounds = nodes.map(\.frame).reduce(first.frame) { $0.union($1) }
        let local = nodes.map { n -> Node in
            var c = n
            c.frame.origin = CGPoint(x: n.frame.minX - bounds.minX, y: n.frame.minY - bounds.minY)
            return c
        }
        return Node(name: name, frame: bounds, content: .group(children: local))
    }
}

// MARK: - Content-stream scanner
//
// Holds the graphics state + the path being built, and appends finished Nodes.
// Operator callbacks (below) are context-free C closures that reach this object
// through the scanner's `info` pointer.

private nonisolated final class PageScan {

    // Graphics state that q/Q save & restore.
    struct GState {
        var ctm: CGAffineTransform = .identity   // user space → page user space
        var fill: RGBAColor = .black
        var stroke: RGBAColor = .black
        var lineWidth: CGFloat = 1
        var fillCSComps = 1                       // components for sc/scn (fill)
        var strokeCSComps = 1                     // components for SC/SCN (stroke)
    }

    private struct SubPath { var points: [PathPoint]; var closed: Bool }

    // page user space → document space (top-left, y-down)
    private let m0: CGAffineTransform
    private var gs = GState()
    private var stack: [GState] = []

    // Path under construction (points already in DOCUMENT space).
    private var subpaths: [SubPath] = []
    private var working: [PathPoint] = []
    private var workingClosed = false
    private var currentUser: CGPoint = .zero      // current point in USER space
    private var startUser: CGPoint = .zero        // subpath start (for h/close)

    // Text object state (transient; not saved by q/Q).
    private var tm: CGAffineTransform = .identity
    private var tlm: CGAffineTransform = .identity
    private var leading: CGFloat = 0
    private var fontSize: CGFloat = 0
    private var fontName: String = ""
    private var fontReliable = true

    private var depth = 0
    // Page-level Resources dict, used as fallback for Form XObjects that inherit resources.
    private var pageResDict: CGPDFDictionaryRef?

    private(set) var nodes: [Node] = []
    private(set) var needsRaster = false
    private var totalPoints = 0
    static let maxPointsPerNode = 12_000
    static let maxPointsPerPage = 60_000

    init(cropBox: CGRect) {
        m0 = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -cropBox.minX, ty: cropBox.maxY)
    }

    func markRaster() { needsRaster = true }

    // MARK: Run

    func run(_ page: CGPDFPage) {
		if let pageDict = page.dictionary {
            var r: CGPDFDictionaryRef?
            CGPDFDictionaryGetDictionary(pageDict, "Resources", &r)
            pageResDict = r
        }
        let stream = CGPDFContentStreamCreateWithPage(page)
        let info = Unmanaged.passUnretained(self).toOpaque()
        let scanner = CGPDFScannerCreate(stream, PageScan.table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
    }

    // MARK: Transforms & doc mapping

    /// User-space point → document space.
    private func d(_ p: CGPoint) -> CGPoint { p.applying(gs.ctm).applying(m0) }

    /// Approximate uniform scale of the current CTM (for line width).
    private var ctmScale: CGFloat {
        let sx = hypot(gs.ctm.a, gs.ctm.b), sy = hypot(gs.ctm.c, gs.ctm.d)
        return (sx + sy) / 2
    }

    // MARK: Graphics state

    func gSave() { stack.append(gs) }
    func gRestore() { if let g = stack.popLast() { gs = g } }
    func concat(_ m: CGAffineTransform) { gs.ctm = m.concatenating(gs.ctm) }
    func setLineWidth(_ w: CGFloat) { gs.lineWidth = w }

    func setFill(_ c: RGBAColor) { gs.fill = c }
    func setStroke(_ c: RGBAColor) { gs.stroke = c }

    // MARK: Path construction (points captured in DOC space)

    func moveTo(_ x: CGFloat, _ y: CGFloat) {
        flushWorking()
        currentUser = CGPoint(x: x, y: y); startUser = currentUser
        working = [PathPoint(point: d(currentUser))]
        workingClosed = false
    }

    func lineTo(_ x: CGFloat, _ y: CGFloat) {
        if working.isEmpty { moveTo(x, y); return }
        currentUser = CGPoint(x: x, y: y)
        working.append(PathPoint(point: d(currentUser)))
    }

    /// Full cubic: control points cp1, cp2 and endpoint (all user space).
    func curveTo(_ cp1: CGPoint, _ cp2: CGPoint, _ end: CGPoint) {
        if working.isEmpty { working = [PathPoint(point: d(currentUser))] }
        working[working.count - 1].controlOut = d(cp1)
        working.append(PathPoint(point: d(end), controlIn: d(cp2)))
        currentUser = end
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        flushWorking()
        let c = [CGPoint(x: x, y: y), CGPoint(x: x + w, y: y),
                 CGPoint(x: x + w, y: y + h), CGPoint(x: x, y: y + h)]
        subpaths.append(SubPath(points: c.map { PathPoint(point: d($0)) }, closed: true))
        currentUser = CGPoint(x: x, y: y); startUser = currentUser
    }

    func closePath() {
        workingClosed = true
        currentUser = startUser
    }

    private func flushWorking() {
        if working.count >= 2 { subpaths.append(SubPath(points: working, closed: workingClosed)) }
        working = []; workingClosed = false
    }

    private func resetPath() { subpaths = []; working = []; workingClosed = false }

    // MARK: Painting

    /// `fill`/`stroke` say which the operator paints; `close` closes the last
    /// subpath first (b/b*/s). Even-odd is irrelevant to our model but noted.
    func paint(fill: Bool, stroke: Bool, close: Bool) {
        if close { closePath() }
        flushWorking()
        defer { resetPath() }
        // `n` (end path, e.g. after a W clip) paints nothing — emit no nodes.
        guard fill || stroke, !subpaths.isEmpty else { return }
        guard nodes.count < Self.nodeCap else { markRaster(); return }   // node explosion → raster
        let sw = stroke ? max(0.1, gs.lineWidth * ctmScale) : 0

        if fill {
            // One node; multiple subpaths → even-odd compound (holes punch through).
            let contours = subpaths.map(\.points)
            if let node = buildNode(contours: contours, closed: true,
                                    fill: .solid(gs.fill),
                                    stroke: stroke ? gs.stroke : .black,
                                    strokeWidth: sw) {
                nodes.append(node)
            }
        } else {
            // Stroke-only: one node per subpath, each keeping its own open/closed.
            for sp in subpaths {
                if let node = buildNode(contours: [sp.points], closed: sp.closed,
                                        fill: .clear, stroke: gs.stroke, strokeWidth: sw) {
                    nodes.append(node)
                }
            }
        }
    }

    /// Build a Path node from doc-space contours (localized to their bbox).
    private func buildNode(contours: [[PathPoint]], closed: Bool, fill: Paint,
                           stroke: RGBAColor, strokeWidth: CGFloat) -> Node? {
        let all = contours.flatMap { $0 }
        guard all.count >= 2 else { return nil }
        // A single path with tens of thousands of points renders + hit-tests O(n)
        // every frame and can beach-ball the canvas — cap it (per node AND per
        // page) and rasterize instead.
        guard all.count <= Self.maxPointsPerNode else { markRaster(); return nil }
        totalPoints += all.count
        guard totalPoints <= Self.maxPointsPerPage else { markRaster(); return nil }
        // Reject corrupt geometry — a NaN/Inf or absurd coordinate produces a NaN
        // CGRect, which beach-balls AppKit on every redraw and hit-test.
        for p in all where !(Self.finite(p.point) && Self.finite(p.controlIn) && Self.finite(p.controlOut)) {
            return nil
        }
        let bounds = pointsBounds(all)
        guard Self.sane(bounds) else { return nil }
        let origin = bounds.origin
        let localized = contours.map { $0.map { localize($0, by: origin) } }
        var ps = PathShape(points: localized[0], closed: closed, fill: fill,
                           stroke: stroke, strokeWidth: strokeWidth)
        if localized.count > 1 { ps.contours = localized }
        return Node(name: "Path", frame: bounds, content: .path(ps))
    }

    // MARK: Text

    func beginText() { tm = .identity; tlm = .identity }
    func setTextMatrix(_ m: CGAffineTransform) { tm = m; tlm = m }
    func textMove(_ tx: CGFloat, _ ty: CGFloat, setLeading: Bool) {
        if setLeading { leading = -ty }
        tlm = CGAffineTransform(translationX: tx, y: ty).concatenating(tlm)
        tm = tlm
    }
    func textNextLine() { textMove(0, -leading, setLeading: false) }
    func setLeading(_ l: CGFloat) { leading = l }
    func setFont(_ name: String, _ size: CGFloat, reliable: Bool) { fontName = name; fontSize = size; fontReliable = reliable }

    /// Heuristic: does a decoded PDF string look like real text (vs. glyph-index
    /// garbage from a font with no ToUnicode)? Flags control chars, the Unicode
    /// private-use area, and the replacement char as "bad"; needs ≥70% good.
    static func isLikelyText(_ s: String) -> Bool {
        var good = 0, total = 0
        for u in s.unicodeScalars {
            total += 1
            let v = u.value
            if v == 0x09 || v == 0x0A || v == 0x20 { good += 1 }                  // tab/newline/space
            else if v >= 0x21 && v < 0x7F { good += 1 }                            // printable ASCII
            else if v >= 0xA1 && v < 0x2500 && !(v >= 0xE000 && v <= 0xF8FF) { good += 1 }  // common Latin/extended (not PUA)
            else if u.properties.isAlphabetic && !(v >= 0xE000 && v <= 0xF8FF) { good += 1 } // other real letters (CJK etc.)
        }
        guard total > 0 else { return false }
        return Double(good) / Double(total) >= 0.7
    }

    /// Emit one editable text node for a shown string at the current text matrix.
    /// Measured with CoreText (thread-safe / nonisolated), NOT the MainActor
    /// `TextContent.measuredSize()`, since this runs inside the nonisolated
    /// content-stream callbacks.
    func showText(_ string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, fontSize > 0 else { return }
        guard nodes.count < Self.nodeCap else { markRaster(); return }
        // Subset/CID fonts with no ToUnicode map decode to junk (private-use /
        // control scalars). Editable gibberish is worse than a faithful raster, so
        // a page with undecodable text rasterizes instead. (Advance the matrix so
        // any decodable text on the same line still positions correctly.)
        // Unreliable font (subset, no ToUnicode → scrambled letters) OR output that
        // still looks like glyph garbage → rasterize the page instead of emitting
        // wrong-but-valid-looking text.
        if !fontReliable || !Self.isLikelyText(s) {
            markRaster()
            let A0 = tm.concatenating(gs.ctm), sx = hypot(A0.a, A0.b)
            if sx > 0 { tm = CGAffineTransform(translationX: fontSize * CGFloat(s.count) * 0.5, y: 0).concatenating(tm) }
            return
        }
        let A = tm.concatenating(gs.ctm)               // text space → page user space
        let originDoc = CGPoint.zero.applying(A).applying(m0)
        let scaleY = hypot(A.c, A.d)
        let fs = max(1, fontSize * scaleY)
        let color = gs.fill
        var tc = TextContent(string: s, fontSize: fs, color: color, fontName: fontName)
        tc.runs = [TextRun(string: s, fontName: fontName, fontSize: fs, color: color)]

        // CoreText line metrics.
        let ctFont = CTFontCreateWithName((fontName.isEmpty ? "Helvetica" : fontName) as CFString, fs, nil)
        let attrs = [kCTFontAttributeName: ctFont] as CFDictionary
        var width = fs * CGFloat(s.count) * 0.5, ascent = fs * 0.8, descent = fs * 0.2, lead: CGFloat = 0
        if let cfStr = CFAttributedStringCreate(nil, s as CFString, attrs) {
            let line = CTLineCreateWithAttributedString(cfStr)
            width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &lead))
        }
        let size = CGSize(width: max(20, ceil(width) + 2),
                          height: max(ceil(fs * 1.3), ceil(ascent + descent + lead)))
        // Text matrix origin is the baseline; our frame origin is the top-left.
        let origin = CGPoint(x: originDoc.x, y: originDoc.y - ascent)
        let frame = CGRect(origin: origin, size: size)
        guard Self.sane(frame) else { return }   // skip corrupt-transform text
        let node = Node(name: String(s.prefix(24)), frame: frame, content: .text(tc))
        nodes.append(node)
        // Advance the text line by the shown width so the next chunk doesn't stack.
        let scaleX = hypot(A.a, A.b)
        if scaleX > 0 { tm = CGAffineTransform(translationX: size.width / scaleX, y: 0).concatenating(tm) }
    }

    /// Resolve a font resource name → an installed PostScript name, or "" (system)
    /// when the PDF's font isn't available (owner's spec: fall back to system).
    func resolveFont(_ name: String, scanner: CGPDFScannerRef) -> (name: String, reliable: Bool) {
        let cs = CGPDFScannerGetContentStream(scanner)
        guard let obj = CGPDFContentStreamGetResource(cs, "Font", name) else { return ("", true) }
        var dict: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(obj, .dictionary, &dict), let dict else { return ("", true) }
        var base: UnsafePointer<Int8>?
        var psName = ""
        if CGPDFDictionaryGetName(dict, "BaseFont", &base), let base { psName = String(cString: base) }
        let reliable = Self.fontDecodesReliably(dict, baseFont: psName)
        // Subset fonts are prefixed like "ABCDEF+Helvetica" — strip that.
        if let plus = psName.firstIndex(of: "+"), psName.distance(from: psName.startIndex, to: plus) == 6 {
            psName = String(psName[psName.index(after: plus)...])
        }
        return (NSFont(name: psName, size: 12) != nil ? psName : "", reliable)
    }

    /// Whether text drawn with this font decodes to correct Unicode. Reliable when
    /// the font carries a ToUnicode CMap OR a standard named encoding OR is a
    /// non-subset base font (built-in standard encoding). A SUBSET font (ABCDEF+…)
    /// with a custom/Identity encoding and no ToUnicode decodes to scrambled but
    /// valid-looking letters — the "gibberish beside good text" case — so its page
    /// is rasterized instead of showing wrong text.
    static func fontDecodesReliably(_ dict: CGPDFDictionaryRef, baseFont: String) -> Bool {
        var tu: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(dict, "ToUnicode", &tu) { return true }
        var enc: UnsafePointer<Int8>?
        if CGPDFDictionaryGetName(dict, "Encoding", &enc), let enc,
           String(cString: enc).hasSuffix("Encoding") { return true }   // WinAnsi/MacRoman/Standard/MacExpert
        let chars = Array(baseFont)
        let isSubset = chars.count > 7 && chars[6] == "+"
        return !isSubset
    }

    // MARK: Form XObject recursion

    func runForm(_ stream: CGPDFStreamRef, parent: CGPDFContentStreamRef, scannerInfo: UnsafeMutableRawPointer) {
        guard depth < 12 else { return }
        let dict = CGPDFStreamGetDictionary(stream)
        var m = CGAffineTransform.identity
        var marr: CGPDFArrayRef?
        if let dict, CGPDFDictionaryGetArray(dict, "Matrix", &marr), let marr, CGPDFArrayGetCount(marr) >= 6 {
            var v = [CGPDFReal](repeating: 0, count: 6)
            for i in 0..<6 { CGPDFArrayGetNumber(marr, i, &v[i]) }
            m = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        }
        var resDict: CGPDFDictionaryRef?
        if let dict { CGPDFDictionaryGetDictionary(dict, "Resources", &resDict) }
        // Form XObjects without their own Resources dict inherit from the parent page.
        guard let effectiveResDict = resDict ?? pageResDict else { return }

        // Save state + suspend the outer path so the form can't corrupt it.
        gSave()
        let savedSub = subpaths, savedWork = working, savedClosed = workingClosed
        subpaths = []; working = []; workingClosed = false
        concat(m)
        depth += 1

        let formCS = CGPDFContentStreamCreateWithStream(stream, effectiveResDict, parent)
        let sc = CGPDFScannerCreate(formCS, PageScan.table, scannerInfo)
        CGPDFScannerScan(sc)
        CGPDFScannerRelease(sc)
        CGPDFContentStreamRelease(formCS)

        depth -= 1
        subpaths = savedSub; working = savedWork; workingClosed = savedClosed
        gRestore()
    }

    // MARK: Geometry helpers

    private func localize(_ p: PathPoint, by o: CGPoint) -> PathPoint {
        PathPoint(point: CGPoint(x: p.point.x - o.x, y: p.point.y - o.y),
                  controlIn: p.controlIn.map { CGPoint(x: $0.x - o.x, y: $0.y - o.y) },
                  controlOut: p.controlOut.map { CGPoint(x: $0.x - o.x, y: $0.y - o.y) })
    }

    // Geometry sanity — reject NaN/Inf/absurd values that would make a NaN CGRect
    // (a well-known AppKit beach-ball) or an unusable node explosion.
    static let maxCoord: CGFloat = 1_000_000
    static let nodeCap = 2500   // pages denser than this rasterize (stability; raise once confirmed safe)
    static func finite(_ p: CGPoint) -> Bool { p.x.isFinite && p.y.isFinite }
    static func finite(_ p: CGPoint?) -> Bool { p.map { $0.x.isFinite && $0.y.isFinite } ?? true }
    static func sane(_ r: CGRect) -> Bool {
        r.origin.x.isFinite && r.origin.y.isFinite && r.width.isFinite && r.height.isFinite
            && abs(r.minX) < maxCoord && abs(r.minY) < maxCoord && r.width < maxCoord && r.height < maxCoord
    }

    private func pointsBounds(_ pts: [PathPoint]) -> CGRect {
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for p in pts {
            xs.append(p.point.x); ys.append(p.point.y)
            if let c = p.controlIn { xs.append(c.x); ys.append(c.y) }
            if let c = p.controlOut { xs.append(c.x); ys.append(c.y) }
        }
        guard let minX = xs.min(), let minY = ys.min(),
              let maxX = xs.max(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    // MARK: Operator table (built once, shared by every scanner)
    //
    // The callbacks are @convention(c) closures — they CANNOT capture context, so
    // they reach the scanner state through the `info` pointer via the file-scope
    // `scanState`/`popNum` helpers below (referencing a local func would capture).

    static let table: CGPDFOperatorTableRef = {
        let t = CGPDFOperatorTableCreate()!
        func cb(_ op: String, _ f: @escaping @convention(c) (CGPDFScannerRef, UnsafeMutableRawPointer?) -> Void) {
            CGPDFOperatorTableSetCallback(t, op, f)
        }

        // Graphics state
        cb("q") { _, i in scanState(i).gSave() }
        cb("Q") { _, i in scanState(i).gRestore() }
        cb("cm") { sc, i in
            let f = popNum(sc), e = popNum(sc), d = popNum(sc), c = popNum(sc), b = popNum(sc), a = popNum(sc)
            scanState(i).concat(CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f))
        }
        cb("w") { sc, i in scanState(i).setLineWidth(popNum(sc)) }

        // Path construction
        cb("m") { sc, i in let y = popNum(sc), x = popNum(sc); scanState(i).moveTo(x, y) }
        cb("l") { sc, i in let y = popNum(sc), x = popNum(sc); scanState(i).lineTo(x, y) }
        cb("c") { sc, i in
            let y3 = popNum(sc), x3 = popNum(sc), y2 = popNum(sc), x2 = popNum(sc), y1 = popNum(sc), x1 = popNum(sc)
            scanState(i).curveTo(CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2), CGPoint(x: x3, y: y3))
        }
        cb("v") { sc, i in   // first control point = current point
            let y3 = popNum(sc), x3 = popNum(sc), y2 = popNum(sc), x2 = popNum(sc)
            let s = scanState(i)
            s.curveTo(s.currentUserPoint, CGPoint(x: x2, y: y2), CGPoint(x: x3, y: y3))
        }
        cb("y") { sc, i in   // second control point = endpoint
            let y3 = popNum(sc), x3 = popNum(sc), y1 = popNum(sc), x1 = popNum(sc)
            scanState(i).curveTo(CGPoint(x: x1, y: y1), CGPoint(x: x3, y: y3), CGPoint(x: x3, y: y3))
        }
        cb("re") { sc, i in
            let h = popNum(sc), w = popNum(sc), y = popNum(sc), x = popNum(sc)
            scanState(i).rect(x, y, w, h)
        }
        cb("h") { _, i in scanState(i).closePath() }

        // Painting (fill / stroke / both / close variants). n ends path (post-clip).
        cb("f")  { _, i in scanState(i).paint(fill: true,  stroke: false, close: false) }
        cb("F")  { _, i in scanState(i).paint(fill: true,  stroke: false, close: false) }
        cb("f*") { _, i in scanState(i).paint(fill: true,  stroke: false, close: false) }
        cb("S")  { _, i in scanState(i).paint(fill: false, stroke: true,  close: false) }
        cb("s")  { _, i in scanState(i).paint(fill: false, stroke: true,  close: true) }
        cb("B")  { _, i in scanState(i).paint(fill: true,  stroke: true,  close: false) }
        cb("B*") { _, i in scanState(i).paint(fill: true,  stroke: true,  close: false) }
        cb("b")  { _, i in scanState(i).paint(fill: true,  stroke: true,  close: true) }
        cb("b*") { _, i in scanState(i).paint(fill: true,  stroke: true,  close: true) }
        cb("n")  { _, i in scanState(i).paint(fill: false, stroke: false, close: false) }

        // Color — fill (lowercase) and stroke (uppercase)
        cb("g")  { sc, i in let v = popNum(sc); scanState(i).setFill(pdfGray(v)) }
        cb("G")  { sc, i in let v = popNum(sc); scanState(i).setStroke(pdfGray(v)) }
        cb("rg") { sc, i in let b = popNum(sc), g = popNum(sc), r = popNum(sc); scanState(i).setFill(RGBAColor(r: r, g: g, b: b, a: 1)) }
        cb("RG") { sc, i in let b = popNum(sc), g = popNum(sc), r = popNum(sc); scanState(i).setStroke(RGBAColor(r: r, g: g, b: b, a: 1)) }
        cb("k")  { sc, i in let k = popNum(sc), y = popNum(sc), m = popNum(sc), c = popNum(sc); scanState(i).setFill(pdfCMYK(c, m, y, k)) }
        cb("K")  { sc, i in let k = popNum(sc), y = popNum(sc), m = popNum(sc), c = popNum(sc); scanState(i).setStroke(pdfCMYK(c, m, y, k)) }
        cb("sc")  { sc, i in setComponents(sc, i, stroke: false) }
        cb("scn") { sc, i in setComponents(sc, i, stroke: false) }
        cb("SC")  { sc, i in setComponents(sc, i, stroke: true) }
        cb("SCN") { sc, i in setComponents(sc, i, stroke: true) }

        // Gradients / shadings we can't yet reconstruct → rasterize the page.
        cb("sh") { _, i in scanState(i).markRaster() }

        // Text
        cb("BT") { _, i in scanState(i).beginText() }
        cb("ET") { _, _ in }
        cb("Td") { sc, i in let ty = popNum(sc), tx = popNum(sc); scanState(i).textMove(tx, ty, setLeading: false) }
        cb("TD") { sc, i in let ty = popNum(sc), tx = popNum(sc); scanState(i).textMove(tx, ty, setLeading: true) }
        cb("Tm") { sc, i in
            let f = popNum(sc), e = popNum(sc), d = popNum(sc), c = popNum(sc), b = popNum(sc), a = popNum(sc)
            scanState(i).setTextMatrix(CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f))
        }
        cb("T*") { _, i in scanState(i).textNextLine() }
        cb("TL") { sc, i in scanState(i).setLeading(popNum(sc)) }
        cb("Tf") { sc, i in
            let size = popNum(sc)
            var nameP: UnsafePointer<Int8>?
            CGPDFScannerPopName(sc, &nameP)
            let raw = nameP.map { String(cString: $0) } ?? ""
            let s = scanState(i)
            let f = s.resolveFont(raw, scanner: sc)
            s.setFont(f.name, size, reliable: f.reliable)
        }
        cb("Tj") { sc, i in
            var str: CGPDFStringRef?
            guard CGPDFScannerPopString(sc, &str), let str else { return }
            if let cf = CGPDFStringCopyTextString(str) { scanState(i).showText(cf as String) }
            else { scanState(i).markRaster() }   // undecodable → page rasterizes
        }
        cb("'") { sc, i in
            let s = scanState(i); s.textNextLine()
            var str: CGPDFStringRef?
            guard CGPDFScannerPopString(sc, &str), let str else { return }
            if let cf = CGPDFStringCopyTextString(str) { s.showText(cf as String) } else { s.markRaster() }
        }
        cb("\"") { sc, i in
            var str: CGPDFStringRef?
            guard CGPDFScannerPopString(sc, &str), let str else { return }
            let s = scanState(i); s.textNextLine()
            if let cf = CGPDFStringCopyTextString(str) { s.showText(cf as String) } else { s.markRaster() }
        }
        cb("TJ") { sc, i in
            var arr: CGPDFArrayRef?
            guard CGPDFScannerPopArray(sc, &arr), let arr else { return }
            let s = scanState(i)
            var text = ""
            for k in 0..<CGPDFArrayGetCount(arr) {
                var str: CGPDFStringRef?
                if CGPDFArrayGetString(arr, k, &str), let str {
                    if let cf = CGPDFStringCopyTextString(str) { text += cf as String }
                    else { s.markRaster() }
                } else {
                    var nn: CGPDFReal = 0
                    if CGPDFArrayGetNumber(arr, k, &nn), nn < -200 { text += " " }   // big neg kern ≈ space
                }
            }
            s.showText(text)
        }

        // XObjects: recurse into forms, rasterize on images.
        cb("Do") { sc, i in
            var nameP: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(sc, &nameP), let nameP else { return }
            let cs = CGPDFScannerGetContentStream(sc)
            let name = String(cString: nameP)
            guard let obj = CGPDFContentStreamGetResource(cs, "XObject", name) else { return }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(obj, .stream, &stream), let stream else { return }
            var sub = ""
            if let dict = CGPDFStreamGetDictionary(stream) {
                var subP: UnsafePointer<Int8>?
                if CGPDFDictionaryGetName(dict, "Subtype", &subP), let subP { sub = String(cString: subP) }
            }
            let s = scanState(i)
            if sub == "Image" { s.markRaster() }
            else if sub == "Form" { s.runForm(stream, parent: cs, scannerInfo: i!) }
        }

        return t
    }()

    /// Exposed for the `v` (implicit first control point) operator.
    var currentUserPoint: CGPoint { currentUser }
}

// MARK: - File-scope helpers for the @convention(c) operator callbacks
//
// These are top-level (not nested) so the C callbacks can reference them without
// capturing context. `scanState` recovers the scanner state from the info ptr.

private nonisolated func scanState(_ info: UnsafeMutableRawPointer?) -> PageScan {
    Unmanaged<PageScan>.fromOpaque(info!).takeUnretainedValue()
}

private nonisolated func popNum(_ sc: CGPDFScannerRef) -> CGFloat {
    var v: CGPDFReal = 0
    CGPDFScannerPopNumber(sc, &v)
    return v
}

private nonisolated func pdfGray(_ v: CGFloat) -> RGBAColor { RGBAColor(r: v, g: v, b: v, a: 1) }

private nonisolated func pdfCMYK(_ c: CGFloat, _ m: CGFloat, _ y: CGFloat, _ k: CGFloat) -> RGBAColor {
    RGBAColor(r: (1 - c) * (1 - k), g: (1 - m) * (1 - k), b: (1 - y) * (1 - k), a: 1)
}

/// sc/scn/SC/SCN: a leading name operand means a Pattern (tiling/shading) — we
/// can't reconstruct those yet, so rasterize the page. Otherwise interpret the
/// 1/3/4 numeric components as gray/RGB/CMYK.
private nonisolated func setComponents(_ sc: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?, stroke: Bool) {
    let s = scanState(info)
    var nameP: UnsafePointer<Int8>?
    if CGPDFScannerPopName(sc, &nameP) { s.markRaster(); return }   // pattern fill
    var comps: [CGFloat] = []
    var v: CGPDFReal = 0
    while comps.count < 4 && CGPDFScannerPopNumber(sc, &v) { comps.append(v) }
    comps.reverse()
    let color: RGBAColor
    switch comps.count {
    case 1: color = pdfGray(comps[0])
    case 3: color = RGBAColor(r: comps[0], g: comps[1], b: comps[2], a: 1)
    case 4: color = pdfCMYK(comps[0], comps[1], comps[2], comps[3])
    default: return
    }
    if stroke { s.setStroke(color) } else { s.setFill(color) }
}
