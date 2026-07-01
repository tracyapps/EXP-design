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

    /// Panel being dragged by its header (so a drop target knows what's incoming).
    @ObservationIgnored var trayDraggingPanel: PanelID?

    /// The frontmost document the shared panels currently target. Weak so panels
    /// never keep a closed document alive.
    weak var activeApp: AppState?
    weak var activeDocument: ExpDocument?
    @ObservationIgnored var activeUndo: UndoManager?

    private static let defaultPanels: [PanelID] = [.layers, .properties, .components]
    private static let traysKey = "exp.trays.v1"
    private var restoring = false

    private init() { loadTrays() }

    // MARK: Active document

    func setActive(app: AppState, document: ExpDocument, undoManager: UndoManager?) {
        activeApp = app
        activeDocument = document
        activeUndo = undoManager
    }

    // MARK: Tray queries + mutations

    func isPanelInTrays(_ id: PanelID) -> Bool { trays.contains { $0.panels.contains(id) } }

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
            t.removeAll { $0.panels.isEmpty }
            trays = t
        } else {
            trays.append(PanelTray(panels: [id]))
        }
    }

    /// Move/merge a panel into a tray at an index (also reorders within a tray).
    func movePanel(_ panel: PanelID, toTray trayID: UUID, at index: Int) {
        var t = trays
        for i in t.indices { t[i].panels.removeAll { $0 == panel }; t[i].collapsed.remove(panel) }
        if let ti = t.firstIndex(where: { $0.id == trayID }) {
            let idx = min(max(0, index), t[ti].panels.count)
            t[ti].panels.insert(panel, at: idx)
        }
        t.removeAll { $0.panels.isEmpty }
        trays = t
    }

    func tearOutPanel(_ panel: PanelID) {
        var t = trays
        for i in t.indices { t[i].panels.removeAll { $0 == panel }; t[i].collapsed.remove(panel) }
        t.removeAll { $0.panels.isEmpty }
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

    func removeTray(_ trayID: UUID) { trays.removeAll { $0.id == trayID } }

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
