//
//  PaletteProviders.swift
//  EXP [design]
//
//  Phase 18f — palette inspiration, local and offline first. A `PaletteProvider`
//  turns a seed color into a labeled set of candidate paints the user can add to
//  the document's design language. Everything here is pure and offline: OKLCH
//  ramps and hue harmonies computed with `ColorMath`, and accessible pairs scored
//  with `ContrastMath`. No network, no scraping — remote/service providers can
//  adopt the same protocol later behind honest source/license labels.
//

import Foundation

/// A named set of suggested paints, with a human-readable source + terms note so
/// provenance stays honest when entries are added to the library.
struct PaletteSuggestion: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var note: String
    var paints: [Paint]
}

/// Anything that can propose palettes from a seed. Local generators and (later)
/// remote services both conform, so the UI treats them uniformly.
protocol PaletteProvider {
    var name: String { get }
    /// Terms/attribution note surfaced in the UI (e.g. "Generated locally").
    var sourceNote: String { get }
    func suggestions(seed: RGBAColor) -> [PaletteSuggestion]
}

/// Local, offline generators. Grouped as static helpers plus a `LocalProvider`
/// that bundles them for the UI.
enum PaletteProviders {

    static let localNote = "Generated locally in EXP · free to use"

    // MARK: OKLCH ramp

    /// A perceptually-even lightness ramp through the seed's hue/chroma. OKLCH is
    /// used because equal lightness steps read as equal steps to the eye, unlike
    /// HSL. Out-of-gamut steps are clamped to sRGB (honestly, by the shared math).
    static func ramp(seed: RGBAColor, steps: Int = 9) -> PaletteSuggestion {
        let (_, c, h) = ColorMath.rgbToOKLCH(seed.r, seed.g, seed.b)
        let n = max(2, steps)
        var paints: [Paint] = []
        for i in 0..<n {
            let L = 0.15 + 0.80 * Double(i) / Double(n - 1)
            let (rgb, _) = ColorMath.oklchToRGBGamut(L, c, h)
            paints.append(.solid(RGBAColor(r: rgb.0, g: rgb.1, b: rgb.2, a: seed.a)))
        }
        return PaletteSuggestion(title: "OKLCH ramp", note: localNote, paints: paints)
    }

    // MARK: Hue harmonies (rotate hue in OKLCH, keep L + C)

    private static func rotated(_ seed: RGBAColor, by degrees: Double) -> Paint {
        let (L, c, h) = ColorMath.rgbToOKLCH(seed.r, seed.g, seed.b)
        let (rgb, _) = ColorMath.oklchToRGBGamut(L, c, (h + degrees).truncatingRemainder(dividingBy: 360))
        return .solid(RGBAColor(r: rgb.0, g: rgb.1, b: rgb.2, a: seed.a))
    }

    static func complementary(seed: RGBAColor) -> PaletteSuggestion {
        PaletteSuggestion(title: "Complementary", note: localNote,
                          paints: [.solid(seed), rotated(seed, by: 180)])
    }

    static func triadic(seed: RGBAColor) -> PaletteSuggestion {
        PaletteSuggestion(title: "Triadic", note: localNote,
                          paints: [.solid(seed), rotated(seed, by: 120), rotated(seed, by: 240)])
    }

    static func analogous(seed: RGBAColor) -> PaletteSuggestion {
        PaletteSuggestion(title: "Analogous", note: localNote,
                          paints: [rotated(seed, by: -30), .solid(seed), rotated(seed, by: 30)])
    }

    // MARK: Accessible pair

    /// The seed as a background plus a same-hue foreground nudged (in OKLCH
    /// lightness) until it clears WCAG AA for normal text. Falls back to whichever
    /// of black/white passes if the hue-preserving nudge can't reach it.
    static func accessiblePair(seed: RGBAColor) -> PaletteSuggestion {
        let target = ContrastUse.normalText.aa
        let fg: RGBAColor
        if let suggested = ContrastMath.suggestForeground(preservingHueChroma: seed,
                                                          against: seed, target: target) {
            fg = suggested
        } else {
            let onBlack = ContrastMath.report(foreground: .black, background: seed).ratio
            let onWhite = ContrastMath.report(foreground: .white, background: seed).ratio
            fg = onWhite >= onBlack ? .white : .black
        }
        let ratio = ContrastMath.report(foreground: fg, background: seed).ratioLabel
        return PaletteSuggestion(title: "Accessible pair",
                                 note: "Foreground on seed — \(ratio), WCAG AA · \(localNote)",
                                 paints: [.solid(seed), .solid(fg)])
    }

    // MARK: Bundle

    static func all(seed: RGBAColor) -> [PaletteSuggestion] {
        [ramp(seed: seed),
         complementary(seed: seed),
         analogous(seed: seed),
         triadic(seed: seed),
         accessiblePair(seed: seed)]
    }
}

/// The default local provider, bundling every offline generator.
struct LocalPaletteProvider: PaletteProvider {
    var name: String { "Local" }
    var sourceNote: String { PaletteProviders.localNote }
    func suggestions(seed: RGBAColor) -> [PaletteSuggestion] { PaletteProviders.all(seed: seed) }
}
