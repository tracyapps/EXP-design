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

// MARK: - Field tip (rich hover help for form fields) ========================

/// The app-wide rich tip for FORM FIELDS: a short title naming the value plus
/// an optional multi-line detail explaining what it does — direction of change
/// ("higher = finer grain"), units, and value ranges. Never assume shorthand
/// like "W" or "Oct" is universally understood; spell it out here.
///
/// Hierarchy: the title renders in the accent color; `detail` accepts inline
/// MARKDOWN — `**bold**` runs brighten to the primary text color for subtle
/// emphasis, and literal newlines are preserved as line breaks.
///
/// Presentation: the bubble lives in a borderless CHILD WINDOW, not a SwiftUI
/// overlay — so it can spill past the panel's edge when there's monitor space,
/// and is clamped to the visible screen frame when there isn't (it slides left
/// / flips below the field rather than getting cut off). An overlay could
/// never do this: the panel's scroll view and the window clip it.
///
/// Accessibility: the detail is ALSO attached as an `accessibilityHint`, so
/// VoiceOver users get the same explanation the hover bubble shows.
private struct EXPFieldTipModifier: ViewModifier {
    let title: String
    let detail: String
    let edge: VerticalEdge
    let align: HorizontalAlignment
    @State private var hostWindow: NSWindow?
    @State private var anchorFrame = CGRect.zero   // SwiftUI .global (window content, y-down)
    @State private var hoverTask: Task<Void, Never>?
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .accessibilityHint(detail.isEmpty ? Text(title) : Text(detail))
            .background(EXPWindowReader { hostWindow = $0 })
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { anchorFrame = $0 }
            .onHover { inside in
                hoverTask?.cancel()
                if inside {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        guard !Task.isCancelled else { return }
                        present()
                    }
                } else {
                    dismiss()
                }
            }
            .onDisappear { dismiss() }
    }

    @MainActor private func present() {
        guard let win = hostWindow, let contentView = win.contentView else { return }
        // SwiftUI .global (top-left, y-down) → the content view's own space.
        // NSHostingView is flipped, so the rect passes straight through; the
        // convert calls then handle any flippedness + the titlebar offset.
        let inContent = CGRect(x: anchorFrame.minX, y: anchorFrame.minY,
                               width: anchorFrame.width, height: anchorFrame.height)
        let inWindow = contentView.convert(inContent, to: nil)
        let onScreen = win.convertToScreen(inWindow)
        EXPFieldTipWindow.shared.show(
            EXPFieldTipBubble(title: title, detail: detail),
            anchor: onScreen, parent: win, edge: edge, align: align)
        showing = true
    }

    @MainActor private func dismiss() {
        guard showing else { return }
        EXPFieldTipWindow.shared.hide()
        showing = false
    }
}

/// Reports the NSWindow hosting this SwiftUI hierarchy (needed to convert the
/// anchor's rect into screen coordinates and to parent the tip window).
private struct EXPWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { [weak v] in onWindow(v?.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { [weak v] in onWindow(v?.window) }
    }
}

/// The single floating tip window shared by every field tip: borderless,
/// non-activating, click-through, added as a CHILD of the hovered panel so it
/// tracks window moves and always draws above it. Placement is EDGE-AWARE in
/// screen space: preferred spot first (above the field, leading- or trailing-
/// aligned), then slid horizontally inside the screen's visible frame, and
/// flipped below the field if there's no room above.
@MainActor
private final class EXPFieldTipWindow {
    static let shared = EXPFieldTipWindow()
    private var panel: NSPanel?

    func show(_ bubble: EXPFieldTipBubble, anchor: CGRect, parent: NSWindow,
              edge: VerticalEdge, align: HorizontalAlignment) {
        hide()
        let host = NSHostingView(rootView: bubble)
        let size = host.fittingSize
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                 // the bubble draws its own
        panel.ignoresMouseEvents = true         // never steals the hover
        panel.isReleasedWhenClosed = false
        panel.contentView = host

        // Preferred position (screen coords, y-up): above the field, aligned
        // to its leading or trailing edge, floated 6pt clear of it.
        var x = align == .trailing ? anchor.maxX - size.width : anchor.minX
        var y = edge == .top ? anchor.maxY + 6 : anchor.minY - size.height - 6
        if let vis = (parent.screen ?? NSScreen.main)?.visibleFrame {
            // Slide inside the monitor horizontally (overflowing the PANEL is
            // fine and intended — only the screen edge is a hard wall).
            if x + size.width > vis.maxX - 4 { x = vis.maxX - 4 - size.width }
            if x < vis.minX + 4 { x = vis.minX + 4 }
            // No room on the preferred side → flip to the other side of the field.
            if edge == .top, y + size.height > vis.maxY - 4 { y = anchor.minY - size.height - 6 }
            if y < vis.minY + 4 { y = anchor.maxY + 6 }
        }
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)
        parent.addChildWindow(panel, ordered: .above)
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func hide() {
        guard let p = panel else { return }
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
        panel = nil
    }
}

/// The tip bubble itself (also what the tip window hosts).
private struct EXPFieldTipBubble: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EXPColor.accent)
            if !detail.isEmpty {
                detailText
                    .font(.system(size: 10.5, weight: .light))
                    .foregroundStyle(EXPColor.textSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        // Detail bubbles take a FIXED readable width; title-only tips hug.
        .frame(width: detail.isEmpty ? nil : 232, alignment: .leading)
        .fixedSize(horizontal: detail.isEmpty, vertical: true)
        .background(EXPColor.surfacePopover,
                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: EXPMetric.radiusRow, style: .continuous)
            .strokeBorder(EXPColor.borderGlass, lineWidth: EXPMetric.strokeHairline))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        .padding(14)   // room for the shadow inside the borderless window
    }

    /// `detail` parsed as inline markdown, with `**bold**` runs lifted to the
    /// primary text color so emphasis reads as hierarchy, not just weight.
    private var detailText: Text {
        var attr = (try? AttributedString(
            markdown: detail,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(detail)
        let boldRanges = attr.runs.compactMap { run -> Range<AttributedString.Index>? in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true ? run.range : nil
        }
        for r in boldRanges { attr[r].foregroundColor = EXPColor.textPrimary }
        return Text(attr)
    }
}

extension View {
    /// App-wide rich field tip. `title` names the value ("Width"); `detail`
    /// explains it ("In pixels…") and may use inline markdown + newlines.
    /// Placement is screen-edge aware; `edge`/`align` only set the PREFERRED
    /// spot (above/below, leading/trailing) before clamping kicks in.
    func expFieldTip(_ title: String, _ detail: String = "",
                     edge: VerticalEdge = .top,
                     align: HorizontalAlignment = .leading) -> some View {
        modifier(EXPFieldTipModifier(title: title, detail: detail, edge: edge, align: align))
    }
}
