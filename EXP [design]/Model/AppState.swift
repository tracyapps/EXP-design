//
//  AppState.swift
//  EXP [design]
//
//  The shared *session* state for the editor: what's on screen and selected,
//  the camera, panel visibility. The persisted design data itself lives in
//  `document` (see Document.swift).
//
//  The split matters: Document is the file (Codable, saved to disk); AppState
//  is the view of it (camera, selection, panel layout) that does NOT get saved.
//  That separation is exactly what the native document system expects next
//  cycle — the Document becomes the file, AppState stays as scene/view state.
//
//  Think of this like a set of CSS custom properties scoped to :root — one
//  place every panel reads from and writes to, instead of each panel keeping
//  its own private copy. That matters for two locked decisions in the roadmap:
//   1. Floating/detachable panels (v2): a panel can only live on any monitor
//      without knowing where it's hosted if it talks to shared state.
//   2. The component system: instances reference a source held in the document.
//
//  `@Observable` is Apple's modern observation system: any SwiftUI view that
//  reads a property here automatically re-renders when it changes. Mutating the
//  `document` struct in place reassigns the property, so that counts too.
//  `@MainActor` keeps all access on the main thread (all UI is).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {

    // NOTE: the persisted design data lives in ExpDocument.model (the file).
    // AppState holds only per-window *view* state — camera, selection, panel
    // layout — none of which is saved.

    // MARK: Panel visibility (persisted as a workspace preference)
    var showLeftPanel = true { didSet { saveLayout() } }
    var showRightPanel = true { didSet { saveLayout() } }

    // MARK: Panel dock layout (Phase 13 — Photoshop-style docks)
    //
    // The arrangement of dockable panels (which panels, grouped into tabbed
    // groups, in which column). Session state for now; 13d makes named
    // workspaces saveable. Mutating `workspace` reassigns it, so @Observable
    // re-renders the docks.
    var workspace: Workspace = .default { didSet { saveLayout() } }

    // The Multi-Window tray arrangement is shared across documents — it lives in
    // `PanelHub.shared`, not here (so opening a second document doesn't spawn a
    // second set of panels).

    /// Which workspace MODE the editor is in. `single` = the compact, single
    /// window (panels are contextual stacked sections, hide when not applicable);
    /// `multiWindow` = the Photoshop-style mode where panels float as separate
    /// windows + tab groups and stay visible (de-emphasized) when not applicable.
    /// Single is the default; multi-window is built out in a later sub-phase.
    enum WorkspaceMode: String, CaseIterable, Sendable, Codable {
        case single, multiWindow
        var label: String { self == .single ? "Single Window" : "Multi-Window" }
        var icon: String { self == .single ? "macwindow" : "macwindow.on.rectangle" }
    }
    var workspaceMode: WorkspaceMode = .single { didSet { saveLayout() } }

    /// Drives the in-app feedback sheet (set by the Help ▸ Send Feedback menu).
    var showingFeedback = false

    init() {
        loadLayout()
        migrateNewPanels()
        // Seed without persisting — these reads are not user edits.
        applyingExternalPrefs = true
        applyAppPreferenceDefaults()
        applyingExternalPrefs = false
        // Live two-way sync: when Settings (or another window) changes a synced
        // default in UserDefaults, pull it into this window so the canvas + View
        // menu checkmarks stay in lockstep. Our own writes are guarded re-entrant.
        prefsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSyncedPrefs() }
        }
    }

    deinit {
        if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
    }

    /// Seed the per-window session toggles from the app-wide Settings defaults
    /// (see `AppPreferences`). Reading only when the key EXISTS means an unset
    /// preference leaves the inline default untouched — so behaviour is identical
    /// to before the Settings screen for anyone who never opens it. The caller wraps
    /// this in `applyingExternalPrefs = true`, so the synced properties' `didSet`
    /// hooks don't write the seeded values straight back to UserDefaults.
    private func applyAppPreferenceDefaults() {
        let d = UserDefaults.standard
        if d.object(forKey: AppPreferences.smartGuides) != nil {
            smartGuidesEnabled = d.bool(forKey: AppPreferences.smartGuides)
        }
        if d.object(forKey: AppPreferences.showSelectionBounds) != nil {
            showSelectionBounds = d.bool(forKey: AppPreferences.showSelectionBounds)
        }
        if d.object(forKey: AppPreferences.snapToGrid) != nil {
            snapToGrid = d.bool(forKey: AppPreferences.snapToGrid)
        }
        if let g = d.object(forKey: AppPreferences.gridSize) as? Double, g > 0 {
            gridSize = CGFloat(g)
        }
        if let s = d.object(forKey: AppPreferences.gridSubdivisions) as? Int, s > 0 {
            gridSubdivisions = s
        }
        if let raw = d.string(forKey: AppPreferences.sourceBackdrop),
           let bd = CanvasBackdrop(rawValue: raw) {
            sourceBackdrop = bd
        }
        if let raw = d.string(forKey: AppPreferences.performanceMode),
           let m = CanvasPerformanceMode(rawValue: raw) {
            performanceMode = m
        }
    }

    /// Forget the saved workspace layout (the Settings ▸ General reset button).
    /// Static because Settings is app-wide and has no `AppState` in scope; new
    /// windows then open with the default arrangement.
    static func clearSavedLayout() {
        UserDefaults.standard.removeObject(forKey: layoutKey)
    }

    // MARK: Synced preference plumbing
    //
    // The Settings-exposed toggles double as a per-window session value AND an
    // app-wide default. `didSet` on each writes to UserDefaults (window → Settings);
    // the UserDefaults observer installed in init reads them back (Settings →
    // window). `applyingExternalPrefs` breaks the loop in both directions.
    @ObservationIgnored private var applyingExternalPrefs = false
    @ObservationIgnored nonisolated(unsafe) private var prefsObserver: NSObjectProtocol?

    /// Persist a synced toggle — unless we're mid-apply from an external change.
    private func persistPref(_ key: String, _ value: Any) {
        guard !applyingExternalPrefs else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Pull any externally-changed synced prefs into this window. Assigns only on a
    /// real difference (so it never thrashes @Observable) and suppresses write-back
    /// while doing so.
    private func reloadSyncedPrefs() {
        applyingExternalPrefs = true
        defer { applyingExternalPrefs = false }
        let d = UserDefaults.standard
        if d.object(forKey: AppPreferences.smartGuides) != nil {
            let v = d.bool(forKey: AppPreferences.smartGuides)
            if v != smartGuidesEnabled { smartGuidesEnabled = v }
        }
        if d.object(forKey: AppPreferences.showSelectionBounds) != nil {
            let v = d.bool(forKey: AppPreferences.showSelectionBounds)
            if v != showSelectionBounds { showSelectionBounds = v }
        }
        if d.object(forKey: AppPreferences.snapToGrid) != nil {
            let v = d.bool(forKey: AppPreferences.snapToGrid)
            if v != snapToGrid { snapToGrid = v }
        }
        if let g = d.object(forKey: AppPreferences.gridSize) as? Double, g > 0 {
            let v = CGFloat(g)
            if v != gridSize { gridSize = v }
        }
        if let sub = d.object(forKey: AppPreferences.gridSubdivisions) as? Int, sub > 0 {
            if sub != gridSubdivisions { gridSubdivisions = sub }
        }
        if let raw = d.string(forKey: AppPreferences.sourceBackdrop),
           let bd = CanvasBackdrop(rawValue: raw), bd != sourceBackdrop {
            sourceBackdrop = bd
        }
        if let raw = d.string(forKey: AppPreferences.performanceMode),
           let m = CanvasPerformanceMode(rawValue: raw), m != performanceMode {
            performanceMode = m
        }
    }

    /// Record a dock column's actual on-screen width (the dock view reports it as
    /// the user drags the splitter) so it persists and restores next launch.
    func setColumnWidth(_ side: DockSide, _ width: CGFloat) {
        let w = min(600, max(160, width))
        switch side {
        case .left:  if abs(workspace.left.width - w) > 0.5 { workspace.left.width = w }
        case .right: if abs(workspace.right.width - w) > 0.5 { workspace.right.width = w }
        }
    }

    // MARK: Layout persistence (app-wide workspace preference, not document data)

    /// The slice of session state we remember between launches: panel arrangement
    /// (incl. collapse, weights, column widths), the workspace mode, and dock
    /// visibility. Stored in UserDefaults — it's a workspace preference, not part
    /// of the document file.
    private struct PersistedLayout: Codable {
        var workspace: Workspace
        var mode: WorkspaceMode
        var showLeft: Bool
        var showRight: Bool
    }

    private static let layoutKey = "exp.workspaceLayout.v1"
    private static let seenPanelsKey = "exp.panels.seen.v1"

    /// One-time reveal for newly-added panels. Any panel that has never been part
    /// of a layout before is added to the (single-window) dock once, so a new
    /// feature — e.g. the Design Language panel — isn't left unreachable behind a
    /// layout saved before it existed. Every panel is then marked "seen", so a
    /// panel the user later hides stays hidden. Multi-window trays are left alone
    /// (auto-opening a floating window would be intrusive); the Window menu reveals
    /// panels there on demand.
    private func migrateNewPanels() {
        let d = UserDefaults.standard
        let seen = Set(d.stringArray(forKey: Self.seenPanelsKey) ?? [])
        let known = seen.union(layoutPanels.map(\.rawValue))
        let missing = PanelID.allCases.filter { !known.contains($0.rawValue) }
        for pid in missing {
            withColumn(.right) { $0.groups.append(PanelGroup([pid])) }
        }
        d.set(PanelID.allCases.map(\.rawValue), forKey: Self.seenPanelsKey)
    }
    /// True only while applying a loaded layout, so the property `didSet`s don't
    /// immediately re-save what we just read.
    @ObservationIgnored private var restoringLayout = false

    private func saveLayout() {
        guard !restoringLayout else { return }
        let payload = PersistedLayout(workspace: workspace, mode: workspaceMode,
                                      showLeft: showLeftPanel, showRight: showRightPanel)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.layoutKey)
        }
    }

    private func loadLayout() {
        // App-wide opt-out (Settings ▸ General). Key absent = restore (the prior
        // behaviour); only an explicit `false` skips restoring.
        let prefs = UserDefaults.standard
        if prefs.object(forKey: AppPreferences.restoreLayout) != nil,
           prefs.bool(forKey: AppPreferences.restoreLayout) == false { return }
        guard let data = UserDefaults.standard.data(forKey: Self.layoutKey),
              let p = try? JSONDecoder().decode(PersistedLayout.self, from: data) else { return }
        restoringLayout = true
        workspace = p.workspace
        // Migration: bump a saved right column that's narrower than the current
        // default (the align/distribute row needs the extra width). Only nudges
        // up old/auto layouts; anyone who set it wider keeps their width.
        if workspace.right.width < Workspace.default.right.width {
            workspace.right.width = Workspace.default.right.width
        }
        workspaceMode = p.mode
        showLeftPanel = p.showLeft
        showRightPanel = p.showRight
        restoringLayout = false
    }

    /// The groups in one dock column, for the views to render.
    func dockGroups(_ side: DockSide) -> [PanelGroup] {
        side == .left ? workspace.left.groups : workspace.right.groups
    }

    /// Every distinct panel currently in the layout (both columns), in order —
    /// the set that multi-window mode floats into separate windows.
    var layoutPanels: [PanelID] {
        var seen = Set<PanelID>()
        var out: [PanelID] = []
        for g in workspace.left.groups + workspace.right.groups {
            for p in g.panels where !seen.contains(p) { seen.insert(p); out.append(p) }
        }
        return out
    }

    /// Mutate one column in place (the single write funnel for dock edits).
    private func withColumn(_ side: DockSide, _ body: (inout DockColumn) -> Void) {
        switch side {
        case .left:  body(&workspace.left)
        case .right: body(&workspace.right)
        }
    }

    /// Make `pid` the active tab of its group (and expand the group if collapsed).
    func setActivePanel(_ pid: PanelID, inGroup gid: UUID, side: DockSide) {
        withColumn(side) { col in
            guard let i = col.groups.firstIndex(where: { $0.id == gid }) else { return }
            col.groups[i].activeID = pid
            col.groups[i].collapsed = false
        }
    }

    /// Collapse/expand a group (Photoshop "minimize" to its header).
    func toggleGroupCollapsed(_ gid: UUID, side: DockSide) {
        withColumn(side) { col in
            guard let i = col.groups.firstIndex(where: { $0.id == gid }) else { return }
            col.groups[i].collapsed.toggle()
        }
    }

    /// Resize two adjacent expanded groups by dragging the divider between them.
    /// `deltaPoints` is the incremental drag (down = positive = grow the upper
    /// group); `pointsPerWeight` converts screen points into weight units (the
    /// dock view knows the current pixels-per-weight and passes it in).
    func adjustGroupHeights(side: DockSide, aboveID: UUID, belowID: UUID,
                            deltaPoints: CGFloat, pointsPerWeight: CGFloat) {
        guard pointsPerWeight > 0 else { return }
        let dW = deltaPoints / pointsPerWeight
        withColumn(side) { col in
            guard let ai = col.groups.firstIndex(where: { $0.id == aboveID }),
                  let bi = col.groups.firstIndex(where: { $0.id == belowID }) else { return }
            let minW: CGFloat = 0.12
            let total = col.groups[ai].weight + col.groups[bi].weight
            var a = col.groups[ai].weight + dW
            a = min(max(minW, a), total - minW)
            col.groups[ai].weight = a
            col.groups[bi].weight = total - a
        }
    }

    /// Reset the dock layout to the default arrangement.
    func resetWorkspace() { workspace = .default }

    /// Move a group to a column, inserting before `targetID` (or appending when
    /// nil). Removes it from whichever column currently holds it — so this both
    /// reorders within a column and moves a panel across columns.
    func moveGroup(_ gid: UUID, toSide: DockSide, before targetID: UUID?) {
        guard gid != targetID else { return }
        var moved: PanelGroup?
        for side in [DockSide.left, .right] {
            withColumn(side) { col in
                if let i = col.groups.firstIndex(where: { $0.id == gid }) { moved = col.groups.remove(at: i) }
            }
            if moved != nil { break }
        }
        guard let group = moved else { return }
        withColumn(toSide) { col in
            if let t = targetID, let ti = col.groups.firstIndex(where: { $0.id == t }) {
                col.groups.insert(group, at: ti)
            } else {
                col.groups.append(group)
            }
        }
    }

    /// Whether a panel currently lives somewhere in the layout (either column).
    func isPanelVisible(_ id: PanelID) -> Bool {
        (workspace.left.groups + workspace.right.groups).contains { $0.panels.contains(id) }
    }

    /// Whether a panel is currently part of the active layout — the shared trays
    /// in Multi-Window, this window's dock columns in Single-Window. Used for the
    /// Window menu's checkmarks + toggling.
    func isPanelShown(_ id: PanelID) -> Bool {
        workspaceMode == .multiWindow
            ? PanelHub.shared.isPanelInTrays(id)
            : isPanelVisible(id)
    }

    /// Show/hide a panel, acting on whichever mode is active: this window's dock
    /// in Single-Window, or the shared trays in Multi-Window.
    func togglePanel(_ id: PanelID) {
        if workspaceMode == .multiWindow {
            PanelHub.shared.togglePanel(id)
            return
        }
        if isPanelVisible(id) {
            for side in [DockSide.left, .right] {
                withColumn(side) { col in
                    for i in col.groups.indices { col.groups[i].panels.removeAll { $0 == id } }
                    col.groups.removeAll { $0.panels.isEmpty }
                    for i in col.groups.indices where !col.groups[i].panels.contains(col.groups[i].activeID) {
                        col.groups[i].activeID = col.groups[i].panels.first ?? col.groups[i].activeID
                    }
                }
            }
        } else {
            withColumn(.right) { $0.groups.append(PanelGroup([id])) }
        }
    }

    /// Reveal a closed panel (Window-menu): adds it to the shared trays.
    func ensurePanelTray(_ panel: PanelID) { PanelHub.shared.ensurePanelTray(panel) }

    // MARK: Camera (the viewport into the document)
    //
    // The canvas maps a document point to a view point with:
    //     viewPoint = documentPoint * zoom + panOffset
    // which is exactly CSS `transform: translate(panOffset) scale(zoom)`.
    var zoom: CGFloat = 1.0
    var panOffset: CGPoint = .zero      // in view points

    let minZoom: CGFloat = 0.05         // 5%
    let maxZoom: CGFloat = 256.0        // 25600% — close-in pixel/anchor work

    func clampZoom(_ z: CGFloat) -> CGFloat {
        min(max(z, minZoom), maxZoom)
    }

    /// The canvas reports its current pixel size here (set on layout) so zoom
    /// commands from the Inspector can keep the viewport CENTER fixed.
    var viewportSize: CGSize = .zero

    /// Zoom to an absolute factor, keeping the doc point under the viewport
    /// center fixed (so the content doesn't jump when you type a %).
    func zoomTo(_ newZoom: CGFloat) {
        let z = clampZoom(newZoom)
        guard zoom > 0 else { zoom = z; return }
        let c = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let docC = CGPoint(x: (c.x - panOffset.x) / zoom, y: (c.y - panOffset.y) / zoom)
        panOffset = CGPoint(x: c.x - docC.x * z, y: c.y - docC.y * z)
        zoom = z
    }

    func zoomIn()     { zoomTo(zoom * 1.25) }
    func zoomOut()    { zoomTo(zoom / 1.25) }
    func zoomActual() { zoomTo(1) }

    /// Center the viewport on a specific document-space rectangle, keeping the
    /// current zoom level (just pans; doesn't fit/zoom).
    func centerOn(_ rect: CGRect) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let docCenter = CGPoint(x: rect.midX, y: rect.midY)
        let viewCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        panOffset = CGPoint(x: viewCenter.x - docCenter.x * zoom,
                           y: viewCenter.y - docCenter.y * zoom)
    }

    // MARK: Active tool (session state — not saved)

    /// What a click-drag on the canvas does. Defaults to Select.
    var tool: Tool = .select

    /// Side count used when drawing a NEW polygon (default 3 = triangle). Editing a
    /// polygon's Sides in the Inspector updates this so the next one matches.
    var polygonSides: Int = 3

    /// What align operations measure against: the selection's own bounding box, or
    /// the artboard the selection sits in (Illustrator-style "Align to"). Session
    /// state — not saved. Distribute always uses the selection span.
    enum AlignTarget: String, CaseIterable { case selection, artboard }
    var alignTarget: AlignTarget = .selection

    /// Developer "Testing Mode" — when on, the canvas logs lightweight perf stats
    /// (frame time, nodes drawn vs culled, instance-cache hit rate, snap cost) to
    /// the Xcode console ~twice a second. Session state, OFF by default and never
    /// persisted, so it adds zero overhead to normal use until explicitly enabled
    /// (View ▸ Testing Mode, ⌃⌘T).
    var testingMode = false

    /// Rulers + guides display (session state — not saved; the guides themselves
    /// live in the document).
    var showRulers = true
    var showGuides = true
    var guidesLocked = false

    /// Uniform (Photoshop-style) square grid — a workspace preference, session state.
    /// Layout grids are different: those are per-artboard and live in the document.
    var showGrid = false
    var snapToGrid = false { didSet { persistPref(AppPreferences.snapToGrid, snapToGrid) } }
    var gridSize: CGFloat = 50 { didSet { persistPref(AppPreferences.gridSize, Double(gridSize)) } }   // major spacing in points
    var gridSubdivisions: Int = 2 { didSet { persistPref(AppPreferences.gridSubdivisions, gridSubdivisions) } }   // minor lines per major cell

    /// Smart guides: snap to other elements' edges/centers and show alignment
    /// lines (Figma/XD-style). Enabled by default.
    var smartGuidesEnabled = true { didSet { persistPref(AppPreferences.smartGuides, smartGuidesEnabled) } }

    /// Whether the selection bounding-box outline is drawn for box shapes.
    /// (Paths never draw a box — they trace their outline instead.) Settings now
    /// owns the DEFAULT (two-way synced); the View menu still toggles it per window.
    var showSelectionBounds: Bool = true { didSet { persistPref(AppPreferences.showSelectionBounds, showSelectionBounds) } }

    /// Backdrop shade drawn BEHIND the component in the source-editor canvas. This
    /// is a pure VIEW setting (like Photoshop's canvas colour) — it never touches
    /// the element's own background; it only supplies contrast so a white (or black)
    /// component stays visible while you edit. Persisted as a workspace preference.
    enum CanvasBackdrop: String, CaseIterable, Identifiable, Sendable {
        case light, grey, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .light: return "Light"
            case .grey:  return "Grey"
            case .dark:  return "Dark"
            }
        }
        /// Grayscale value (0…1) used for both the canvas fill and the UI swatch, so
        /// the picker preview always matches what the canvas shows. (AppState avoids
        /// importing AppKit; the canvas builds its NSColor from this.)
        var white: CGFloat {
            switch self {
            case .light: return 1.0
            case .grey:  return 0.50
            case .dark:  return 0.17
            }
        }
        var color: Color { Color(white: white) }
    }
    var sourceBackdrop: CanvasBackdrop = .light {
        didSet { persistPref(AppPreferences.sourceBackdrop, sourceBackdrop.rawValue) }
    }

    /// The user's canvas performance stance (Settings ▸ Canvas ▸ Performance) —
    /// one friendly dial instead of raw thresholds, because every designer
    /// weighs speed vs. fidelity differently. Each case carries the tuning the
    /// canvas reads: how expensive a document may be before a blend-mode drag
    /// falls back from TRUE live compositing to the fast snapshot path, how
    /// much extra pan snapshot is captured around the viewport, and how quickly
    /// the full-quality settle render fires after motion stops.
    enum CanvasPerformanceMode: String, CaseIterable, Identifiable, Sendable {
        case speed, balanced, detail
        var id: String { rawValue }
        var label: String {
            switch self {
            case .speed:    return "Speed focus"
            case .balanced: return "Balanced"
            case .detail:   return "Detail focus"
            }
        }
        /// Max recent full-frame cost (ms) at which a drag whose moving content
        /// uses blend modes keeps TRUE live compositing (full render per tick)
        /// instead of the fast snapshot composite. 0 = never (always fast).
        var trueDragBudgetMs: Double {
            switch self {
            case .speed:    return 0
            case .balanced: return 18   // ~55fps still achievable live
            case .detail:   return 40   // accept ~25fps for correct compositing
            }
        }
        /// Pan-snapshot halo — extra viewport fraction captured on every side
        /// (bigger = fewer blank-edge recaptures, costlier captures).
        var panHaloFraction: CGFloat {
            switch self {
            case .speed:    return 0.15
            case .balanced: return 0.25
            case .detail:   return 0.40
            }
        }
        /// Delay after the last pan/zoom tick before the settle render.
        var settleDelay: TimeInterval {
            switch self {
            case .speed:    return 0.12
            case .balanced: return 0.08
            case .detail:   return 0.05
            }
        }
    }
    var performanceMode: CanvasPerformanceMode = .balanced {
        didSet { persistPref(AppPreferences.performanceMode, performanceMode.rawValue) }
    }

    // MARK: Selection (session state — not saved)

    /// Which artboards are selected. A set so multiple boards can move, export,
    /// or duplicate together. Resolving ids to actual Artboards happens where the
    /// document is in scope (the Inspector, the canvas).
    var selectedArtboardIDs: Set<UUID> = []

    /// Compatibility accessor for the many single-artboard call sites. Reading
    /// returns the lone selected board (nil when zero or many); writing replaces
    /// the whole set with that one id (or clears it for nil). Multi-select code
    /// reads/writes `selectedArtboardIDs` directly.
    var selectedArtboardID: UUID? {
        get { selectedArtboardIDs.count == 1 ? selectedArtboardIDs.first : nil }
        set { selectedArtboardIDs = newValue.map { [$0] } ?? [] }
    }

    /// Which shapes (nodes) are selected. A set, so we support marquee +
    /// shift-click multi-selection. Empty = nothing selected.
    var selectedNodeIDs: Set<UUID> = []

    /// Convenience: the single selected node id, or nil when zero or many are
    /// selected (the Inspector shows editable fields only for a single shape).
    var singleSelectedNodeID: UUID? {
        selectedNodeIDs.count == 1 ? selectedNodeIDs.first : nil
    }

    /// The "anchor" for Shift-range selection in the Layers panel — the last row
    /// clicked without Shift. A Shift-click selects everything between it and the
    /// clicked row.
    var selectionAnchorID: UUID?

    /// The layer "style" captured by Copy Style — effects + blend mode + opacity —
    /// ready for Paste Style onto one or many other layers. Session-only (not saved
    /// with the file) and shared by the canvas and the Layers panel, so either
    /// surface can copy and the other can paste. nil = nothing copied yet, which is
    /// what keeps Paste Style disabled.
    var copiedLayerStyle: LayerStyle?

    // MARK: Artboard notes (session UI — the notes text itself lives on Artboard)

    /// Which artboards currently have their notes panel open (ephemeral).
    var openNotesArtboardIDs: Set<UUID> = []

    /// Manual size of each board's notes panel, so a resize sticks across
    /// close/open within the session (ephemeral — not saved to the file).
    var notesPanelSize: [UUID: CGSize] = [:]

    // MARK: Text styling channel (Inspector ⇄ active text editor)

    /// A style change requested by the Inspector. The canvas applies it to the
    /// active editor's selection (while editing) or the whole text node.
    enum TextStyleOp: Equatable {
        case fontName(String)     // PostScript face ("" = system)
        case fontSize(CGFloat)
        case color(RGBAColor)
        case paragraph            // re-sync align / line-height / spacing into the editor
    }

    /// A direct, synchronous hook the active text editor installs while editing.
    /// The Inspector calls it from its control handlers so a style change is applied
    /// to the editor immediately (no async round-trip through the view update, which
    /// was dropping changes and racing the commit). `@ObservationIgnored` so setting
    /// it never invalidates any view. nil = no text box is being edited.
    @ObservationIgnored var applyTextStyle: ((TextStyleOp) -> Void)?

    /// The document's Layers panel registers this so the View menu can expand
    /// (true) or collapse (false) all groups + sections. `@ObservationIgnored` —
    /// a closure hook, like `applyTextStyle`.
    @ObservationIgnored var layersExpandAll: ((Bool) -> Void)?

    /// The canvas publishes the current text selection's style here so the
    /// Inspector reflects it. nil component = "Multiple"/mixed across the selection.
    struct TextSelectionStyle: Equatable {
        var fontName: String?
        var fontSize: CGFloat?
        var color: RGBAColor?
        var bold: Bool?
        var italic: Bool?
        var underline: Bool?
    }
    /// Non-nil only while a text node is being edited inline.
    var textSelection: TextSelectionStyle?

    // MARK: Point-selection channel (Inspector ⇄ node tool)

    /// How many path points the node tool currently has multi-selected on the
    /// canvas. Session state — the Inspector uses it to decide whether to show
    /// the point-rotation field (and how many points it's about to spin).
    var selectedPointCount: Int = 0

    /// The angle last dialed into the Inspector's point-rotation field, so the
    /// field can show where it left off. There's no persisted "this selection's
    /// rotation" the way there is `node.rotation` — rotating points bakes the
    /// turn directly into their coordinates — so this resets to 0 whenever the
    /// point selection changes (a fresh dial for a fresh selection).
    var pointSelectionRotation: Double = 0

    /// A direct, synchronous hook the canvas installs while the node tool has
    /// points selected. The Inspector calls it with a DELTA in degrees (not an
    /// absolute angle — it computes that itself from `pointSelectionRotation`)
    /// to rotate the selected points about their own bounding-box centre.
    /// Same channel shape as `applyTextStyle`. nil = no points selected.
    @ObservationIgnored var applyPointRotation: ((Double) -> Void)?

    func toggleNotes(_ id: UUID) {
        if openNotesArtboardIDs.contains(id) { openNotesArtboardIDs.remove(id) }
        else { openNotesArtboardIDs.insert(id) }
    }
}

