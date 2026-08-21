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

    /// The line height this text ACTUALLY renders at, in points at scale 1,
    /// whatever unit it is authored in. `.auto` reports the font's natural line
    /// height, because that is what `.auto` draws — which is what makes switching
    /// off Auto keep the same appearance.
    var renderedLineHeightPoints: CGFloat {
        let font = firstRun.nsFont(scale: 1)
        let natural = NSLayoutManager().defaultLineHeight(for: font)
        switch lineHeightUnit {
        case .auto:     return natural
        case .multiple: return lineHeight * natural
        case .px:       return lineHeight
        case .em:       return lineHeight * firstRun.fontSize
        }
    }

    /// The number that expresses `points` of line height in `unit`, for THIS
    /// text's first run — so the unit selector can convert instead of
    /// reinterpreting. A 64pt line box on 40pt type is about 1.4× or 1.6em; read
    /// as "64" of either it becomes an absurd line box.
    ///
    /// `.multiple` divides by the font's NATURAL line height, not by the font
    /// size, because that is what `NSParagraphStyle.lineHeightMultiple` multiplies.
    /// (CSS's unitless `line-height` multiplies the font size instead — a real
    /// difference, and this app lays out through TextKit, so TextKit's definition
    /// is the one that has to be inverted here.) `.auto` has no number of its own,
    /// so the stored one is returned untouched and survives a round trip.
    ///
    /// Uses the same `NSLayoutManager.defaultLineHeight(for:)` the fixed-line-height
    /// leading correction above uses, so the two cannot disagree about "natural".
    func lineHeightValue(for points: CGFloat, in unit: LineHeightUnit) -> CGFloat {
        let font = firstRun.nsFont(scale: 1)
        let natural = NSLayoutManager().defaultLineHeight(for: font)
        switch unit {
        case .auto:     return lineHeight
        case .multiple: return natural > 0 ? points / natural : lineHeight
        case .px:       return points
        case .em:       return firstRun.fontSize > 0 ? points / firstRun.fontSize : lineHeight
        }
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
    func attributedString(scale: CGFloat = 1, applyCase: Bool = true,
                          centerFixedLineHeightLeading: Bool = true) -> NSAttributedString {
        let para = paragraphStyle(scale: scale)
        let strings = applyCase ? displayStrings() : runs.map(\.string)

        let out = NSMutableAttributedString()
        for (i, run) in runs.enumerated() {
            let font = run.nsFont(scale: scale)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: PaintRender.nsColor(run.color),
                .paragraphStyle: para
            ]
            // CSS distributes the extra space in a fixed line-height equally
            // above and below the font box. TextKit instead leaves the extra
            // space above its bottom-anchored baseline, which makes a truthful
            // imported `26px` line box paint several points too low. Raise the
            // glyphs by half that difference while keeping the stored line box,
            // selection frame, and exported CSS value unchanged.
            if centerFixedLineHeightLeading && centersFixedLineHeightLeading {
                let targetLineHeight: CGFloat?
                switch lineHeightUnit {
                case .px: targetLineHeight = lineHeight * scale
                case .em: targetLineHeight = lineHeight * run.fontSize * scale
                case .auto, .multiple: targetLineHeight = nil
                }
                if let targetLineHeight {
                    let naturalLineHeight = NSLayoutManager().defaultLineHeight(for: font)
                    let offset = max(0, (targetLineHeight - naturalLineHeight) / 2)
                    if offset > 0.001 { attrs[.baselineOffset] = offset }
                }
            }
            if run.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if tracking != 0 { attrs[.kern] = tracking * scale }
            out.append(NSAttributedString(string: strings[i], attributes: attrs))
        }
        return out
    }

    /// Rebuild runs from an edited NSAttributedString (dividing sizes by `scale`).
    init(attributed: NSAttributedString, scale: CGFloat = 1,
         align: TextAlign, lineHeight: CGFloat, lineHeightUnit: LineHeightUnit,
         tracking: CGFloat, box: TextBox, textCase: TextCase = .none,
         centersFixedLineHeightLeading: Bool = true) {
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
                  tracking: tracking, box: box, textCase: textCase,
                  centersFixedLineHeightLeading: centersFixedLineHeightLeading)
    }

    /// Size to fit the same attributed text TextKit draws on canvas. With
    /// `maxWidth` (a fixed/paragraph box) the width is kept and the text wraps,
    /// growing only in height; otherwise it hugs a single line. Do not impose an
    /// extra `1.3 × font size` floor or bottom safety pad here: those made the
    /// stored box visibly taller than TextKit's real line box and caused false
    /// overflow badges when a tightly authored/imported frame still drew every
    /// character.
    func measuredSize(maxWidth: CGFloat? = nil) -> CGSize {
        // Baseline correction is paint-only. Measuring the unshifted fixed line
        // box keeps its authored px/em height instead of shrinking to glyph ink.
        let a = attributedString(centerFixedLineHeightLeading: false)
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

    /// AppKit's documented family classes. These are intentionally broad: font
    /// metadata is incomplete in the wild, so an explicit Other bucket is more
    /// truthful than guessing from a family name and silently hiding misses.
    enum Category: String, CaseIterable {
        case sansSerif, serif, monospaced, handwriting, display, symbol, other
    }

    struct Face: Identifiable, Hashable {
        let postScriptName: String
        let faceName: String
        var id: String { postScriptName }
    }

    static let families: [String] = Set([systemMonospacedFamily] + NSFontManager.shared.availableFontFamilies)
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

    static func category(for family: String) -> Category {
        if family.isEmpty { return .sansSerif }
        if family == systemMonospacedFamily { return .monospaced }
        return categoriesByFamily[family] ?? .other
    }

    /// Font descriptors are stable for the process lifetime. Cache the catalog's
    /// classifications once instead of reopening hundreds of descriptors whenever
    /// SwiftUI recomputes a filtered list.
    private static let categoriesByFamily: [String: Category] = {
        var result: [String: Category] = [:]
        for family in families where family != systemMonospacedFamily {
            result[family] = uncachedCategory(for: family)
        }
        return result
    }()

    private static func uncachedCategory(for family: String) -> Category {
        guard let face = defaultFace(of: family),
              let font = NSFont(name: face, size: 12) else { return .other }
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.monoSpace) { return .monospaced }

        switch traits.intersection(.classMask) {
        case .classOldStyleSerifs, .classTransitionalSerifs, .classModernSerifs,
             .classClarendonSerifs, .classSlabSerifs, .classFreeformSerifs:
            return .serif
        case .classSansSerif:
            return .sansSerif
        case .classScripts:
            return .handwriting
        case .classOrnamentals:
            return .display
        case .classSymbolic:
            return .symbol
        default:
            return .other
        }
    }
}

