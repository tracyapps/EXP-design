//
//  DesignTokens.swift
//  EXP [design]
//
//  Phase 17a — the design-system SEAM. A single Swift source of truth for the
//  app CHROME's colours, type, spacing/radii/stroke, motion, and glass values.
//  Ported verbatim from `design/EXP [design] Design System/tokens/*.css` (the
//  finalized visual language; that CSS/JSON is the value authority).
//
//  Scope: CHROME ONLY. The canvas is intentionally undesigned — its tokens live
//  under `EXPColor.Canvas` and mirror the isolated `--canvas-*` CSS group; change
//  them sparingly and on purpose. This file is app-target only (it is NOT
//  referenced by the shared model/renderer, so it must NOT join EXPThumbnail).
//
//  Appearance: every colour token resolves light/dark automatically via a dynamic
//  NSColor provider (the Swift analogue of the `.exp-dark` / light CSS scopes),
//  so one token serves both. Dark is the design home; light is the faithful
//  mirror. Reduce-Transparency / Increase-Contrast are honoured by AppKit's own
//  resolution plus the glass fallbacks (built in 17b).
//
//  ⚠ Two things to verify on-device (flagged, not assumed):
//   1. SF Compact is now BUNDLED + registered at launch (UI/FontRegistration.swift),
//      so layer names render condensed on every Mac. `EXPType.layerFont` still
//      falls back to the system font defensively if registration ever fails.
//   2. Live accent-override refresh — `EXPColor.accent` reads the override from
//      UserDefaults on each access, so it updates on the next SwiftUI render.
//      The Settings UI (17i) will post a change so live windows refresh promptly.
//

import SwiftUI
import AppKit

// MARK: - Colour ============================================================

/// Chrome colour tokens. Canonical builders return `NSColor` (so AppKit surfaces
/// — separators, NSTextView, the canvas — can share them); SwiftUI reads the
/// `Color` mirrors. Values: `tokens/colors.css` (`:root,.exp-dark` = dark, the
/// `@media`/`.exp-light` block = light).
enum EXPColor {

    // ---- builders ---------------------------------------------------------

