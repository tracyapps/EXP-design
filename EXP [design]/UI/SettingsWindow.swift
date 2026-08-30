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
import AppKit

// MARK: - Shared preference keys (the single source of truth for both sides)

/// App-wide preference keys + their defaults. Shared by the Settings screen
/// (which writes them) and `AppState` (which reads them when a window opens), so
/// the two never drift. Defaults here MUST match the literals AppState falls back
/// to, so an unset key behaves exactly like today.
enum AppPreferences {
    static let smartGuides         = "exp.pref.smartGuides"          // Bool, default true
    static let showSelectionBounds = "exp.pref.showSelectionBounds"  // Bool, default true
    static let autoSelectLayers    = "exp.pref.autoSelectLayers"     // Bool, default true
    static let snapToGrid          = "exp.pref.snapToGrid"           // Bool, default false
    static let pixelSnap           = "exp.pref.pixelSnap"            // Bool, default true
    static let gridSize            = "exp.pref.gridSize"             // Double (points), default 50
    static let gridSubdivisions    = "exp.pref.gridSubdivisions"     // Int, default 2
    static let restoreLayout       = "exp.pref.restoreLayout"        // Bool, default true
    static let textBoxTrim         = "exp.pref.textBoxTrim"          // String, default "capBaseline"
    static let sourceBackdrop      = "exp.pref.sourceBackdrop"       // String (CanvasBackdrop raw), default "light"
    static let accentOverride      = "exp.pref.accentOverride"      // String "#RRGGBB"; ABSENT = follow macOS system accent (default)
    static let performanceMode     = "exp.pref.performanceMode"     // String (CanvasPerformanceMode raw), default "balanced"
    static let statesBarCompact    = "exp.pref.statesBarCompact"    // Bool, default false (extended chip row)
    static let artboardSpacing     = "exp.pref.artboardSpacing"     // Double (points), default 160
    static let pencilFidelity      = "exp.pref.pencilFidelity"      // Double (points of allowed deviation), default 2
    static let requestedSettingsPane = "exp.settings.requestedPane" // String (SettingsPane raw); "" = none. Lets a window jump Settings to a pane.
    static let interfaceTypeSize    = "exp.pref.interfaceTypeSize"  // EXPInterfaceTypeSize raw value
    static let tooltipVerbosity     = "exp.pref.tooltipVerbosity"   // EXPTooltipVerbosity raw value

    // Defaults (kept next to the keys so AppState and Settings agree).
    static let defaultSmartGuides         = true
    static let defaultShowSelectionBounds = true
    static let defaultAutoSelectLayers    = true
    static let defaultSnapToGrid          = false
    static let defaultPixelSnap           = true
    static let defaultGridSize: Double    = 50
    static let defaultGridSubdivisions    = 2
    static let defaultRestoreLayout       = true
    static let defaultTextBoxTrim         = "capBaseline"
    static let defaultPerformanceMode     = "balanced"
    static let defaultArtboardSpacing: Double = 160
    static let defaultPencilFidelity: Double = 2
    static let defaultInterfaceTypeSize = EXPInterfaceTypeSize.standard.rawValue
    static let defaultTooltipVerbosity = EXPTooltipVerbosity.full.rawValue
}

/// User-controlled chrome type size. This rides SwiftUI's Dynamic Type
/// environment so system accessibility sizing and the app preference compose.
enum EXPInterfaceTypeSize: String, CaseIterable, Identifiable {
    case compact, standard, large
    var id: String { rawValue }
    var label: String {
        switch self { case .compact: "Compact"; case .standard: "Standard"; case .large: "Large" }
    }
    var dynamicTypeSize: DynamicTypeSize {
        switch self { case .compact: .medium; case .standard: .large; case .large: .xxLarge }
    }
}

/// Hover-help density. Shorter levels never alter accessible names or the full
/// VoiceOver hint; Option-hover temporarily reveals the complete explanation.
enum EXPTooltipVerbosity: String, CaseIterable, Identifiable {
    case full, standard, minimal
    var id: String { rawValue }
    var label: String {
        switch self { case .full: "Full"; case .standard: "Standard"; case .minimal: "Minimal" }
    }
}