extension Document {
    /// Installed families actually referenced by this document. This walks every
    /// canvas page, reusable component source, component-state/instance typography
    /// override, and saved type style. The picker still filters ONE installed-font
    /// catalog; unavailable document fonts are therefore not presented as choices.
    var usedFontFamilies: Set<String> {
        let installed = Set(FontCatalog.families)
        var result: Set<String> = []

        func addFontName(_ fontName: String) {
            if fontName.isEmpty {
                result.insert("")
            } else if FontCatalog.isSystemMonospaced(fontName) {
                result.insert(FontCatalog.systemMonospacedFamily)
            } else if installed.contains(fontName) {
                result.insert(fontName)
            } else if let family = NSFont(name: fontName, size: 12)?.familyName,
                      installed.contains(family) {
                result.insert(family)
            }
        }

        func addOverride(_ value: InstanceOverride.Value) {
            guard case .textStyle(let style) = value,
                  let fontName = style.fontName else { return }
            addFontName(fontName)
        }

        func visit(_ nodes: [Node]) {
            for node in nodes {
                switch node.content {
                case .text(let text):
                    text.runs.forEach { addFontName($0.fontName) }
                case .group(let children):
                    visit(children)
                case .instance(let instance):
                    instance.overrides.forEach { addOverride($0.value) }
                    instance.nestedOverrides.forEach { addOverride($0.value) }
                default:
                    break
                }
            }
        }

        pages.forEach { visit($0.nodes) }
        for source in sources {
            visit(source.children)
            source.states.flatMap(\.overrides).forEach { addOverride($0.value) }
        }
        designLanguage.typeStyles.forEach { addFontName($0.fontName) }
        return result
    }
}