    /// Normalised sRGB components from a 0xRRGGBB hex + alpha. Pure & Sendable
    /// (only CGFloats cross into the dynamic provider).
    private static func comps(_ hex: UInt32, _ a: CGFloat) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        (CGFloat((hex >> 16) & 0xFF) / 255,
         CGFloat((hex >> 8) & 0xFF) / 255,
         CGFloat(hex & 0xFF) / 255, a)
    }

    /// An appearance-resolving NSColor: `dark` value under Dark Aqua, else `light`.
    private static func dynNS(_ dHex: UInt32, _ dA: CGFloat,
                             _ lHex: UInt32, _ lA: CGFloat) -> NSColor {
        NSColor(name: nil) { ap in
            let isDark = ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? comps(dHex, dA) : comps(lHex, lA)
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        }
    }

    private static func dyn(_ dHex: UInt32, _ dA: CGFloat,
                            _ lHex: UInt32, _ lA: CGFloat) -> Color {
        Color(nsColor: dynNS(dHex, dA, lHex, lA))
    }

    /// Appearance-invariant colour (brand constants).
    private static func solidNS(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        let c = comps(hex, a)
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
    }
    private static func solid(_ hex: UInt32, _ a: CGFloat = 1) -> Color { Color(nsColor: solidNS(hex, a)) }

    /// Parse a "#RRGGBB" (or "RRGGBB") string for the accent override.
    static func hexColor(_ string: String) -> NSColor? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return solidNS(v)
    }

    // ---- brand (appearance-invariant) -------------------------------------
    static let brandLime     = Color(nsColor: solidNS(0x4CE62E)) // [design] mark — the one place lime carries weight
    static let brandLimeNeon = Color(nsColor: solidNS(0x3DFF1A)) // raw logo neon — lockups/glow only
    static let brandInk      = Color(nsColor: solidNS(0x121212)) // logo plate
    static var brandLimeNS: NSColor { solidNS(0x4CE62E) }

    // ---- neutral ramp (dark / light) --------------------------------------
    static var n0:   Color { dyn(0x0E0E10, 1, 0xFFFFFF, 1) }
    static var n50:  Color { dyn(0x151517, 1, 0xFBFBFC, 1) }
    static var n100: Color { dyn(0x181819, 1, 0xF4F4F6, 1) } // window bg — the owner's signature value
    static var n150: Color { dyn(0x1D1D1F, 1, 0xEEEEF0, 1) }
    static var n200: Color { dyn(0x232325, 1, 0xFFFFFF, 1) }
    static var n300: Color { dyn(0x2B2B2E, 1, 0xF0F0F2, 1) }
    static var n400: Color { dyn(0x3A3A3E, 1, 0xE4E4E8, 1) }
    static var n500: Color { dyn(0x4D4D52, 1, 0xD0D0D6, 1) }
    static var n600: Color { dyn(0x6B6B71, 1, 0x8A8A90, 1) }
    static var n700: Color { dyn(0x8E8E94, 1, 0x6A6A70, 1) }
    static var n800: Color { dyn(0xC7C7CC, 1, 0x3A3A40, 1) }
    static var n900: Color { dyn(0xF2F2F5, 1, 0x1A1A1C, 1) }

    // ---- surfaces (chrome only — NOT the canvas) --------------------------
    static var surfaceWindow:     Color { n100 }
    static var surfacePanel:      Color { dyn(0x1E1E21, 0.72, 0xFFFFFF, 0.66) } // glass tint over blur
    static var surfacePanelSolid: Color { n150 }                                // Reduce-Transparency fallback
    static var surfaceRaised:     Color { n200 }
    static var surfaceCard:       Color { dyn(0xFFFFFF, 0.04, 0x000000, 0.035) }
    static var surfaceField:      Color { dyn(0xFFFFFF, 0.05, 0x000000, 0.045) }
    static var surfaceFieldFocus: Color { dyn(0xFFFFFF, 0.08, 0x000000, 0.07) }
    static var surfacePopover:    Color { dyn(0x262629, 0.80, 0xFFFFFF, 0.82) }
    static var surfaceToolbar:    Color { dyn(0x161618, 0.60, 0xF8F8FA, 0.65) }
    static var surfacePanelSolidNS: NSColor { dynNS(0x1D1D1F, 1, 0xEEEEF0, 1) }
    static var surfaceRaisedNS:     NSColor { dynNS(0x232325, 1, 0xFFFFFF, 1) }

    // ---- row states -------------------------------------------------------
    static var rowHover:    Color { dyn(0xFFFFFF, 0.06, 0x000000, 0.05) }
    static var rowActive:   Color { dyn(0xFFFFFF, 0.10, 0x000000, 0.08) }
    static var rowSelected: Color { accentSubtle }

    // ---- text tiers (hierarchy from opacity: 100 / 62 / 42 / 28) ----------
    static var textPrimary:    Color { dyn(0xF2F2F5, 1.00, 0x141416, 1.00) }
    static var textSecondary:  Color { dyn(0xF2F2F5, 0.62, 0x141416, 0.60) }
    static var textTertiary:   Color { dyn(0xF2F2F5, 0.42, 0x141416, 0.40) }
    static var textQuaternary: Color { dyn(0xF2F2F5, 0.28, 0x141416, 0.26) }
    static var textOnAccent:   Color { .white }
    static var textAccent:     Color { accent }                 // tracks the (overridable) accent
    static var textBrand:      Color { dyn(0x4CE62E, 1, 0x2AA516, 1) } // lime darkened for contrast on light
    static var textPrimaryNS:   NSColor { dynNS(0xF2F2F5, 1.00, 0x141416, 1.00) }
    static var textSecondaryNS: NSColor { dynNS(0xF2F2F5, 0.62, 0x141416, 0.60) }
    static var textTertiaryNS:  NSColor { dynNS(0xF2F2F5, 0.42, 0x141416, 0.40) }

    // ---- lines & borders --------------------------------------------------
    static var hairline:     Color { dyn(0xFFFFFF, 0.09, 0x000000, 0.10) } // separatorColor analog
    static var borderSoft:   Color { dyn(0xFFFFFF, 0.07, 0x000000, 0.08) }
    static var borderGlass:  Color { dyn(0xFFFFFF, 0.12, 0xFFFFFF, 0.85) } // the lit top edge of glass
    static var borderStrong: Color { dyn(0xFFFFFF, 0.18, 0x000000, 0.16) }
    static var hairlineNS:    NSColor { dynNS(0xFFFFFF, 0.09, 0x000000, 0.10) }

    // ---- semantics --------------------------------------------------------
    static var green:  Color { dyn(0x32D74B, 1, 0x28CD41, 1) }
    static var red:    Color { dyn(0xFF453A, 1, 0xFF3B30, 1) }
    static var orange: Color { dyn(0xFF9F0A, 1, 0xFF9500, 1) }
    static var teal:   Color { dyn(0x40C8E0, 1, 0x00A3C4, 1) } // guides / measurement cyan
    static var yellow: Color { dyn(0xFFD60A, 1, 0xFFD60A, 1) }
    static var tealNS: NSColor { dynNS(0x40C8E0, 1, 0x00A3C4, 1) }

    // ---- accent (interactive) — overridable -------------------------------
    //
    // DEFAULT = the user's macOS system accent (`controlAccentColor`), exactly
    // like System Settings. When the app-specific override is set (Settings ▸
    // Design, 17i), every accent token derives from it. Hover/press are computed
    // (blend toward white/black), subtle/subtle2 are the accent at a fixed low
    // alpha (a slight simplification of the CSS's per-appearance 0.16/0.12 — one
    // value reads the same in both and avoids a non-Sendable capture).

    /// The live accent: app override if set, else the system accent.
    static func resolvedAccentNS() -> NSColor {
        if let hex = UserDefaults.standard.string(forKey: AppPreferences.accentOverride),
           let c = hexColor(hex) { return c }
        return .controlAccentColor
    }

    static var accent:       Color   { Color(nsColor: resolvedAccentNS()) }
    static var accentNS:     NSColor { resolvedAccentNS() }
    static var accentOn:     Color   { .white }
    /// Auto-contrast foreground for text/icons on a SOLID accent fill: near-black on
    /// a light accent, white on a dark one — so a light accent override stays legible
    /// (WCAG relative luminance). Use this on primary buttons / selected segments.
    static var accentForeground: Color { onColor(resolvedAccentNS()) }
    static func onColor(_ color: NSColor) -> Color {
        let c = color.usingColorSpace(.sRGB) ?? color
        func lin(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        let L = 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        return L > 0.6 ? Color(nsColor: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)) : .white
    }
    static var accentSubtle:  Color  { Color(nsColor: resolvedAccentNS().withAlphaComponent(0.15)) }
    static var accentSubtle2: Color  { Color(nsColor: resolvedAccentNS().withAlphaComponent(0.22)) }
    static var accentHover: Color {
        let base = resolvedAccentNS().usingColorSpace(.sRGB) ?? resolvedAccentNS()
        return Color(nsColor: base.blended(withFraction: 0.18, of: .white) ?? base)
    }
    static var accentPress: Color {
        let base = resolvedAccentNS().usingColorSpace(.sRGB) ?? resolvedAccentNS()
        return Color(nsColor: base.blended(withFraction: 0.16, of: .black) ?? base)
    }

    // ---- canvas (the undesigned centre — isolated on purpose) -------------
    enum Canvas {
        static var bg:         NSColor { dynNS(0x1C1C1E, 1, 0xE8E8EA, 1) }
        static var artboard:   NSColor { solidNS(0xFFFFFF) }
        static var rulerBg:    NSColor { dynNS(0x181819, 0.70, 0xF4F4F6, 0.80) }
        static var rulerTick:  NSColor { dynNS(0xF2F2F5, 0.34, 0x141416, 0.34) }
        static var selection:  NSColor { resolvedAccentNS() }
        static var guideTint:  NSColor { EXPColor.tealNS }
    }
}

