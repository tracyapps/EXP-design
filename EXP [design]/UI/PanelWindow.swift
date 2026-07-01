//
//  PanelWindow.swift
//  EXP [design]
//
//  Phase 13c — Multi-window "tray" windows, shared across documents. The tray
//  arrangement + active-document context live in `PanelHub.shared`, so there is
//  ONE global set of tray windows no matter how many documents are open; their
//  content points at whichever document is frontmost (`hub.activeApp/Document`).
//
//  The manager maps `hub.trays` → windows (one per tray, keyed by tray id),
//  opening/closing them to match and recording each window's frame back into the
//  hub as it's moved. `reconcile()` is the single entry point: it shows the trays
//  when the active document is in Multi-Window mode, and hides them otherwise.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class PanelWindowManager {
    static let shared = PanelWindowManager()

    private var controllers: [UUID: NSWindowController] = [:]   // keyed by tray id (global)
    private var delegates: [UUID: TrayWindowDelegate] = [:]
    /// True while WE close windows (mode switch / merge), so the close delegate
    /// doesn't treat it as a user closing the tray.
    private var programmaticClose = false

    /// Bring the shared tray windows in line with the hub + active document.
    func reconcile() {
        let hub = PanelHub.shared
        guard let active = hub.activeApp, active.workspaceMode == .multiWindow else {
            closeAll()
            return
        }
        hub.seedTraysIfNeeded()
        let wanted = Set(hub.trays.map { $0.id })
        for (id, controller) in controllers where !wanted.contains(id) {
            programmaticClose = true; controller.close(); programmaticClose = false
            controllers[id] = nil; delegates[id] = nil
        }
        for tray in hub.trays where controllers[tray.id] == nil {
            open(tray)
        }
    }

    private func open(_ tray: PanelTray) {
        let hosting = NSHostingController(rootView: AnyView(TrayWindowView(trayID: tray.id)))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]  // content fills under the titlebar so the glass+gradient reach the very top
        window.isOpaque = false                 // let the behind-window glass show
        window.backgroundColor = .clear
        window.title = tray.panels.map(\.title).joined(separator: " · ")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true            // we list panels ourselves
        window.standardWindowButton(.zoomButton)?.isHidden = true

        if tray.frame != .zero {
            window.setFrame(tray.frame, display: false)
        } else {
            window.setContentSize(NSSize(width: 300, height: 460))
            let i = PanelHub.shared.trays.firstIndex { $0.id == tray.id } ?? 0
            if let vf = NSScreen.main?.visibleFrame {
                window.setFrameTopLeftPoint(NSPoint(x: vf.maxX - 320 - CGFloat(i) * 26,
                                                    y: vf.maxY - 24 - CGFloat(i) * 30))
            } else {
                window.center()
            }
            PanelHub.shared.setTrayFrame(tray.id, window.frame)
        }

        let delegate = TrayWindowDelegate(trayID: tray.id)
        window.delegate = delegate
        delegates[tray.id] = delegate

        let controller = NSWindowController(window: window)
        controllers[tray.id] = controller
        controller.showWindow(nil)
        window.orderFront(nil)   // show without stealing key from the document
    }

    private func closeAll() {
        for (id, controller) in controllers {
            programmaticClose = true; controller.close(); programmaticClose = false
            controllers[id] = nil; delegates[id] = nil
        }
    }

    /// Bring the window hosting `panel` to the front (Window-menu "reveal").
    func focusPanel(_ panel: PanelID) {
        guard let tray = PanelHub.shared.trays.first(where: { $0.panels.contains(panel) }) else { return }
        controllers[tray.id]?.window?.makeKeyAndOrderFront(nil)
    }

    /// A tray window closed. A USER close (its ✕) drops the tray from the hub so
    /// its panels read as "closed" (reopenable from the Window menu); our own
    /// programmatic closes leave the hub intact.
    func trayWindowClosed(_ trayID: UUID) {
        controllers[trayID] = nil
        delegates[trayID] = nil
        if !programmaticClose { PanelHub.shared.removeTray(trayID) }
    }
}

/// Vends the active document's undo manager and records the tray window's frame
/// back into the hub as it moves/resizes; a user close drops the tray.
private final class TrayWindowDelegate: NSObject, NSWindowDelegate {
    let trayID: UUID
    init(trayID: UUID) { self.trayID = trayID }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        MainActor.assumeIsolated { PanelHub.shared.activeUndo }
    }
    func windowDidMove(_ notification: Notification) { record(notification) }
    func windowDidResize(_ notification: Notification) { record(notification) }
    func windowWillClose(_ notification: Notification) {
        let id = trayID
        MainActor.assumeIsolated { PanelWindowManager.shared.trayWindowClosed(id) }
    }
    private func record(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let id = trayID
        MainActor.assumeIsolated { PanelHub.shared.setTrayFrame(id, window.frame) }
    }
}

