//
//  Typography.swift
//  EXP [design]
//
//  Rich-text bridging between the model (`TextContent` = styled runs) and AppKit's
//  NSAttributedString, used for drawing, measuring, editing, and export. Also the
//  installed-font catalog for the typeface picker.
//

import AppKit
import CoreText

/// One glyph's outline from "convert text to shapes": its character (for the
/// layer name), color, tight ink box in text-local space, and contours relative
/// to that box.
struct GlyphOutline {
    var char: String
    var color: RGBAColor
    var boxInText: CGRect
    var localContours: [[PathPoint]]
}

extension TextAlign {
    var nsAlignment: NSTextAlignment {
        switch self { case .left: return .left; case .center: return .center; case .right: return .right }
    }
}

extension RGBAColor {
    init(ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        self.init(r: Double(c.redComponent), g: Double(c.greenComponent),
                  b: Double(c.blueComponent), a: Double(c.alphaComponent))
    }
}

extension TextRun {
    /// The face for this run (system font when unset/unknown). System-font
    /// variants (".AppleSystemUIFontBold", etc.) don't reload via NSFont(name:),
    /// so we rebuild their bold/italic from the name as a fallback.
    func nsFont(scale: CGFloat = 1) -> NSFont {
        let size = max(1, fontSize * scale)
        if fontName.isEmpty { return .systemFont(ofSize: size) }
        if let f = NSFont(name: fontName, size: size) { return f }
        var f = NSFont.systemFont(ofSize: size)
        let lower = fontName.lowercased()
        let fm = NSFontManager.shared
        if lower.contains("bold") { f = fm.convert(f, toHaveTrait: .boldFontMask) }
        if lower.contains("italic") || lower.contains("oblique") { f = fm.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }
    var familyName: String {
        if fontName.isEmpty { return "System" }
        if FontCatalog.isSystemMonospaced(fontName) { return FontCatalog.systemMonospacedFamily }
        return NSFont(name: fontName, size: 12)?.familyName ?? fontName
    }
}

extension TextContent {
    /// Family name for the inspector (uniform across runs, or "Mixed").
    var familyName: String {
        guard let fn = uniformFontName else { return "Mixed" }
        if FontCatalog.isSystemMonospaced(fn) { return FontCatalog.systemMonospacedFamily }
        return fn.isEmpty ? "System" : (NSFont(name: fn, size: 12)?.familyName ?? fn)
    }

    /// Build the NSAttributedString for drawing/editing. `scale` multiplies font
    /// sizes (the on-canvas editor renders at zoom).
    /// The paragraph style (alignment + line height) for this text at `scale`.
    func paragraphStyle(scale: CGFloat = 1) -> NSParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.alignment = align.nsAlignment
        switch lineHeightUnit {
        case .auto:
            // Use explicit lineHeightMultiple of 0 to ensure consistent behavior
            // across editing and non-editing states. 0 means "use the font's default"
            // but prevents TextKit from applying its own adjustments.
            para.lineHeightMultiple = 0
        case .multiple:
            para.lineHeightMultiple = lineHeight       // unitless, scale-invariant
        case .px:
            let h = lineHeight * scale
            para.minimumLineHeight = h; para.maximumLineHeight = h
        case .em:
            let h = lineHeight * firstRun.fontSize * scale
            para.minimumLineHeight = h; para.maximumLineHeight = h
        }
        return para
    }

    /// Per-run display strings with the non-destructive `textCase` applied. For
    /// `sentence` the capitalize-next state is carried across runs so a sentence
    /// that spans styled spans still reads correctly.
    func displayStrings() -> [String] {
        guard textCase != .none else { return runs.map(\.string) }
        guard textCase == .sentence else { return runs.map { textCase.apply($0.string) } }
        var out: [String] = []
        var capNext = true
        for run in runs {
            var s = ""
            for ch in run.string {
                if capNext, ch.isLetter {
                    s += String(ch).localizedUppercase; capNext = false
                } else {
                    s.append(ch)
                    if ch == "." || ch == "!" || ch == "?" || ch == "\n" { capNext = true }
                }
            }
            out.append(s)
        }
        return out
    }

