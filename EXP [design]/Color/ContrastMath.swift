//
//  ContrastMath.swift
//  EXP [design]
//
//  WCAG 2.x contrast scoring. Pure math over the model's sRGB `RGBAColor`, kept
//  beside `ColorMath` and deliberately UI-free so it can be unit-tested and used
//  by the picker, the inspector, and (later) the Design Language panel alike.
//
//  WCAG 2.x is the honest, settled standard, so it drives pass/fail here. APCA is
//  a different model still tied to the unsettled WCAG 3 draft; if it earns a place
//  it belongs as an *advisory* readout, never as the primary judgment (Phase 18c).
//
//  Contrast is only meaningful between two OPAQUE colors, so any alpha in the
//  foreground (or the background) is flattened first — a translucent color scores
//  as what the eye actually sees once it's composited over the layer behind it.
//

import Foundation

/// A category of contrast requirement, with its WCAG 2.x AA/AAA thresholds.
/// Large text = >= 18pt regular or >= 14pt bold. "UI / graphics" covers non-text
/// components and meaningful graphical objects (WCAG 1.4.11), which have a single
/// 3:1 bar rather than separate AA/AAA levels.
enum ContrastUse: String, CaseIterable, Identifiable, Sendable {
    case normalText = "Normal text"
    case largeText  = "Large text"
    case uiGraphics = "UI / graphics"

    var id: String { rawValue }

    /// Minimum ratio to reach AA for this use.
    var aa: Double {
        switch self {
        case .normalText: return 4.5
        case .largeText:  return 3.0
        case .uiGraphics: return 3.0
        }
    }

    /// Minimum ratio to reach AAA. UI/graphics has no defined AAA level in WCAG
    /// 2.x, so we return its AA bar (nothing higher to claim).
    var aaa: Double {
        switch self {
        case .normalText: return 7.0
        case .largeText:  return 4.5
        case .uiGraphics: return 3.0
        }
    }
}

/// The pass level a ratio reaches for a given use.
enum ContrastLevel: String, Sendable {
    case fail = "Fail"
    case aa   = "AA"
    case aaa  = "AAA"
}

/// A full contrast readout for one foreground/background pair.
struct ContrastReport: Sendable {
    /// The WCAG contrast ratio (1...21), already alpha-flattened.
    var ratio: Double

    /// The opaque colors actually scored (foreground composited over background,
    /// background composited over `base`). Handy for showing the "real" swatches.
    var flattenedForeground: RGBAColor
    var flattenedBackground: RGBAColor

    func level(for use: ContrastUse) -> ContrastLevel {
        if ratio >= use.aaa { return .aaa }
        if ratio >= use.aa  { return .aa }
        return .fail
    }

    func passes(_ use: ContrastUse, atLeast level: ContrastLevel = .aa) -> Bool {
        switch level {
        case .fail: return true
        case .aa:   return ratio >= use.aa
        case .aaa:  return ratio >= use.aaa
        }
    }

    /// e.g. "4.63:1" — the conventional way designers read contrast.
    var ratioLabel: String { String(format: "%.2f:1", ratio) }
}

enum ContrastMath {

    /// The base an otherwise-translucent *background* is composited over before
    /// scoring. White is the honest default for a design surface; callers with a
    /// real page/artboard color can pass their own.
    static let defaultBase = RGBAColor.white

    // MARK: Relative luminance (WCAG 2.x)

    /// WCAG relative luminance of an OPAQUE color. Alpha is ignored here on
    /// purpose — flatten first with `flatten(_:over:)` if the color is translucent.
    static func relativeLuminance(_ c: RGBAColor) -> Double {
        let r = ColorMath.toLinear(ColorMath.clamp01(c.r))
        let g = ColorMath.toLinear(ColorMath.clamp01(c.g))
        let b = ColorMath.toLinear(ColorMath.clamp01(c.b))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    // MARK: Alpha flattening (straight "over" compositing)

    /// Composite `top` over `bottom` (straight alpha). If `bottom` still has
    /// alpha, the result keeps `bottom`'s alpha — callers flatten again over a
    /// solid base.
    static func flatten(_ top: RGBAColor, over bottom: RGBAColor) -> RGBAColor {
        let ta = ColorMath.clamp01(top.a)
        if ta >= 1 { return RGBAColor(r: top.r, g: top.g, b: top.b, a: 1) }
        let ba = ColorMath.clamp01(bottom.a)
        let outA = ta + ba * (1 - ta)
        guard outA > 0 else { return RGBAColor(r: 0, g: 0, b: 0, a: 0) }
        func mix(_ t: Double, _ b: Double) -> Double {
            (t * ta + b * ba * (1 - ta)) / outA
        }
        return RGBAColor(r: mix(top.r, bottom.r),
                         g: mix(top.g, bottom.g),
                         b: mix(top.b, bottom.b),
                         a: outA)
    }

    /// Fully opaque version of a color: flatten it over `base` (white by default).
    static func opaque(_ c: RGBAColor, over base: RGBAColor = defaultBase) -> RGBAColor {
        var b = base
        b.a = 1                       // the base must be solid to end the stack
        let flat = flatten(c, over: b)
        return RGBAColor(r: flat.r, g: flat.g, b: flat.b, a: 1)
    }

    // MARK: Contrast ratio + report

    /// Raw WCAG contrast ratio between two already-opaque colors (1...21).
    static func ratio(opaque a: RGBAColor, _ b: RGBAColor) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        let hi = max(la, lb), lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Full report for a foreground over a background. Translucent inputs are
    /// flattened first (foreground over background, background over `base`), so
    /// the ratio reflects what a viewer actually sees.
    static func report(foreground: RGBAColor,
                       background: RGBAColor,
                       base: RGBAColor = defaultBase) -> ContrastReport {
        let bg = opaque(background, over: base)
        let fg = opaque(flatten(foreground, over: bg), over: bg)
        return ContrastReport(ratio: ratio(opaque: fg, bg),
                              flattenedForeground: fg,
                              flattenedBackground: bg)
    }

    // MARK: OKLCH-based repair suggestions (advisory — never silent)

    /// Suggest a foreground color that reaches `target` contrast against
    /// `background`, moving only OKLCH **lightness** (preserving hue and chroma as
    /// far as the gamut allows). Returns nil if no lightness reaches the target.
    ///
    /// This is a *suggestion*: callers present it for the user to accept, they do
    /// not apply it silently (Phase 18c).
    static func suggestForeground(preservingHueChroma foreground: RGBAColor,
                                  against background: RGBAColor,
                                  target: Double,
                                  base: RGBAColor = defaultBase) -> RGBAColor? {
        let bg = opaque(background, over: base)
        let (_, c, h) = ColorMath.rgbToOKLCH(foreground.r, foreground.g, foreground.b)
        let bgLum = relativeLuminance(bg)

        func firstPassing(_ lightnesses: [Double]) -> RGBAColor? {
            for L in lightnesses {
                let (r, g, b) = ColorMath.oklchToRGB(L, c, h)
                let cand = RGBAColor(r: r, g: g, b: b, a: foreground.a)
                if ratio(opaque: opaque(cand, over: bg), bg) >= target { return cand }
            }
            return nil
        }
        let up   = stride(from: 0.0, through: 1.0, by: 0.01).map { $0 }
        let down = Array(up.reversed())
        // Dark background -> try light foregrounds first, and vice versa.
        let ordered = bgLum > 0.5 ? down : up
        return firstPassing(ordered)
    }
}
