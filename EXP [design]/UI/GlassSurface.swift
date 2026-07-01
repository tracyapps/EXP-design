//
//  GlassSurface.swift
//  EXP [design]
//
//  Phase 17b — the reusable LIQUID GLASS surface primitive the whole chrome
//  reskin composes. One modifier, `.expGlass(...)`, with two backends + a
//  fallback, so every panel/tray/popover/modal shares ONE material vocabulary
//  (the unified-glass requirement from the Session-133 callouts):
//
//   • .liquid   — native macOS-26 Liquid Glass (`.glassEffect`). DEFAULT for
//                 docked chrome, popovers, the floating editor. (Deployment
//                 target is 26.2, so no availability guard is needed.)
//   • .material — NSVisualEffectView (real backdrop blur). For glass that sits
//                 directly on the hand-drawn canvas (rulers / notes overlay,
//                 wired in 17h) where the native effect can't sample a backdrop.
//   • Reduce Transparency → opaque token plate (no blur), automatically.
//
//  Thickness (thin/medium/thick) maps to tint + elevation per the brief:
//  thin = tools rail / toolbars, medium = docks / popovers, thick = modals.
//  Values come from `EXPGlass` / `EXPColor` in DesignTokens.swift.
//
//  17b adds ONLY the primitive (+ a DEBUG preview). Rewiring ToolsStrip /
//  PanelDock / PanelWindow off `.background(.bar)` onto this is 17c.
//

import SwiftUI
import AppKit

// MARK: - Style ============================================================

enum EXPGlassStyle {
    case liquid     // native Liquid Glass (docked chrome, popovers, modals)
    case material   // NSVisualEffectView (canvas-overlay glass — 17h)
}

// MARK: - NSVisualEffectView backend =======================================

/// Real backdrop blur for the `.material` backend. `.withinWindow` blending so
/// it samples whatever is behind it inside the window (e.g. the canvas under a
/// floating ruler/notes panel).
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active           // keep the blur even when the window is inactive
        v.isEmphasized = false
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

// MARK: - Window-level glass (floating panel windows) =======================

/// Liquid glass for a floating panel WINDOW: real BEHIND-window blur that stays
/// glassy and gets THINNER when the window is inactive — instead of the system
/// default of darkening/muting on resign-key. Drive `active` from the call site's
/// `\.controlActiveState`. `state = .active` (set in VisualEffectBackground) means
/// the material itself never auto-dims; we express "active vs inactive" purely as a
/// heavier vs lighter brand tint over a constant blur. Reduce-Transparency → solid.
struct WindowGlassBackground: View {
    var active: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            EXPColor.surfacePanelSolid
        } else {
            VisualEffectBackground(material: .sidebar, blending: .behindWindow)
                // Thin brand tint when focused; even thinner (lighter, more glass)
                // when not — never darker. Tune these two if it reads heavy/light.
                .overlay(active ? EXPColor.glassTintThin : EXPColor.glassTintThin.opacity(0.45))
                .ignoresSafeArea()
        }
    }
}

// MARK: - Top-edge gradient (header weight on glass windows) =================