// MARK: - Type ==============================================================

/// Type roles from `tokens/typography.css`. SF Pro is the system font (so
/// `.system(...)` is exactly right); SF Compact is the condensed voice for layer
/// names / dense labels — resolved at runtime with a graceful fallback. Weight
/// philosophy: light/ultralight carry the brand; medium is the one emphasis.
enum EXPType {
    // Scale (pt)
    static let micro: CGFloat = 10, mini: CGFloat = 11, small: CGFloat = 12
    static let base: CGFloat = 13, md: CGFloat = 15, lg: CGFloat = 18
    static let xl: CGFloat = 22, xxl: CGFloat = 28, xxxl: CGFloat = 40, display: CGFloat = 64

    // Tracking (em → points helper)
    static func tracking(_ em: CGFloat, _ size: CGFloat) -> CGFloat { size * em }
    static let trCaps: CGFloat = 0.06   // panel titles
    static let trWide: CGFloat = 0.04   // section labels

    // ---- SF Compact (condensed) resolution --------------------------------
    @MainActor private static var compactChecked = false
    @MainActor private static var compactAvailable = false
    @MainActor static func hasSFCompact() -> Bool {
        if !compactChecked {
            compactAvailable = NSFontManager.shared.availableFontFamilies.contains("SF Compact Display")
            compactChecked = true
        }
        return compactAvailable
    }
    /// Layer-name font: SF Compact Display (BUNDLED + registered at launch — see
    /// FontRegistration.swift), else a defensive system fallback. Apply the weight
    /// at the call site via `.fontWeight`.
    @MainActor static func layerFont(size: CGFloat = small) -> Font {
        hasSFCompact() ? .custom("SF Compact Display", size: size) : .system(size: size)
    }
}

