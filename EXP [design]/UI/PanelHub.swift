//
//  PanelHub.swift
//  EXP [design]
//
//  The SHARED panel state for Multi-Window mode. Floating panels are app-wide,
//  not per-document: no matter how many documents are open, there is ONE set of
//  tray windows, and they reflect whichever document is frontmost.
//
//  So the tray arrangement (which panels in which tray, their frames/collapse)
//  lives here — a single global, persisted store — and the panel CONTENT is
//  pointed at the "active" document, which updates as you switch document
//  windows. (Per-window things — the single-window docks, the workspace mode —
//  stay on each document's AppState.)
//

import SwiftUI
import AppKit

@MainActor
@Observable
final class PanelHub {
    static let shared = PanelHub()

    /// The shared multi-window arrangement (persisted, app-wide).
    var trays: [PanelTray] = [] { didSet { saveTrays() } }

    /// Every live document window's state, weakly held so a closed document is not
    /// kept alive. `activeApp` alone is not enough: switching workspace mode has to
    /// reach EVERY open document, not just the frontmost one.
    @ObservationIgnored private var registeredApps: [WeakAppState] = []
    /// Breaks the propagation loop — each `workspaceMode` write fires its own `didSet`.
    @ObservationIgnored private var propagatingMode = false

    private struct WeakAppState { weak var value: AppState? }

    /// Panel being dragged by its header (so a drop target knows what's incoming).
    @ObservationIgnored var trayDraggingPanel: PanelID?

    /// The frontmost document the shared panels currently target. Weak so panels
    /// never keep a closed document alive.
    weak var activeApp: AppState?
    weak var activeDocument: ExpDocument?
    var activeFileURL: URL?
    @ObservationIgnored var activeUndo: UndoManager?

    /// FEAT-021 — named workspace presets. App-wide, like the trays they contain.
    var presets: [WorkspacePreset] = [] { didSet { savePresets() } }
    /// Which preset was last applied, so the pickers can show a checkmark. Cleared
    /// the moment a preset is deleted; NOT cleared when the user rearranges panels,
    /// because that would make the checkmark flicker on every drag.
    var activePresetID: UUID? { didSet { savePresets() } }

    private static let defaultPanels: [PanelID] = [.layers, .properties, .components, .designLanguage, .handoff]
    private static let traysKey = "exp.trays.v1"
    private static let presetsKey = "exp.workspacePresets.v1"
    private static let activePresetKey = "exp.workspacePresets.active.v1"
    private var restoring = false

    private init() { loadTrays(); loadPresets() }

    // MARK: Workspace presets (FEAT-021)