// MARK: - Tray window content

/// One tray window: a grab bar (when >1 panel) + a stack of its panels, all
/// pointed at the frontmost document via `PanelHub`. Switching documents
/// re-renders the content for the new active document.
struct TrayWindowView: View {
    let trayID: UUID
    @State private var dropIndex: Int?
    // Reflects the window's active/key state — drives the "thinner glass when
    // inactive" behaviour (instead of the default darken-on-resign-key).
    @Environment(\.controlActiveState) private var controlActiveState
    private var hub: PanelHub { .shared }
    private var tray: PanelTray? { hub.trays.first { $0.id == trayID } }

    var body: some View {
        Group {
            if let tray, let app = hub.activeApp, let document = hub.activeDocument {
                content(tray: tray, document: document)
                    .environment(app)   // so the hosted panels read the active doc's state
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WindowGlassBackground(active: controlActiveState == .key))
        .expTopEdge()   // a touch more opaque at the very top (the grab bar)
    }

    @ViewBuilder
    private func content(tray: PanelTray, document: ExpDocument) -> some View {
        VStack(spacing: 0) {
            if tray.panels.count > 1 {
                grabBar
                Divider()
            }
            ForEach(Array(tray.panels.enumerated()), id: \.element) { idx, panel in
                if dropIndex == idx { insertionLine }
                PanelSection(
                    document: document, panel: panel, trayID: trayID, index: idx,
                    isCollapsed: tray.collapsed.contains(panel),
                    canTearOut: tray.panels.count > 1,
                    dropIndex: $dropIndex
                )
            }
            if dropIndex == tray.panels.count { insertionLine }
            Spacer(minLength: 0)
        }
    }

    private var insertionLine: some View {
        Rectangle().fill(EXPColor.accent).frame(height: EXPMetric.strokeDropline)
    }

    private var grabBar: some View {
        Color.clear
            .frame(height: 18)
            .background(EXPColor.surfaceToolbar)
            .overlay(alignment: .leading) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(EXPColor.textTertiary)
                    .padding(.leading, 8)
            }
            .overlay(WindowMoveArea())
    }
}

/// One panel inside a tray: header (tap = collapse, drag = merge/move, pop-out =
/// tear into its own tray) + the panel body when expanded. Tray edits go through
/// `PanelHub`; the body shows the active document.
private struct PanelSection: View {
    @ObservedObject var document: ExpDocument
    let panel: PanelID
    let trayID: UUID
    let index: Int
    let isCollapsed: Bool
    let canTearOut: Bool
    @Binding var dropIndex: Int?
    @State private var sectionHeight: CGFloat = 60
    private var hub: PanelHub { .shared }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isCollapsed {
                Divider()
                panelContent(panel, document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxHeight: isCollapsed ? nil : .infinity, alignment: .top)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { sectionHeight = g.size.height }
                .onChange(of: g.size.height) { _, h in sectionHeight = h }
        })
        .onDrop(of: [.text], delegate: SectionDropDelegate(
            index: index, height: sectionHeight, dropIndex: $dropIndex,
            isDragging: { hub.trayDraggingPanel != nil },
            commit: { target in
                guard let p = hub.trayDraggingPanel else { return }
                hub.movePanel(p, toTray: trayID, at: target)
                hub.trayDraggingPanel = nil
            }))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Image(systemName: panel.icon).font(.system(size: 12, weight: .medium))
            Text(panel.title).font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 4)
            if canTearOut {
                Button { hub.tearOutPanel(panel) } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Pop “\(panel.title)” out into its own window")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(EXPColor.surfaceToolbar)
        .contentShape(Rectangle())
        .onTapGesture { hub.toggleTrayPanelCollapsed(panel, tray: trayID) }
        .onDrag {
            hub.trayDraggingPanel = panel
            return NSItemProvider(object: panel.rawValue as NSString)
        }
    }
}

/// Computes the insertion point (before/after this section) and commits the move
/// on drop. Bindings + closures, so no actor-isolated state is stored.
private struct SectionDropDelegate: DropDelegate {
    let index: Int
    let height: CGFloat
    @Binding var dropIndex: Int?
    let isDragging: () -> Bool
    let commit: (Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { isDragging() }
    func dropEntered(info: DropInfo) { dropIndex = targetIndex(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropIndex = targetIndex(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { dropIndex = nil }
    func performDrop(info: DropInfo) -> Bool {
        commit(targetIndex(info))
        dropIndex = nil
        return true
    }
    private func targetIndex(_ info: DropInfo) -> Int {
        info.location.y < height / 2 ? index : index + 1
    }
}

/// A transparent region that lets a click-drag move the host window natively
/// (used for the tray's grab bar).
private struct WindowMoveArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MoveView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class MoveView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