/// Named SwiftUI font roles (the SF-Pro ones; no tracking/case — see the View
/// modifiers below for panel/section which need those).
extension Font {
    static var expDocName: Font  { .system(size: EXPType.md,    weight: .light) }
    static var expPanelTitle: Font { .system(size: EXPType.base, weight: .regular) }
    static var expSection: Font  { .system(size: EXPType.mini,  weight: .ultraLight) }
    static var expArtboard: Font { .system(size: EXPType.small, weight: .medium) }
    static var expLabel: Font    { .system(size: EXPType.small, weight: .light) }
    static var expNumeric: Font  { .system(size: EXPType.small, weight: .regular).monospacedDigit() }
}

extension View {
    /// UPPERCASE panel title (e.g. LAYERS, PROPERTIES) — 13 regular, +0.06em.
    func expPanelTitle() -> some View {
        self.font(.expPanelTitle)
            .textCase(.uppercase)
            .tracking(EXPType.tracking(EXPType.trCaps, EXPType.base))
            .foregroundStyle(EXPColor.textPrimary)
    }
    /// UPPERCASE section label — 11 ultralight, +0.04em, secondary.
    func expSectionLabel() -> some View {
        self.font(.expSection)
            .textCase(.uppercase)
            .tracking(EXPType.tracking(EXPType.trWide, EXPType.mini))
            .foregroundStyle(EXPColor.textSecondary)
    }
    /// Layer-name row text — SF Compact 12, medium when the layer is active.
    @MainActor func expLayerName(active: Bool) -> some View {
        self.font(EXPType.layerFont())
            .fontWeight(active ? .medium : .light)
    }
}

// MARK: - Metrics (spacing · radii · stroke · layout) =======================

/// From `tokens/spacing.css`. Deliberately small and varied — do NOT snap to an
/// 8-grid; the source uses 6 and 12 on purpose.
enum EXPMetric {
    // spacing scale
    static let xxs: CGFloat = 2, xs: CGFloat = 4, sm: CGFloat = 6, md: CGFloat = 8
    static let lg: CGFloat = 12, xl: CGFloat = 16, xxl: CGFloat = 24, xxxl: CGFloat = 32
    // panel rhythm
    static let panelPadH: CGFloat = 12, rowGap: CGFloat = 6
    static let sectionGap: CGFloat = 8, sectionHeadGap: CGFloat = 12
    // radii
    static let radiusDrop: CGFloat = 4, radiusField: CGFloat = 5, radiusRow: CGFloat = 6
    static let radiusCard: CGFloat = 6, radiusTool: CGFloat = 6, radiusControl: CGFloat = 7
    static let radiusButton: CGFloat = 8, radiusPanel: CGFloat = 12, radiusPill: CGFloat = 999
    // stroke
    static let strokeHairline: CGFloat = 1, strokeSelection: CGFloat = 1.5
    static let strokeDropline: CGFloat = 2, strokeFocus: CGFloat = 2
    // canvas handle metrics
    static let handleSize: CGFloat = 8, handleGrab: CGFloat = 12, rotateOffset: CGFloat = 22
    static let rulerSize: CGFloat = 20, guideTol: CGFloat = 4
    // layout
    static let dockLeftWidth: CGFloat = 264, dockRightWidth: CGFloat = 332
    static let toolsStripWidth: CGFloat = 44
    static let windowMinWidth: CGFloat = 900, windowMinHeight: CGFloat = 600
    static let titlebarHeight: CGFloat = 52, panelHeaderHeight: CGFloat = 38
    // control sizing
    static let controlH: CGFloat = 24, controlHLg: CGFloat = 30
    static let iconBtn: CGFloat = 24, hitTarget: CGFloat = 28, fieldWNumeric: CGFloat = 56
}

