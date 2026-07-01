//
//  TextMetrics.swift
//  EXP [design]
//
//  Vertical font metrics + "text box trim" math (a.k.a. leading-trim, or CSS
//  `text-box-trim` / Figma "vertical trim"). The home for measuring interface
//  text from an OPTICAL box — cap height on top, alphabetic baseline on the
//  bottom — instead of the font's line box. The line box carries per-font
//  breathing room above the ascenders and below the descenders, plus half the
//  line's leading; padding measured from it looks larger than the number and
//  drifts between typefaces. Measured from the optical box, padding reads evenly.
//  The design-token system builds on this (see VISUAL-HANDOFF token notes).
//
//  Everything is in points at the font's own size (1 pt = 1 px @1x) and read
//  straight from Core Text — no magic numbers.
//

import AppKit
import CoreText

/// Raw vertical metrics for one font, all relative to the alphabetic baseline.
struct FontMetrics: Equatable {
    /// Above the baseline (positive), from the font's line metrics.
    var ascent: CGFloat
    /// Below the baseline (returned as a positive magnitude).
    var descent: CGFloat
    /// Recommended line gap (extra leading) between lines.
    var leading: CGFloat
    /// Baseline → top of a flat capital (the top of "H").
    var capHeight: CGFloat
    /// Baseline → top of the lowercase x.
    var xHeight: CGFloat
    var unitsPerEm: CGFloat
    var pointSize: CGFloat

    init(_ font: NSFont) {
        let ct = font as CTFont
        ascent     = CTFontGetAscent(ct)
        descent    = CTFontGetDescent(ct)
        leading    = CTFontGetLeading(ct)
        capHeight  = CTFontGetCapHeight(ct)
        xHeight    = CTFontGetXHeight(ct)
        unitsPerEm = CGFloat(CTFontGetUnitsPerEm(ct))
        pointSize  = CTFontGetSize(ct)
    }

    /// The font's natural line height (ascent + descent + leading) — what a
    /// layout engine uses per line when line-height is "auto".
    var lineHeight: CGFloat { ascent + descent + leading }
}

/// A vertical edge of the text box, mirroring CSS `text-box-edge`. Offsets are
/// relative to the baseline (above = positive).
enum TextBoxEdge: String, CaseIterable, Sendable {
    case ascent      // the font's ascender metric (line-box top)
    case cap         // cap height — recommended top for UI text
    case ex          // x-height — tight, all-lowercase
    case alphabetic  // the baseline — recommended bottom for UI text
    case descent     // the font's descender metric (line-box bottom)

    /// Height of this edge above the baseline for `m` (negative = below it).
    func offset(in m: FontMetrics) -> CGFloat {
        switch self {
        case .ascent:     return m.ascent
        case .cap:        return m.capHeight
        case .ex:         return m.xHeight
        case .alphabetic: return 0
        case .descent:    return -m.descent
        }
    }
}

/// How a line's extra leading is distributed around the glyphs when the line box
/// is taller than ascent+descent. CSS (and Figma's vertical trim) split it in
/// half; Core Text's default puts it all below the descent. The trim math needs
/// to know which, to place the baseline inside the box.
enum LeadingModel: Sendable { case splitHalf, below }

/// A pair of optical edges to trim the text box down to. `.uiDefault` is the
/// cap-height → baseline box you want for buttons, rows, and labels.
struct TextBoxTrim: Equatable, Sendable {
    var top: TextBoxEdge
    var bottom: TextBoxEdge

    static let uiDefault = TextBoxTrim(top: .cap, bottom: .alphabetic)
    static let none      = TextBoxTrim(top: .ascent, bottom: .descent)

    /// Insets to remove from a line box of height `lineBox` to reach this optical
    /// box: `top` off the top edge, `bottom` off the bottom edge. Subtract them
    /// when laying out, so padding is then measured from the optical edges.
    ///
    /// Pass the line height you actually render with (defaults to the font's
    /// natural line height) and the leading model your layout uses.
    func insets(_ m: FontMetrics,
                lineBox: CGFloat? = nil,
                leading: LeadingModel = .splitHalf) -> (top: CGFloat, bottom: CGFloat) {
        let box = lineBox ?? m.lineHeight
        let extra = box - (m.ascent + m.descent)         // leading actually applied
        let above: CGFloat = (leading == .splitHalf) ? extra / 2 : 0
        let baselineFromTop = m.ascent + above           // y of baseline from box top
        let topEdgeFromTop    = baselineFromTop - top.offset(in: m)
        let bottomEdgeFromTop = baselineFromTop - bottom.offset(in: m)
        return (top: max(0, topEdgeFromTop),
                bottom: max(0, box - bottomEdgeFromTop))
    }
}

extension FontMetrics {
    /// Tight ink bounds of `string` in this font, in a baseline-relative, y-up
    /// space (origin at the start of the baseline; baseline at y = 0). Use when
    /// you need the ACTUAL drawn extent — optical centring of a single glyph or an
    /// all-caps label — rather than the font-wide metrics above.
    static func inkBounds(of string: String, font: NSFont) -> CGRect {
        let attr = NSAttributedString(string: string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr)
        return CTLineGetImageBounds(line, nil)
    }
}
