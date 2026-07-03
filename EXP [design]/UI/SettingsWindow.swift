//
//  SettingsWindow.swift
//  EXP [design]
//
//  The app-wide Settings screen. Deliberately built as a FULL window (sidebar +
//  detail pane), not a stack of menu items, so it scales: adding a new options
//  group is one `SettingsPane` case + one view. This is the "App settings /
//  preferences" item from the roadmap (owns the toggles that were living on the
//  View menu, and is the future home for the design-token controls).
//
//  Scope rule: Settings is APP-WIDE. It is one window for the whole app, so it
//  cannot reach into any one document window's `AppState` (that's per-window
//  session state). Everything here is therefore backed by UserDefaults via
//  `AppPreferences` / `@AppStorage`. `AppState.init` reads those same keys, so a
//  new editor window opens honouring whatever the user set here. (Live windows
//  keep their current session values; the defaults apply on next window.)
//

import SwiftUI

// MARK: - Shared preference keys (the single source of truth for both sides)

/// App-wide preference keys + their defaults. Shared by the Settings screen
/// (which writes them) and `AppState` (which reads them when a window opens), so
/// the two never drift. Defaults here MUST match the literals AppState falls back
/// to, so an unset key behaves exactly like today.
enum AppPreferences {
    static let smartGuides         = "exp.pref.smartGuides"          // Bool, default true
    static let showSelectionBounds = "exp.pref.showSelectionBounds"  // Bool, default true
    static let snapToGrid          = "exp.pref.snapToGrid"           // Bool, default false
    static let gridSize            = "exp.pref.gridSize"             // Double (points), default 50
    static let gridSubdivisions    = "exp.pref.gridSubdivisions"     // Int, default 2
    static let restoreLayout       = "exp.pref.restoreLayout"        // Bool, default true
    static let textBoxTrim         = "exp.pref.textBoxTrim"          // String, default "capBaseline"
    static let sourceBackdrop      = "exp.pref.sourceBackdrop"       // String (CanvasBackdrop raw), default "light"
    static let accentOverride      = "exp.pref.accentOverride"      // String "#RRGGBB"; ABSENT = follow macOS system accent (default)
    static let performanceMode     = "exp.pref.performanceMode"     // String (CanvasPerformanceMode raw), default "balanced"

    // Defaults (kept next to the keys so AppState and Settings agree).
    static let defaultSmartGuides         = true
    static let defaultShowSelectionBounds = true
    static let defaultSnapToGrid          = false
    static let defaultGridSize: Double    = 50
    static let defaultGridSubdivisions    = 2
    static let defaultRestoreLayout       = true
    static let defaultTextBoxTrim         = "capBaseline"
    static let defaultPerformanceMode     = "balanced"
}

// MARK: - Pane catalogue (add a case + a view to grow Settings)

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, canvas, designTokens, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:      return "General"
        case .canvas:       return "Canvas"
        case .designTokens: return "Design Tokens"
        case .about:        return "About"
        }
    }

    /// SF Symbol for the sidebar row.
    var symbol: String {
        switch self {
        case .general:      return "gearshape"
        case .canvas:       return "squareshape.dashed.squareshape"
        case .designTokens: return "swatchpalette"
        case .about:        return "info.circle"
        }
    }
}

// MARK: - Window

struct SettingsWindow: View {
    // Optional because `List(selection:)` single-selection binds an optional;
    // nil is treated as General so the detail pane is never blank.
    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                detail
                    .padding(24)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle((pane ?? .general).title)
        }
        // Roomy default so panes have space to grow into; the user can resize.
        .frame(minWidth: 720, idealWidth: 820, minHeight: 460, idealHeight: 560)
    }

    @ViewBuilder private var detail: some View {
        switch pane ?? .general {
        case .general:      GeneralSettingsPane()
        case .canvas:       CanvasSettingsPane()
        case .designTokens: DesignTokensSettingsPane()
        case .about:        AboutSettingsPane()
        }
    }
}

// MARK: - Panes

/// A titled block of related controls — keeps every pane visually consistent and
/// is the unit a future design token can restyle once.
private struct SettingsGroup<Content: View>: View {
    let title: String
    let footnote: String?
    @ViewBuilder var content: Content