/// A subtle gradient that's more opaque at the very TOP and fades to clear — a
/// touch of "header weight" so a grab bar / titlebar reads solid over glass.
/// Applied to every window (floating trays + the main window) via `.expTopEdge()`.
struct TopEdgeGradient: View {
    var height: CGFloat = 44
    var body: some View {
        LinearGradient(
            stops: [
                // SOLID at the very top (covers the glass backdrop → reads as a
                // header), fading to clear so the glass returns below.
                .init(color: EXPColor.surfacePanelSolid,             location: 0.0),
                .init(color: EXPColor.surfacePanelSolid.opacity(0.6), location: 0.4),
                .init(color: EXPColor.surfacePanelSolid.opacity(0.0), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Overlay the top-edge gradient, pinned to (and extending past) the top edge.
    func expTopEdge(height: CGFloat = 44) -> some View {
        overlay(alignment: .top) {
            TopEdgeGradient(height: height).ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - The modifier =====================================================

private struct ExpGlassModifier: ViewModifier {
    let thickness: EXPGlass.Thickness
    let style: EXPGlassStyle
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }
    private var tintColor: Color { tint ?? EXPGlass.tint(thickness) }

    func body(content: Content) -> some View {
        content
            .background { backdrop }
    }

    @ViewBuilder private var backdrop: some View {
        Group {
            if reduceTransparency {
                // Opaque plate — no blur. Honors Reduce Transparency.
                shape.fill(opaquePlate)
            } else {
                switch style {
                case .liquid:
                    // Native Liquid Glass, brand-tinted, clipped to the shape.
                    Color.clear
                        .glassEffect(
                            .regular.tint(tintColor).interactive(interactive),
                            in: shape
                        )
                case .material:
                    VisualEffectBackground(material: nsMaterial)
                        .overlay(shape.fill(tintColor))   // brand tint over the blur
                        .clipShape(shape)
                }
            }
        }
        .overlay { sheen }
        .overlay { litRim }
        .compositingGroup()
        .shadow(color: elevation.color, radius: elevation.radius, x: 0, y: elevation.y)
    }

    // ---- pieces -----------------------------------------------------------

    /// Lit top rim → fading hairline (brighter under Increase Contrast).
    private var litRim: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [contrast == .increased ? EXPColor.borderStrong : EXPColor.borderGlass,
                         EXPColor.borderGlass.opacity(0)],
                startPoint: .top, endPoint: .bottom),
            lineWidth: EXPMetric.strokeHairline)
    }

    /// Top-down sheen highlight (stronger in light, per glass.css).
    private var sheen: some View {
        shape.fill(
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(scheme == .dark ? 0.10 : 0.55), location: 0.0),
                    .init(color: .white.opacity(scheme == .dark ? 0.02 : 0.10), location: 0.20),
                    .init(color: .white.opacity(0.0), location: 0.42),
                ],
                startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
    }

    private var opaquePlate: Color {
        thickness == .thick ? EXPColor.surfaceRaised : EXPColor.surfacePanelSolid
    }

    private var nsMaterial: NSVisualEffectView.Material {
        switch thickness {
        case .thin:   .hudWindow
        case .medium: .sidebar
        case .thick:  .popover
        }
    }

    /// Elevation per thickness (shadow.css), softened in light mode.
    private var elevation: (color: Color, radius: CGFloat, y: CGFloat) {
        let dark = scheme == .dark
        switch thickness {
        case .thin:   return (.black.opacity(dark ? 0.30 : 0.10),  6, 2)
        case .medium: return (.black.opacity(dark ? 0.42 : 0.16), 14, 8)
        case .thick:  return (.black.opacity(dark ? 0.62 : 0.24), 40, 30)
        }
    }
}

// MARK: - Public API =======================================================

extension View {
    /// EXP liquid-glass surface. Apply to a panel/tray/popover/control body; the
    /// blur, brand tint, lit rim, sheen and elevation are handled here so every
    /// surface reads identically. `cornerRadius` defaults to the panel radius.
    func expGlass(_ thickness: EXPGlass.Thickness = .medium,
                  style: EXPGlassStyle = .liquid,
                  cornerRadius: CGFloat = EXPMetric.radiusPanel,
                  tint: Color? = nil,
                  interactive: Bool = false) -> some View {
        modifier(ExpGlassModifier(thickness: thickness, style: style,
                                  cornerRadius: cornerRadius, tint: tint,
                                  interactive: interactive))
    }

    /// Convenience roles (the readme's thickness→surface mapping).
    func expToolbarGlass() -> some View { expGlass(.thin,   cornerRadius: EXPMetric.radiusTool) }
    func expPanelGlass()   -> some View { expGlass(.medium, cornerRadius: EXPMetric.radiusPanel) }
    func expPopoverGlass() -> some View { expGlass(.medium, cornerRadius: EXPMetric.radiusPanel) }
    func expModalGlass()   -> some View { expGlass(.thick,  cornerRadius: EXPMetric.radiusPanel) }
}

// MARK: - Proof preview (DEBUG) ============================================

#if DEBUG
private struct GlassSurfaceProof: View {
    var body: some View {
        ZStack {
            // A colourful, busy backdrop so the glass lensing/tint is visible.
            LinearGradient(colors: [.blue, .purple, .pink, .orange],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            HStack(spacing: 24) {
                ForEach([("thin", EXPGlass.Thickness.thin),
                         ("medium", .medium),
                         ("thick", .thick)], id: \.0) { name, t in
                    VStack(spacing: 10) {
                        Text(name).expSectionLabel()
                        Spacer()
                        Text("liquid").font(.expLabel).foregroundStyle(EXPColor.textPrimary)
                    }
                    .padding(EXPMetric.lg)
                    .frame(width: 150, height: 180, alignment: .topLeading)
                    .expGlass(t)
                }
            }
            .padding(40)
        }
        .frame(width: 640, height: 320)
    }
}

#Preview("Glass — Dark") { GlassSurfaceProof().preferredColorScheme(.dark) }
#Preview("Glass — Light") { GlassSurfaceProof().preferredColorScheme(.light) }
#endif

// MARK: - Tooltip (design-system Tooltip: label + keycap shortcut) ===========

/// A hover tooltip matching the design-system `Tooltip`: a translucent popover
/// with the label and an optional monospaced keycap for the shortcut. Appears to
/// the RIGHT of the trigger after a short delay (tuned for the left tools rail).
/// Usage: `.expTooltip(label: "Pan", shortcut: "H")`.
private struct EXPTooltipModifier: ViewModifier {
    let label: String
    let shortcut: String
    @State private var show = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hoverTask?.cancel()
                if inside {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        if !Task.isCancelled { show = true }
                    }
                } else {
                    show = false
                }
            }
            .overlay(alignment: .leading) {
                if show { bubble.offset(x: 40).zIndex(1000) }   // to the right of the rail
            }
            .animation(EXPMotion.fast, value: show)
    }

    private var bubble: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(EXPColor.textPrimary)
            if !shortcut.isEmpty {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(EXPColor.accent)                      // accent keycap
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(EXPColor.accentSubtle,
                                in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(EXPColor.accent.opacity(0.35), lineWidth: 1))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .fixedSize()
        .background(EXPColor.surfacePopover,
                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous)
            .strokeBorder(EXPColor.borderGlass, lineWidth: EXPMetric.strokeHairline))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

extension View {
    /// Design-system hover tooltip (label + optional keycap shortcut).
    func expTooltip(label: String, shortcut: String = "") -> some View {
        modifier(EXPTooltipModifier(label: label, shortcut: shortcut))
    }
}