/// The canvas tools. Select manipulates existing things; the shape tools draw
/// new nodes. After drawing one shape we snap back to `.select`.
enum Tool: Hashable {
    case pan         // hand tool: drag pans the canvas (never selects/moves)
    case select
    case node        // direct selection: edit a path's points/handles
    case rectangle
    case ellipse
    case polygon
    case line
    case pen
    case text
    case image       // action tool: opens the importer (reverts to select)
    case component   // action tool: makes an empty component + opens its editor

    var symbolName: String {
        switch self {
        case .pan:       return "hand.point.up.left.fill"
        case .select:    return "pointer.arrow"
        case .node:      return "beziercurve"
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .polygon:   return "triangleshape"
        case .line:      return "line.diagonal"
        case .pen:       return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .text:      return "character.textbox"
        case .image:     return "photo.fill"
        case .component: return "square.on.square.squareshape.controlhandles"
        }
    }

    var label: String {
        switch self {
        case .pan:       return "Pan"
        case .select:    return "Select"
        case .node:      return "Edit Points"
        case .rectangle: return "Rectangle"
        case .ellipse:   return "Ellipse"
        case .polygon:   return "Polygon"
        case .line:      return "Line"
        case .pen:       return "Pen"
        case .text:      return "Text"
        case .image:     return "Place Image"
        case .component: return "New Component"
        }
    }

    /// Keyboard hint shown in tooltips (handled in the canvas's keyDown).
    var shortcutKey: String {
        switch self {
        case .pan:       return "H"
        case .select:    return "V"
        case .node:      return "A"
        case .rectangle: return "R"
        case .ellipse:   return "O"
        case .polygon:   return "G"
        case .line:      return "L"
        case .pen:       return "P"
        case .text:      return "T"
        case .image:     return "\u{21E7}\u{2318}P"
        case .component: return ""
        }
    }
}