extension AppPreferences {
    /// Gap left between artboards when a new board is added and when Clean Up
    /// re-flows a page. Read straight from UserDefaults so AppKit callers
    /// (CanvasNSView) and `@AppStorage` views can never disagree about the value.
    static var artboardSpacingValue: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: artboardSpacing) as? Double
                ?? defaultArtboardSpacing)
    }

    /// How far, in document points, a fitted pencil curve may stray from the stroke
    /// the designer actually drew. Small = accurate, more anchors; large = smooth,
    /// fewer anchors. Read straight from UserDefaults so the canvas (AppKit) and
    /// `@AppStorage` views can never disagree — the same pattern as artboard spacing.
    static var pencilFidelityValue: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: pencilFidelity) as? Double
                ?? defaultPencilFidelity)
    }
}

// MARK: - Pane catalogue (add a case + a view to grow Settings)

private enum SettingsScope { case app, document }

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, canvas, sanaa, designTokens, about   // app-wide
    case designLanguage                          // document-specific
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:        return "General"
        case .canvas:         return "Canvas"
        case .sanaa:          return "Sanaa"
        case .designTokens:   return "Design Tokens"
        case .about:          return "About"
        case .designLanguage: return "Design Language"
        }
    }

    /// SF Symbol for the sidebar row.
    var symbol: String {
        switch self {
        case .general:        return "gearshape"
        case .canvas:         return "squareshape.dashed.squareshape"
        case .sanaa:          return "hand.draw"
        case .designTokens:   return "textformat"
        case .about:          return "info.circle"
        case .designLanguage: return "swatchpalette"
        }
    }

    /// App-wide preferences vs. the frontmost document's own data.
    var scope: SettingsScope {
        switch self {
        case .designLanguage: return .document
        default:              return .app
        }
    }

    static var appPanes: [SettingsPane]      { allCases.filter { $0.scope == .app } }
    static var documentPanes: [SettingsPane] { allCases.filter { $0.scope == .document } }
}

// MARK: - Window