// MARK: - Motion ============================================================

/// From `tokens/spacing.css`. Restrained, macOS-ish: ease-out for state changes;
/// a gentle overshoot only on toggles. Always respect Reduce Motion.
enum EXPMotion {
    static let durFast = 0.12, durBase = 0.18, durSlow = 0.26
    static var standard: Animation { .timingCurve(0.22, 0.61, 0.36, 1, duration: durBase) }
    static var emphasis: Animation { .timingCurve(0.34, 1.20, 0.40, 1, duration: durBase) }
    static var fast:     Animation { .timingCurve(0.22, 0.61, 0.36, 1, duration: durFast) }
    /// nil under Reduce Motion (callers pass `accessibilityReduceMotion`).
    static func standard(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : standard }
    static func emphasis(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : emphasis }
}

// MARK: - Glass values (data; the modifier lands in 17b) ====================

/// Liquid-glass token VALUES from `tokens/glass.css`. 17b builds the reusable
/// `.glass(...)` surface modifier (native macOS-26 Liquid Glass, with an
/// NSVisualEffectView/Material fallback for canvas-overlay glass). Held here so
/// the values live with the rest of the tokens.
enum EXPGlass {
    enum Thickness { case thin, medium, thick }

    static func blur(_ t: Thickness) -> CGFloat {
        switch t { case .thin: 16; case .medium: 30; case .thick: 50 }
    }
    static let saturate: CGFloat = 1.8

    /// Tint that sits over the blur (dark home / light mirror).
    static func tint(_ t: Thickness) -> Color {
        switch t {
        case .thin:   EXPColor.glassTintThin
        case .medium: EXPColor.glassTintMedium
        case .thick:  EXPColor.glassTintThick
        }
    }

    /// One drop-shadow layer (SwiftUI has no spread; radius ≈ CSS blur / 2).
    struct ShadowLayer: Sendable { let color: Color; let radius: CGFloat; let x: CGFloat; let y: CGFloat }
    static let panel:   [ShadowLayer] = [.init(color: .black.opacity(0.42), radius: 14, x: 0, y: 8)]
    static let popover: [ShadowLayer] = [.init(color: .black.opacity(0.50), radius: 20, x: 0, y: 12)]
    static let modal:   [ShadowLayer] = [.init(color: .black.opacity(0.62), radius: 40, x: 0, y: 30)]
    static let drag:    [ShadowLayer] = [.init(color: .black.opacity(0.50), radius: 20, x: 0, y: 16)]
}

extension EXPColor {
    static var glassTintThin:   Color { dyn(0x1C1C1F, 0.46, 0xFFFFFF, 0.55) }
    static var glassTintMedium: Color { dyn(0x1E1E21, 0.66, 0xFFFFFF, 0.70) }
    static var glassTintThick:  Color { dyn(0x222226, 0.78, 0xFFFFFF, 0.82) }
}

// MARK: - Field style (flat token text field) ==============================

/// The brand text field (design-system `TextField`): flat `surface-field` fill,
/// `border-strong` hairline, radius 5, 12pt — NOT the macOS bezel. Apply with
/// `.textFieldStyle(.exp)`. (Focus shows the text cursor; the accent focus ring
/// from the spec needs per-field @FocusState and can layer on later.)
struct EXPFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: EXPType.small))
            .foregroundStyle(EXPColor.textPrimary)
            .padding(.horizontal, 7)
            .frame(height: EXPMetric.controlH)
            .background(EXPColor.surfaceField,
                        in: RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EXPMetric.radiusField, style: .continuous)
                    .strokeBorder(EXPColor.borderStrong, lineWidth: EXPMetric.strokeHairline)
            )
    }
}

extension TextFieldStyle where Self == EXPFieldStyle {
    /// The brand flat field. Usage: `TextField(...).textFieldStyle(.exp)`.
    static var exp: EXPFieldStyle { EXPFieldStyle() }
}