    init(_ title: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.expDocName)
                .foregroundStyle(EXPColor.textPrimary)
            VStack(alignment: .leading, spacing: 12) { content }
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct GeneralSettingsPane: View {
    @AppStorage(AppPreferences.restoreLayout) private var restoreLayout =
        AppPreferences.defaultRestoreLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("Workspace",
                          footnote: "\u{201C}Reset\u{201D} clears the saved panel arrangement. It takes effect the next time you open an editor window.") {
                Toggle("Restore the panel layout when the app launches", isOn: $restoreLayout)
                Button("Reset Workspace Layout to Default\u{2026}") {
                    AppState.clearSavedLayout()
                }
                .buttonStyle(.exp(.secondary))
                .accessibilityHint("Forgets the saved panel arrangement, column widths, and window mode.")
            }
        }
    }
}

private struct CanvasSettingsPane: View {
    @AppStorage(AppPreferences.smartGuides) private var smartGuides =
        AppPreferences.defaultSmartGuides
    @AppStorage(AppPreferences.showSelectionBounds) private var showSelectionBounds =
        AppPreferences.defaultShowSelectionBounds
    @AppStorage(AppPreferences.snapToGrid) private var snapToGrid =
        AppPreferences.defaultSnapToGrid
    @AppStorage(AppPreferences.gridSize) private var gridSize =
        AppPreferences.defaultGridSize
    @AppStorage(AppPreferences.gridSubdivisions) private var gridSubdivisions =
        AppPreferences.defaultGridSubdivisions
    @AppStorage(AppPreferences.performanceMode) private var performanceModeRaw =
        AppPreferences.defaultPerformanceMode