    private func savePresets() {
        guard !restoring else { return }
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.presetsKey)
        }
        UserDefaults.standard.set(activePresetID?.uuidString, forKey: Self.activePresetKey)
    }

    private func loadPresets() {
        restoring = true
        defer { restoring = false }
        if let data = UserDefaults.standard.data(forKey: Self.presetsKey),
           let p = try? JSONDecoder().decode([WorkspacePreset].self, from: data) {
            presets = p
        }
        if let s = UserDefaults.standard.string(forKey: Self.activePresetKey) {
            activePresetID = UUID(uuidString: s)
        }
    }

    /// Save the current arrangement under `name`. An existing preset with the same
    /// name is REPLACED rather than duplicated — two workspaces called "Laptop" help
    /// nobody.
    @discardableResult
    func savePreset(named name: String, snapshot: WorkspaceSnapshot) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UUID() }
        if let i = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            presets[i].snapshot = snapshot
            activePresetID = presets[i].id
            return presets[i].id
        }
        let preset = WorkspacePreset(name: trimmed, snapshot: snapshot)
        presets.append(preset)
        activePresetID = preset.id
        return preset.id
    }

    /// Overwrite a preset with the current arrangement. Switching presets does NOT
    /// do this on its own — Photoshop's rule, and the less surprising one: an
    /// arrangement you nudged while working should not silently become the saved one.
    func updatePreset(_ id: UUID, snapshot: WorkspaceSnapshot) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].snapshot = snapshot
        activePresetID = id
    }

    func renamePreset(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].name = trimmed
    }

    func deletePreset(_ id: UUID) {
        presets.removeAll { $0.id == id }
        if activePresetID == id { activePresetID = nil }
    }

    /// Replace the tray arrangement, clamping every window onto a screen that is
    /// actually attached.
    func applyTrays(_ incoming: [PanelTray]) {
        trays = incoming.map { tray in
            var t = tray
            t.frame = Self.clampedToAttachedScreen(t.frame)
            return t
        }
    }

    /// A preset saved on a three-monitor desk must not drop a window somewhere this
    /// machine cannot reach. If the frame does not overlap any attached screen by
    /// enough to grab it, move it onto the main screen instead. macOS will otherwise
    /// happily place a window entirely off-screen and leave you with no way back.
    static func clampedToAttachedScreen(_ frame: CGRect) -> CGRect {
        guard frame != .zero, !NSScreen.screens.isEmpty else { return frame }
        let grabbable: CGFloat = 80   // enough width to catch the tray's grab bar
        for screen in NSScreen.screens {
            let overlap = screen.visibleFrame.intersection(frame)
            if !overlap.isNull, overlap.width >= grabbable, overlap.height >= 24 { return frame }
        }
        guard let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return frame }
        var f = frame
        f.size.width = min(f.width, vf.width)
        f.size.height = min(f.height, vf.height)
        f.origin.x = min(max(vf.minX, f.minX), vf.maxX - f.width)
        f.origin.y = min(max(vf.minY, f.minY), vf.maxY - f.height)
        return f
    }

    // MARK: Active document

    /// Remember a document window's state and, if the app is already in Multi-Window
    /// mode, bring the newcomer into it — a window opened while the shared panels are
    /// floating should not appear with docks.
    func register(_ app: AppState) {
        registeredApps.removeAll { $0.value == nil }
        if !registeredApps.contains(where: { $0.value === app }) {
            registeredApps.append(WeakAppState(value: app))
        }
        if let current = registeredApps.compactMap(\.value).first(where: { $0 !== app }),
           current.workspaceMode != app.workspaceMode {
            propagatingMode = true
            app.workspaceMode = current.workspaceMode
            propagatingMode = false
        }
    }

    /// Apply a workspace-mode change to every OTHER open document window.
    func propagateWorkspaceMode(_ mode: AppState.WorkspaceMode, from source: AppState) {
        guard !propagatingMode else { return }
        propagatingMode = true
        registeredApps.removeAll { $0.value == nil }
        for app in registeredApps.compactMap(\.value) where app !== source {
            app.workspaceMode = mode
        }
        propagatingMode = false
        PanelWindowManager.shared.reconcile()
    }

    func setActive(app: AppState, document: ExpDocument, fileURL: URL?, undoManager: UndoManager?) {
        register(app)
        activeApp = app
        activeDocument = document
        activeFileURL = fileURL
        activeUndo = undoManager
    }

    // MARK: Tray queries + mutations

    func isPanelInTrays(_ id: PanelID) -> Bool {
        trays.contains { $0.panels.contains(id) }
    }

    func seedTraysIfNeeded() {
        guard trays.isEmpty else { return }
        trays = Self.defaultPanels.map { PanelTray(panels: [$0]) }
    }

    /// Show a closed panel in its own tray (Window-menu reveal); no-op if shown.
    func ensurePanelTray(_ id: PanelID) {
        guard !isPanelInTrays(id) else { return }
        trays.append(PanelTray(panels: [id]))
    }

    /// Show/hide a panel: add a tray for it, or remove it from its tray.
    func togglePanel(_ id: PanelID) {
        if isPanelInTrays(id) {
            var t = trays
            for i in t.indices { t[i].panels.removeAll { $0 == id }; t[i].collapsed.remove(id) }
            trays = Self.pruned(t)
        } else {
            trays.append(PanelTray(panels: [id]))
        }
    }

    /// Move/merge a panel into a tray at an index (also reorders within a tray).
    func movePanel(_ panel: PanelID, toTray trayID: UUID, at index: Int) {
        var t = trays
        for i in t.indices { t[i].panels.removeAll { $0 == panel }; t[i].collapsed.remove(panel) }
        if let ti = t.firstIndex(where: { $0.id == trayID }) {
            t[ti].panels.insert(panel, at: min(max(0, index), t[ti].panels.count))
        }
        trays = Self.pruned(t)
    }

    func tearOutPanel(_ panel: PanelID) {
        var t = trays
        for i in t.indices { t[i].panels.removeAll { $0 == panel }; t[i].collapsed.remove(panel) }
        t = Self.pruned(t)
        t.append(PanelTray(panels: [panel]))
        trays = t
    }

    func toggleTrayPanelCollapsed(_ panel: PanelID, tray trayID: UUID) {
        guard let ti = trays.firstIndex(where: { $0.id == trayID }) else { return }
        var t = trays
        if t[ti].collapsed.contains(panel) { t[ti].collapsed.remove(panel) }
        else { t[ti].collapsed.insert(panel) }
        trays = t
    }

    func removeTray(_ trayID: UUID) {
        trays = Self.pruned(trays.filter { $0.id != trayID })
    }

    /// Drop empty trays, then dissolve any glue group left with fewer than two
    /// members — a "group" of one is just a window, and leaving the marker on would
    /// make it draw a seam against a neighbour that is no longer connected.
    private static func pruned(_ trays: [PanelTray]) -> [PanelTray] {
        var out = trays.filter { !$0.panels.isEmpty }
        var counts: [UUID: Int] = [:]
        for t in out { if let g = t.groupID { counts[g, default: 0] += 1 } }
        for i in out.indices {
            if let g = out[i].groupID, (counts[g] ?? 0) < 2 { out[i].groupID = nil }
        }
        return out
    }

    // MARK: Glue groups (FEAT-022)

    /// Connect `moving` to `target`, `movingOnLeft` deciding the side.
    ///
    /// Both windows keep their own size AND their own vertical position — the only
    /// thing that changes is that the moving window's facing edge is snapped flush to
    /// the target's, closing the last few points of the gap the dwell gesture already
    /// narrowed. Nothing is realigned, nothing is resized, and no third rectangle is
    /// invented to contain them.
    func glue(_ movingID: UUID, to targetID: UUID, movingOnLeft: Bool) {
        guard movingID != targetID,
              let mi = trays.firstIndex(where: { $0.id == movingID }),
              let ti = trays.firstIndex(where: { $0.id == targetID }) else { return }
        var next = trays
        let group = next[ti].groupID ?? next[mi].groupID ?? UUID()

        // Joining a tray that is already in a group joins THAT group, so a third
        // panel can be added to a pair without the first two coming apart.
        if let existing = next[mi].groupID, existing != group {
            for i in next.indices where next[i].groupID == existing { next[i].groupID = group }
        }
        next[ti].groupID = group
        next[mi].groupID = group

        let target = next[ti].frame
        var frame = next[mi].frame
        if target.width > 1, frame.width > 1 {
            frame.origin.x = movingOnLeft ? target.minX - frame.width : target.maxX
            next[mi].frame = frame
        }
        trays = Self.pruned(next)
    }

    /// Disconnect one tray from its group and nudge it clear, so the seam it was
    /// drawing goes away and it is obvious the two are no longer joined.
    func unglue(_ trayID: UUID) {
        guard let ti = trays.firstIndex(where: { $0.id == trayID }),
              trays[ti].groupID != nil else { return }
        var next = trays
        next[ti].groupID = nil
        next[ti].frame.origin.x += Self.ungluedNudge
        next[ti].frame = Self.clampedToAttachedScreen(next[ti].frame)
        trays = Self.pruned(next)
    }

    /// Far enough that the two edges are visibly apart, and further than the dwell
    /// gesture's snap distance so letting go does not immediately re-connect them.
    static let ungluedNudge: CGFloat = 24

    /// Every tray in `trayID`'s group, left to right. Empty when it is not glued.
    func groupMembers(of trayID: UUID) -> [PanelTray] {
        guard let group = trays.first(where: { $0.id == trayID })?.groupID else { return [] }
        return trays.filter { $0.groupID == group }.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// The tray whose right edge meets `trayID`'s left edge in the same group.
    /// This is what a window uses to know it should draw a seam, and how tall.
    func leftNeighbour(of trayID: UUID) -> PanelTray? {
        let members = groupMembers(of: trayID)
        guard let i = members.firstIndex(where: { $0.id == trayID }), i > 0 else { return nil }
        return members[i - 1]
    }

    /// The vertical range two glued windows actually SHARE, in screen points
    /// (y-UP), or nil when they do not overlap at all. Item 4's "the height the two
    /// panels actually share" — which is a meaningful phrase precisely because they
    /// are allowed to sit at different heights.
    static func sharedSpan(_ a: CGRect, _ b: CGRect) -> (top: CGFloat, height: CGFloat)? {
        let top = min(a.maxY, b.maxY)
        let bottom = max(a.minY, b.minY)
        guard top - bottom > 1 else { return nil }
        return (top, top - bottom)
    }

    func setTrayFrame(_ trayID: UUID, _ frame: CGRect) {
        guard let ti = trays.firstIndex(where: { $0.id == trayID }), trays[ti].frame != frame else { return }
        trays[ti].frame = frame
    }

    // MARK: Persistence (app-wide)

    private func saveTrays() {
        guard !restoring else { return }
        if let data = try? JSONEncoder().encode(trays) {
            UserDefaults.standard.set(data, forKey: Self.traysKey)
        }
    }

    private func loadTrays() {
        guard let data = UserDefaults.standard.data(forKey: Self.traysKey),
              let t = try? JSONDecoder().decode([PanelTray].self, from: data) else { return }
        restoring = true
        trays = t
        restoring = false
    }
}