    /// Build the attributed string for drawing/measuring (`applyCase: true`) or for
    /// the inline editor (`applyCase: false` — the editor must show the *original*
    /// characters so casing stays non-destructive).
    func attributedString(scale: CGFloat = 1, applyCase: Bool = true) -> NSAttributedString {
        let para = paragraphStyle(scale: scale)
        let strings = applyCase ? displayStrings() : runs.map(\.string)

        let out = NSMutableAttributedString()
        for (i, run) in runs.enumerated() {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: run.nsFont(scale: scale),
                .foregroundColor: PaintRender.nsColor(run.color),
                .paragraphStyle: para
            ]
            if run.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if tracking != 0 { attrs[.kern] = tracking * scale }
            out.append(NSAttributedString(string: strings[i], attributes: attrs))
        }
        return out
    }

    /// Rebuild runs from an edited NSAttributedString (dividing sizes by `scale`).
    init(attributed: NSAttributedString, scale: CGFloat = 1,
         align: TextAlign, lineHeight: CGFloat, lineHeightUnit: LineHeightUnit,
         tracking: CGFloat, box: TextBox, textCase: TextCase = .none) {
        var newRuns: [TextRun] = []
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            let sub = (attributed.string as NSString).substring(with: range)
            guard !sub.isEmpty else { return }
            let font = (attrs[.font] as? NSFont) ?? .systemFont(ofSize: 16)
            let size = font.pointSize / max(scale, 0.0001)
            // System font's name is private and won't round-trip — store "".
            let isSystem = font.fontName == NSFont.systemFont(ofSize: font.pointSize).fontName
            let psName = isSystem ? "" : font.fontName
            let color = (attrs[.foregroundColor] as? NSColor).map { RGBAColor(ns: $0) } ?? .black
            let underline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            newRuns.append(TextRun(string: sub, fontName: psName, fontSize: size, color: color, underline: underline))
        }
        self.init(runs: newRuns.isEmpty ? [TextRun(string: attributed.string)] : newRuns,
                  align: align, lineHeight: lineHeight, lineHeightUnit: lineHeightUnit,
                  tracking: tracking, box: box, textCase: textCase)
    }

    /// Size to fit the same attributed text TextKit draws on canvas. With
    /// `maxWidth` (a fixed/paragraph box) the width is kept and the text wraps,
    /// growing only in height; otherwise it hugs a single line. Do not impose an
    /// extra `1.3 × font size` floor or bottom safety pad here: those made the
    /// stored box visibly taller than TextKit's real line box and caused false
    /// overflow badges when a tightly authored/imported frame still drew every
    /// character.
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize {
        let a = attributedString()
        let s = a.length == 0 ? NSAttributedString(string: "Text", attributes: [.font: firstRun.nsFont()]) : a
        if let w = maxWidth, w > 1 {
            let bounds = s.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading])
            return CGSize(width: w, height: max(1, ceil(bounds.height)))
        }
        let m = s.size()
        return CGSize(width: max(20, ceil(m.width) + 2),
                      height: max(1, ceil(m.height)))
    }

    /// Re-measure honoring the box mode: fixed/paragraph keeps `currentWidth`.
    func measuredSize(boxWidth currentWidth: CGFloat) -> CGSize {
        box == .fixed ? measuredSize(maxWidth: currentWidth) : measuredSize()
    }

    // MARK: Convert to shapes (glyph outlines)

    /// Outline the laid-out text into ONE entry PER GLYPH, so converting a word
    /// yields a shape per letter (auto-grouped by the caller). Each glyph carries a
    /// TIGHT bounding box (ink only — no ascender/descender padding) in the text
    /// box's LOCAL space (y-down, origin top-left), plus its contours expressed
    /// relative to that box. Honors the non-destructive case.
    func outlineGlyphs(in size: CGSize) -> [GlyphOutline] {
        let attr = attributedString(scale: 1)
        guard attr.length > 0, size.width > 0, size.height > 0 else { return [] }
        let nsString = attr.string as NSString

        // CoreText's CTFramesetterCreateFrame returns ZERO lines if the path isn't
        // tall enough for even one line at THIS font's natural line height — which
        // can differ a lot from the box's stored frame height (a manually resized
        // box, or simply a font with a taller em-square than the box assumes). That
        // silently killed "Convert to Outlines" for some fonts/box sizes. TextKit's
        // own `measuredSize` estimate isn't a safe floor either — it can UNDERSHOOT
        // CoreText's real per-line requirement for fonts with unusual ascent/descent
        // (TextKit and CoreText measure independently and don't always agree), which
        // is why doubling the box only fixed it for some fonts and not others. So
        // floor the layout height generously: double the larger of the box's stored
        // height and the TextKit measurement, plus a flat pad. CoreText always starts
        // the first line at the TOP of the rect, so any extra height we add only pads
        // unused space below — it never shifts the glyphs we keep, no matter how much
        // headroom we give it.
        let measuredFloor = max(size.height, measuredSize(boxWidth: size.width).height)
        let layoutSize = CGSize(width: size.width, height: measuredFloor * 2 + 400)

        let rectPath = CGPath(rect: CGRect(origin: .zero, size: layoutSize), transform: nil)
        let setter = CTFramesetterCreateWithAttributedString(attr)
        let ctFrame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), rectPath, nil)
        guard let lines = CTFrameGetLines(ctFrame) as? [CTLine] else { return [] }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &origins)

        // CT lays out y-up from the bottom of the rect; flip into our y-down local.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: layoutSize.height)
        var result: [GlyphOutline] = []

        for (li, line) in lines.enumerated() {
            let lineOrigin = origins[li]
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
            for run in runs {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                guard let fontRef = attrs[kCTFontAttributeName as String] else { continue }
                let font = fontRef as! CTFont
                let ns = (attrs[NSAttributedString.Key.foregroundColor.rawValue] as? NSColor) ?? .black
                let color = RGBAColor(ns: ns)

                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)

                for gi in 0..<count {
                    guard let gp = CTFontCreatePathForGlyph(font, glyphs[gi], nil) else { continue }
                    // Place the glyph at its line position, then flip to y-down.
                    let placed = CGMutablePath()
                    placed.addPath(gp, transform: CGAffineTransform(
                        translationX: lineOrigin.x + positions[gi].x,
                        y: lineOrigin.y + positions[gi].y))
                    let flipped = CGMutablePath()
                    flipped.addPath(placed, transform: flip)
                    let box = flipped.boundingBoxOfPath
                    guard box.width > 0, box.height > 0 else { continue }   // skip spaces
                    // Re-express contours relative to the glyph's tight box.
                    let local = CGMutablePath()
                    local.addPath(flipped, transform: CGAffineTransform(translationX: -box.minX, y: -box.minY))
                    let contours = TextContent.contours(from: local)
                    guard !contours.isEmpty else { continue }
                    let idx = indices[gi]
                    let ch = (idx >= 0 && idx < nsString.length)
                        ? nsString.substring(with: NSRange(location: idx, length: 1)) : ""
                    result.append(GlyphOutline(char: ch, color: color, boxInText: box, localContours: contours))
                }
            }
        }
        return result
    }

    /// Convert a CGPath into our closed `[PathPoint]` contours (split on each
    /// moveTo). Quadratics are promoted to cubics so the model stays bezier-cubic.
    static func contours(from cg: CGPath) -> [[PathPoint]] {
        var out: [[PathPoint]] = []
        var cur: [PathPoint] = []
        cg.applyWithBlock { ePtr in
            let e = ePtr.pointee
            switch e.type {
            case .moveToPoint:
                if !cur.isEmpty { out.append(cur); cur = [] }
                cur.append(PathPoint(point: e.points[0]))
            case .addLineToPoint:
                cur.append(PathPoint(point: e.points[0]))
            case .addQuadCurveToPoint:
                let qc = e.points[0], end = e.points[1]
                if var last = cur.last {
                    last.controlOut = CGPoint(x: last.point.x + 2.0/3 * (qc.x - last.point.x),
                                              y: last.point.y + 2.0/3 * (qc.y - last.point.y))
                    cur[cur.count - 1] = last
                }
                let c2 = CGPoint(x: end.x + 2.0/3 * (qc.x - end.x), y: end.y + 2.0/3 * (qc.y - end.y))
                cur.append(PathPoint(point: end, controlIn: c2))
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], end = e.points[2]
                if var last = cur.last { last.controlOut = c1; cur[cur.count - 1] = last }
                cur.append(PathPoint(point: end, controlIn: c2))
            case .closeSubpath:
                if !cur.isEmpty { out.append(cur); cur = [] }
            @unknown default:
                break
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

/// The installed-font catalog, cached.
enum FontCatalog {
    static let systemMonospacedFamily = "System Monospaced"
    static let systemMonospacedRegular = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName

    struct Face: Identifiable, Hashable {
        let postScriptName: String
        let faceName: String
        var id: String { postScriptName }
    }

    static let families: [String] = ([systemMonospacedFamily] + NSFontManager.shared.availableFontFamilies)
        .filter { !$0.hasPrefix(".") }
        .sorted()

    static func faces(of family: String) -> [Face] {
        if family == systemMonospacedFamily {
            return [
                Face(postScriptName: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName,
                     faceName: "Regular"),
                Face(postScriptName: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold).fontName,
                     faceName: "Semibold"),
                Face(postScriptName: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold).fontName,
                     faceName: "Bold")
            ]
        }
        return (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member -> Face? in
            guard member.count >= 2,
                  let ps = member[0] as? String,
                  let face = member[1] as? String else { return nil }
            return Face(postScriptName: ps, faceName: face)
        }
    }

    static func defaultFace(of family: String) -> String? {
        if family == systemMonospacedFamily { return systemMonospacedRegular }
        let f = faces(of: family)
        return (f.first { $0.faceName == "Regular" } ?? f.first)?.postScriptName
    }

    static func isSystemMonospaced(_ postScriptName: String) -> Bool {
        postScriptName.hasPrefix(".AppleSystemUIFontMonospaced")
    }
}