    /// Typed bridge over the stored raw string (falls back to Balanced).
    private var performanceMode: Binding<AppState.CanvasPerformanceMode> {
        Binding(
            get: { AppState.CanvasPerformanceMode(rawValue: performanceModeRaw) ?? .balanced },
            set: { performanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("Performance",
                          footnote: "Speed focus always uses the fastest drawing while you pan and move things. Design detail keeps blend modes and transparency true to their final look while you drag — as long as the document stays quick enough. Balanced switches automatically.") {
                LabeledContent("While editing, favor") {
                    EXPSegmented(selection: performanceMode, segments:
                        AppState.CanvasPerformanceMode.allCases.map {
                            .init(value: $0, label: $0.label)
                        })
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Canvas performance focus")
                .accessibilityHint("Chooses whether moving and panning favor speed or faithful blend-mode rendering.")
            }

            SettingsGroup("Guides & Selection",
                          footnote: "These set the defaults for new windows. The View menu still toggles them per window.") {
                Toggle("Smart guides (snap to other elements\u{2019} edges & centres)", isOn: $smartGuides)
                Toggle("Show the selection bounding box on shapes", isOn: $showSelectionBounds)
            }

            SettingsGroup("Grid") {
                Toggle("Snap to grid by default", isOn: $snapToGrid)

                LabeledContent("Grid size") {
                    HStack(spacing: 8) {
                        Slider(value: $gridSize, in: 5...200, step: 5)
                            .frame(maxWidth: 220)
                        Text("\(Int(gridSize)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                Stepper("Subdivisions per cell: \(gridSubdivisions)",
                        value: $gridSubdivisions, in: 1...10)
            }
        }
    }
}

/// The future home of the design-token system. The colour / spacing editors are
/// still to come (kept honest — no dead controls), but the TYPE side has its first
/// real foothold: the text-box-trim default, backed by the `TextMetrics` helper so
/// the live schematic below is drawn from actual Core Text metrics, not a mock.
private struct DesignTokensSettingsPane: View {
    @AppStorage(AppPreferences.textBoxTrim) private var textBoxTrim =
        AppPreferences.defaultTextBoxTrim
    @AppStorage(AppPreferences.accentOverride) private var accentOverride = ""

    private var trimToOptical: Bool { textBoxTrim == "capBaseline" }

    /// On = follow the macOS accent (clears the override); off = pin a colour.
    private var followSystemBinding: Binding<Bool> {
        Binding(get: { accentOverride.isEmpty },
                set: { on in accentOverride = on ? "" : hexString(Color(nsColor: .controlAccentColor)) })
    }
    private var accentBinding: Binding<Color> {
        Binding(get: {
            if let ns = EXPColor.hexColor(accentOverride) { return Color(nsColor: ns) }
            return Color(nsColor: .controlAccentColor)
        }, set: { accentOverride = hexString($0) })
    }
    private func hexString(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .controlAccentColor
        return String(format: "#%02X%02X%02X",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("Accent",
                          footnote: "EXP follows your macOS accent by default. Override it to pin an app-specific accent \u{2014} it drives selection, the active tool, focus rings, and primary buttons. (Applies as windows redraw.)") {
                Toggle("Follow system accent", isOn: followSystemBinding)
                if !accentOverride.isEmpty {
                    ColorPicker("App accent", selection: accentBinding, supportsOpacity: false)
                    Button("Reset to system accent") { accentOverride = "" }
                        .buttonStyle(.exp(.secondary))
                }
            }

            SettingsGroup("Type \u{2014} text box trim",
                          footnote: "Measures interface text from an optical box instead of the font\u{2019}s line box, so padding reads evenly across typefaces (CSS text-box-trim / Figma vertical trim). Sets the default for type tokens once they ship.") {
                Picker("Trim type text to", selection: $textBoxTrim) {
                    Text("Cap height \u{2192} baseline (recommended)").tag("capBaseline")
                    Text("Ascender \u{2192} descender (full line box)").tag("ascentDescent")
                }
                .pickerStyle(.radioGroup)

                TextTrimSchematic(trimToOptical: trimToOptical)
                    .frame(height: 104)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Diagram of the \(trimToOptical ? "cap height to baseline" : "ascender to descender") text box")
            }
        }
    }
}

/// A metric-accurate little diagram: it reads the system font\u{2019}s real ascent,
/// cap height, baseline, and descent via `FontMetrics` and shades the box the
/// current trim setting keeps. Proves the helper works and shows what trim does.
private struct TextTrimSchematic: View {
    let trimToOptical: Bool

    var body: some View {
        Canvas { ctx, size in
            let font = NSFont.systemFont(ofSize: 64, weight: .semibold)
            let m = FontMetrics(font)
            let pad: CGFloat = 16
            let spanTop = m.ascent
            let spanBot = -m.descent
            let usable = max(1, size.height - pad * 2)
            // Map a baseline-relative (y-up) value to a view y (top-down).
            func y(_ rel: CGFloat) -> CGFloat {
                let t = (spanTop - rel) / (spanTop - spanBot)
                return pad + t * usable
            }
            let left: CGFloat = 14
            let right = size.width - 14

            // Shaded band for the kept box.
            let topEdge = trimToOptical ? m.capHeight : m.ascent
            let botEdge = trimToOptical ? 0 : -m.descent
            let band = CGRect(x: left, y: y(topEdge), width: right - left, height: y(botEdge) - y(topEdge))
            ctx.fill(Path(roundedRect: band, cornerRadius: 3),
                     with: .color(.accentColor.opacity(0.18)))

            func line(_ rel: CGFloat, _ label: String, strong: Bool) {
                var path = Path()
                path.move(to: CGPoint(x: left, y: y(rel)))
                path.addLine(to: CGPoint(x: right, y: y(rel)))
                let shade = Color(nsColor: strong ? .secondaryLabelColor : .tertiaryLabelColor)
                ctx.stroke(path, with: .color(shade),
                           style: StrokeStyle(lineWidth: 1, dash: strong ? [] : [3, 3]))
                ctx.draw(Text(label).font(.caption2)
                            .foregroundStyle(EXPColor.textSecondary),
                         at: CGPoint(x: right - 2, y: y(rel) - 8), anchor: .topTrailing)
            }
            line(m.ascent, "ascender", strong: false)
            line(m.capHeight, "cap height", strong: true)
            line(0, "baseline", strong: true)
            line(-m.descent, "descender", strong: false)
        }
        .background(EXPColor.surfaceField,
                    in: RoundedRectangle(cornerRadius: EXPMetric.radiusRow))
    }
}

private struct AboutSettingsPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "\u{2014}"
        let build = info?["CFBundleVersion"] as? String ?? "\u{2014}"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("EXP") {
                Text("A native macOS design tool built around an actual UX workflow.")
                Text("The tool should get out of the way.")
                    .italic()
                    .foregroundStyle(.secondary)
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    SettingsWindow()
}