struct SettingsWindow: View {
    // Optional because `List(selection:)` single-selection binds an optional;
    // nil is treated as General so the detail pane is never blank.
    @State private var pane: SettingsPane? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage(AppPreferences.requestedSettingsPane) private var requestedPaneRaw = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $pane) {
                Section("App") {
                    ForEach(SettingsPane.appPanes) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                Section("Document") {
                    ForEach(SettingsPane.documentPanes) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailContainer
            .navigationTitle((pane ?? .general).title)
        }
        // Roomy default so panes have space to grow into; the user can resize.
        .frame(minWidth: 720, idealWidth: 820, minHeight: 460, idealHeight: 560)
        .expInterfaceTypeSize()
        // Another window (e.g. the Design Language panel) can request a pane by
        // writing this key; jump to it whether Settings was just opened or is open.
        .onAppear { applyRequestedPane() }
        .onChange(of: requestedPaneRaw) { _, _ in applyRequestedPane() }
        .onChange(of: columnVisibility) { _, visibility in
            if visibility != .all { columnVisibility = .all }
        }
    }

    private func applyRequestedPane() {
        guard !requestedPaneRaw.isEmpty else { return }
        if let p = SettingsPane(rawValue: requestedPaneRaw) { pane = p }
        requestedPaneRaw = ""
    }

    @ViewBuilder private var detail: some View {
        switch pane ?? .general {
        case .general:      GeneralSettingsPane()
        case .canvas:       CanvasSettingsPane()
        case .sanaa:        SanaaSettingsPane()
        case .designTokens: DesignTokensSettingsPane()
        case .about:        AboutSettingsPane()
        case .designLanguage: DesignLanguageSettingsPane()
        }
    }

    @ViewBuilder private var detailContainer: some View {
        if (pane ?? .general) == .about {
            VStack {
                Spacer(minLength: 0)
                detail
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            }
        } else {
            ScrollView {
                detail
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Panes

/// A titled block of related controls — keeps every pane visually consistent and
/// is the unit a future design token can restyle once.
struct SettingsGroup<Content: View>: View {
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
    @AppStorage(AppPreferences.interfaceTypeSize) private var interfaceTypeSizeRaw =
        AppPreferences.defaultInterfaceTypeSize
    @AppStorage(AppPreferences.tooltipVerbosity) private var tooltipVerbosityRaw =
        AppPreferences.defaultTooltipVerbosity

    private var interfaceTypeSize: Binding<EXPInterfaceTypeSize> {
        Binding(get: { EXPInterfaceTypeSize(rawValue: interfaceTypeSizeRaw) ?? .standard },
                set: { interfaceTypeSizeRaw = $0.rawValue })
    }
    private var tooltipVerbosity: Binding<EXPTooltipVerbosity> {
        Binding(get: { EXPTooltipVerbosity(rawValue: tooltipVerbosityRaw) ?? .full },
                set: { tooltipVerbosityRaw = $0.rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("Interface",
                          footnote: "Tooltip detail only changes the hover bubble. Accessible names and full VoiceOver hints always remain available; hold Option while hovering to temporarily show the full explanation.") {
                LabeledContent("Interface type size") {
                    Picker("Interface type size", selection: interfaceTypeSize) {
                        ForEach(EXPInterfaceTypeSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .labelsHidden()
                }
                LabeledContent("Tooltip detail") {
                    Picker("Tooltip detail", selection: tooltipVerbosity) {
                        ForEach(EXPTooltipVerbosity.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .labelsHidden()
                }
            }

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
    @AppStorage(AppPreferences.autoSelectLayers) private var autoSelectLayers =
        AppPreferences.defaultAutoSelectLayers
    @AppStorage(AppPreferences.snapToGrid) private var snapToGrid =
        AppPreferences.defaultSnapToGrid
    @AppStorage(AppPreferences.pixelSnap) private var pixelSnap =
        AppPreferences.defaultPixelSnap
    @AppStorage(AppPreferences.gridSize) private var gridSize =
        AppPreferences.defaultGridSize
    @AppStorage(AppPreferences.gridSubdivisions) private var gridSubdivisions =
        AppPreferences.defaultGridSubdivisions
    @AppStorage(AppPreferences.performanceMode) private var performanceModeRaw =
        AppPreferences.defaultPerformanceMode
    @AppStorage(AppPreferences.artboardSpacing) private var artboardSpacing =
        AppPreferences.defaultArtboardSpacing
    @AppStorage(AppPreferences.pencilFidelity) private var pencilFidelity =
        AppPreferences.defaultPencilFidelity

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
                Toggle("Automatically select the layer clicked on the canvas", isOn: $autoSelectLayers)
            }

            SettingsGroup("Artboards",
                          footnote: "The gap left beside a new artboard, and the spacing Arrange \u{25B8} Artboards \u{25B8} Clean Up uses when it tidies a page.") {
                LabeledContent("Spacing between artboards") {
                    HStack(spacing: 8) {
                        Slider(value: $artboardSpacing, in: 40...400, step: 10)
                            .frame(maxWidth: 220)
                        Text("\(Int(artboardSpacing)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Spacing between artboards")
                .accessibilityValue("\(Int(artboardSpacing)) points")
            }

            SettingsGroup("Grid") {
                Toggle("Snap to grid by default", isOn: $snapToGrid)

                // BUG-036(b): separate from grid snapping on purpose. Grid snapping
                // pulls to grid lines, layout-grid columns and guides; this one only
                // decides whether drags land on whole points. Folding them together
                // would mean losing guide snapping just to drag by a half point.
                Toggle("Snap to whole pixels by default", isOn: $pixelSnap)

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

            // FEAT-029. This is the one control that decides whether a freehand tool
            // is usable, so it gets a real home rather than a hidden default. The
            // number is how far, in document points, the fitted curve may stray from
            // what was drawn — stated in the footnote because "fidelity" alone tells
            // a designer nothing about which direction is which.
            SettingsGroup("Pencil",
                          footnote: "Lower values follow your stroke closely and leave more anchor points to edit. Higher values smooth the stroke into fewer points. This affects new strokes only \u{2014} paths you have already drawn are ordinary paths and never change.") {
                LabeledContent("Fidelity") {
                    HStack(spacing: 8) {
                        Text("Accurate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Slider(value: $pencilFidelity, in: 0.5...10, step: 0.5)
                            .frame(maxWidth: 180)
                            .accessibilityLabel("Pencil fidelity")
                            .accessibilityValue("\(pencilFidelity, specifier: "%.1f") points of allowed deviation")
                            .accessibilityHint("Lower follows your stroke closely with more points; higher smooths it into fewer points.")
                        Text("Smooth")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("\(pencilFidelity, specifier: "%.1f") pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// The future home of the design-token system. The colour / spacing editors are
/// still to come (kept honest — no dead controls), but the TYPE side has its first
/// real foothold: the text-box-trim default, backed by the `TextMetrics` helper so
/// the live schematic below is drawn from actual Core Text metrics, not a mock.
/// Sanaa's switches. This pane is the ONE Sanaa surface that exists while Sanaa
/// is off, because it has to be — it is where you turn it on. Nothing else
/// (menu items, canvas overlay, avatar) is installed until "Enable Sanaa" is on.
private struct SanaaSettingsPane: View {
    @AppStorage(SanaaPreferences.enabled) private var enabled = false
    @AppStorage(SanaaPreferences.writeEnabled) private var writeEnabled = false
    @AppStorage(AppPreferences.accentOverride) private var accentOverride = ""
    @State private var bridge = AgentBridgeController.shared
    @State private var activity = SanaaActivityController.shared
    @State private var setupKind = AgentSetupKind.claudeCode
    @State private var copiedSetup = false

    private enum AgentSetupKind: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case claudeDesktop = "Claude Desktop"
        case stdioJSON = "Other MCP app (JSON)"
        case helperPath = "Helper path"
        var id: Self { self }
    }

    private var effectiveAccent: Color {
        guard let override = EXPColor.hexColor(accentOverride) else {
            return Color(nsColor: .controlAccentColor)
        }
        return Color(nsColor: override)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("Conversation agent",
                          footnote: "Sanaa uses the supported local runtime shown here. EXP ships no language model or API key. Account and usage details come directly from that runtime and may be absent for providers that do not expose them.") {
                statusRow(title: activity.selectedAgent.name,
                          detail: conversationStatus,
                          symbol: "message.and.waveform")

                if let account = activity.account {
                    VStack(alignment: .leading, spacing: 4) {
                        if let email = account.email, !email.isEmpty {
                            settingsValue("Account", value: email)
                        }
                        settingsValue("Plan", value: accountPlan(account))
                        if let hostVersion = activity.hostVersion, !hostVersion.isEmpty {
                            settingsValue("Host", value: "Codex \(hostVersion)")
                        }
                    }
                }

                ForEach(activity.rateLimits) { limit in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(limitTitle(limit))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(EXPColor.textPrimary)
                        if let primary = limit.primary {
                            usageWindow(primary,
                                        label: limit.secondary == nil ? "Current window" : "Short window")
                        }
                        if let secondary = limit.secondary {
                            usageWindow(secondary, label: "Long window")
                        }
                        if let reached = limit.reachedType, !reached.isEmpty {
                            Label("Limit reached: \(reached)", systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EXPColor.surfaceField,
                                in: RoundedRectangle(cornerRadius: EXPMetric.radiusField,
                                                     style: .continuous))
                }

                if let usage = activity.usageSummary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Token activity")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(EXPColor.textPrimary)
                        if let tokens = usage.lifetimeTokens {
                            settingsValue("Lifetime", value: "\(tokens.formatted()) tokens")
                        }
                        if let date = usage.latestDate, let tokens = usage.latestTokens {
                            settingsValue(date, value: "\(tokens.formatted()) tokens")
                        }
                        if let streak = usage.currentStreakDays {
                            settingsValue("Current streak", value: "\(streak) days")
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button(activity.phase == .failed || activity.phase == .idle
                           ? "Reconnect" : "Refresh status") {
                        if activity.phase == .failed || activity.phase == .idle {
                            activity.reconnect()
                        } else {
                            activity.refreshAccountStatus()
                        }
                    }
                    .buttonStyle(.exp(.secondary))
                    .disabled(!enabled || activity.phase == .connecting)
                    .accessibilityHint("Refreshes connection, account, and available usage information")
                }
            }

            SettingsGroup("Canvas access",
                          footnote: "Off by default. EXP accepts connections only from your macOS user through a local socket; it opens no network port and sends no document data on its own. A connected agent processes requested content under that provider's privacy settings.") {
                Toggle("Allow local agent access", isOn: Binding(
                    get: { bridge.isEnabled },
                    set: { bridge.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .tint(effectiveAccent)
                .accessibilityHint("Starts or stops EXP's local canvas connection")

                statusRow(title: "Canvas bridge",
                          detail: canvasStatus,
                          symbol: "point.3.connected.trianglepath.dotted")

                ForEach(bridge.connectedClients) { client in
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(EXPColor.textSecondary)
                            .accessibilityHidden(true)
                        Text(client.displayName)
                            .foregroundStyle(EXPColor.textPrimary)
                        Spacer(minLength: 8)
                        Text(client.connectionCount == 1
                             ? "Connected" : "\(client.connectionCount) connections")
                            .font(.footnote)
                            .foregroundStyle(EXPColor.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if bridge.unidentifiedConnectionCount > 0 {
                    Text("\(bridge.unidentifiedConnectionCount) connection\(bridge.unidentifiedConnectionCount == 1 ? "" : "s") still identifying…")
                        .font(.footnote)
                        .foregroundStyle(EXPColor.textSecondary)
                }
            }

            SettingsGroup("Connect another canvas agent",
                          footnote: setupNote ?? "Copy this setup into the agent app you want to connect. The connection becomes visible above after that app starts EXP's helper.") {
                Picker("Setup for", selection: $setupKind) {
                    ForEach(AgentSetupKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                Text(setupText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(EXPColor.textSecondary)
                    .textSelection(.enabled)
                    .padding(EXPMetric.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EXPColor.surfaceField,
                                in: RoundedRectangle(cornerRadius: EXPMetric.radiusField))
                    .accessibilityLabel("Agent setup command")

                Button(copiedSetup ? "Copied" : "Copy setup") { copySetup() }
                    .buttonStyle(.exp(.secondary))
                    .accessibilityHint("Copies the selected local agent setup")
            }

            SettingsGroup("Sanaa",
                          footnote: "Sanaa is the design collaborator presented inside EXP. Conversation access and canvas access are separate: the first lets you chat, while the canvas switches decide whether an agent may inspect or change the frontmost document.") {
                Toggle("Enable Sanaa", isOn: $enabled)
                    .toggleStyle(.switch)
                    .tint(effectiveAccent)
                    .accessibilityHint("Shows Sanaa's controls in EXP. Off by default; with this off, EXP shows no trace of Sanaa anywhere.")

                Toggle("Allow Sanaa to draw", isOn: $writeEnabled)
                    .toggleStyle(.switch)
                    .tint(effectiveAccent)
                    .disabled(!enabled)
                    .accessibilityHint("Lets a connected agent add pages, artboards, and layers. Changing work already on the canvas asks you again, per document.")

                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(EXPColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsGroup("What drawing means",
                          footnote: "Each batch of changes arrives as ordinary layers you can select, edit, and export like anything you drew yourself, and lands as a single step in Edit \u{25B8} Undo named after what the agent said it was doing.") {
                Text("Creating new pages, artboards, and duplicates only needs the switches above. Changing what is already on your canvas asks you first, once per document, each time you open EXP.")
                    .font(.callout)
                    .foregroundStyle(EXPColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if enabled { activity.activate() }
        }
        // Turning Sanaa off must not leave a live permission behind for the next
        // time it is turned on.
        .onChange(of: enabled) { _, isOn in
            if !isOn {
                writeEnabled = false
                SanaaConsent.shared.forgetEverything()
                SanaaActivityController.shared.disable()
            }
            // Conditional floating trays stay saved but must open/close now,
            // without waiting for another panel mutation.
            PanelWindowManager.shared.reconcile()
        }
        .onChange(of: writeEnabled) { _, isOn in
            if !isOn { SanaaConsent.shared.forgetEverything() }
        }
    }

    private var statusLine: String {
        if !enabled { return "Sanaa is off. Nothing in EXP mentions it and the agent connection stays read-only." }
        if !writeEnabled { return "Sanaa is on and can read your document, but cannot change it." }
        return "Sanaa can add new work. Changes to what is already on your canvas still ask you, per document."
    }

    private var conversationStatus: String {
        switch activity.phase {
        case .off: return "Off"
        case .idle: return "Disconnected"
        case .connecting: return "Connecting…"
        case .ready: return "Connected and ready"
        case .replying: return "Connected — replying"
        case .stopping: return "Connected — stopping reply"
        case .failed: return activity.failureMessage ?? "Disconnected"
        }
    }

    private var canvasStatus: String {
        if let error = bridge.lastError { return "Unavailable — \(error)" }
        guard bridge.isEnabled, bridge.isRunning else { return "Off" }
        guard bridge.connectionCount > 0 else { return "Ready — no agent connected" }
        return bridge.connectionCount == 1
            ? "1 connection active · \(accessDescription)"
            : "\(bridge.connectionCount) connections active · \(accessDescription)"
    }

    private var accessDescription: String {
        enabled && writeEnabled ? "can read and draw" : "read only"
    }

    private var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/exp-mcp").path
    }

    private var setupText: String {
        switch setupKind {
        case .claudeCode:
            let escaped = helperPath.replacingOccurrences(of: "'", with: "'\\''")
            return "claude mcp add --scope user exp-design -- '\(escaped)'"
        case .claudeDesktop, .stdioJSON:
            let object: [String: Any] = [
                "mcpServers": ["exp-design": ["command": helperPath, "args": []]]
            ]
            guard let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
            ) else { return helperPath }
            return String(data: data, encoding: .utf8) ?? helperPath
        case .helperPath:
            return helperPath
        }
    }

    private var setupNote: String? {
        switch setupKind {
        case .claudeDesktop:
            return "Manual local-server configuration. Claude Desktop may also offer extension-based installation for packaged servers."
        case .stdioJSON:
            return "Use this with an MCP host that accepts a stdio server configuration."
        default:
            return nil
        }
    }

    private func statusRow(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(EXPColor.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(EXPColor.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(EXPColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func settingsValue(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).foregroundStyle(EXPColor.textSecondary)
            Spacer(minLength: 10)
            Text(value)
                .foregroundStyle(EXPColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }

    private func usageWindow(_ window: SanaaRuntimeUsageWindow,
                             label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer(minLength: 8)
                Text("\(Int(window.usedPercent.rounded()))% used")
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(EXPColor.textSecondary)
            ProgressView(value: window.usedPercent, total: 100)
                .tint(effectiveAccent)
            if let resetsAt = window.resetsAt {
                Text("Resets \(Date(timeIntervalSince1970: TimeInterval(resetsAt)), style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(EXPColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(Int(window.usedPercent.rounded())) percent used")
    }

    private func limitTitle(_ limit: SanaaRuntimeRateLimit) -> String {
        if let name = limit.name, !name.isEmpty, name != limit.limitID { return name }
        return limit.limitID == "codex" ? "Codex usage" : limit.limitID
    }

    private func accountPlan(_ account: SanaaRuntimeAccount) -> String {
        if let plan = account.planType, !plan.isEmpty { return plan.capitalized }
        switch account.type {
        case "apiKey": return "API key"
        case "chatgpt": return "ChatGPT"
        default: return account.type
        }
    }

    private func copySetup() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setupText, forType: .string)
        copiedSetup = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedSetup = false
        }
    }
}

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
    private let websiteURL = URL(string: "https://expdesign.app/")!
    private let reportingURL = URL(string: "https://expdesign.app/download#reporting")!

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

            SettingsGroup("Links") {
                Link(destination: websiteURL) {
                    Label("Website", systemImage: "globe")
                }
                Link(destination: reportingURL) {
                    Label("Bug report examples", systemImage: "ladybug")
                }
            }
        }
    }
}

#Preview {
    SettingsWindow()
}
