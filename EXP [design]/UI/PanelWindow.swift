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
//  FEAT-022 — trays can be GLUED into a group. A group is still N separate
//  windows, each at its own size and position; `NSWindow.addChildWindow` is what
//  makes macOS move and order them together. See `PanelTray.groupID` for why the
//  first attempt (merge into one window with columns) was thrown away.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Glue metrics (FEAT-022)

/// One place to tune the connect gesture and the seam — the owner's design
/// explicitly flagged the glue's width as "needs tuning" (item 7).
enum GlueMetric {
    /// Width of the seam drawn inside a window along an edge it is glued on.
    static let seamWidth: CGFloat = 14
    /// How far in from the window's leading edge the unlink button starts. The seam
    /// sits exactly on top of the window's resize border, which wins every click in
    /// that band, so the button has to begin past it.
    static let seamResizeGutter: CGFloat = 9
    /// The unlink button that rides at the vertical middle of the seam (item 5).
    static let unlinkButton: CGFloat = 18
    /// How close two facing window edges must come for the insertion line (item 1).
    static let snapDistance: CGFloat = 14
    /// The seam spans the SHARED height (item 4), so vertical alignment is free
    /// (item 2) but there must be *some* overlap or there is no seam to draw.
    static let minVerticalOverlap: CGFloat = 40
}

@MainActor
final class PanelWindowManager {
    static let shared = PanelWindowManager()

    private var controllers: [UUID: NSWindowController] = [:]   // keyed by tray id (global)
    private var delegates: [UUID: TrayWindowDelegate] = [:]
    /// Which tray acts as each group's AppKit parent window — the one whose movement
    /// the others follow. It is STABLE for the life of the group (the leftmost member
    /// when the group forms), and deliberately never changes because the user grabbed
    /// a different window: re-parenting mid-drag is what produced the crash logged
    /// against this feature on 2026-08-20. A window that is not the parent moves the
    /// parent instead — see `WindowMoveArea`.
    private var groupParents: [UUID: UUID] = [:]
    /// True while WE close windows (mode switch / merge), so the close delegate
    /// doesn't treat it as a user closing the tray.
    private var programmaticClose = false
    /// Re-entrancy guard for `applyGrouping()`: `addChildWindow` orders the window it
    /// adopts, and that is heard by our own window delegates.
    private var regroupingInFlight = false
    /// Each tray window's frame as of the last callback, so a move or resize can be
    /// read as a DELTA. AppKit hands us the new frame, never the change.
    private var lastFrames: [UUID: CGRect] = [:]
    /// True while we are shuffling a group's windows along after a resize, so their
    /// moves are not mistaken for the user dragging them.
    private var reflowingGroup = false

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
        applyGrouping()
    }

    /// A tray window may take KEY status (its text fields need it) but never
    /// MAIN — the document window stays `NSApp.mainWindow`, so canvas actions
    /// (`sendCanvasAction`) and menu validation keep routing to the focused
    /// canvas while a panel has focus. Standard macOS inspector semantics.
    private final class TrayWindow: NSWindow {
        override var canBecomeMain: Bool { false }

        /// FEAT-022 — a glued FOLLOWER hands its drag to the window it follows.
        ///
        /// **This is the difference between smooth and unusable, so it is worth
        /// being precise.** The version before this let a follower drag itself and
        /// then chased it: read the follower's movement, apply the delta to the
        /// parent, let AppKit carry the rest. It lagged exactly the way Session 80
        /// lagged, and for the same reason — the group was being animated by our
        /// code one tick behind the mouse, so windows arrived at different times and
        /// could be left overlapping or gapped when the drag stopped.
        ///
        /// `performDrag(with:)` hands the whole gesture to AppKit's own window-drag
        /// loop, running on the PARENT. The follower never moves under its own power
        /// at all; it moves because it is a child window. Zero code per tick, and it
        /// is the same code path as dragging any macOS window by its titlebar.
        ///
        /// Intercepting in `sendEvent` rather than in a view is deliberate: these
        /// windows are `fullSizeContentView`, so the top strip belongs to the
        /// TITLEBAR and a drag there never reaches any view of ours.
        override func sendEvent(_ event: NSEvent) {
            if event.type == .leftMouseDown, let parent, shouldDrag(event) {
                parent.performDrag(with: event)
                return
            }
            super.sendEvent(event)
        }

        /// True ONLY for the two regions that are meant to start a window drag: the
        /// titlebar strip (minus its buttons) and our own grab bar.
        ///
        /// **This has to be exact, because `sendEvent` swallowing a click is total.**
        /// The first version measured the titlebar as
        /// `frame.height - contentLayoutRect.height` with no ceiling, and asked a
        /// generic `mouseDownCanMoveWindow` of whatever view was hit — an
        /// `NSHostingView` can answer yes. Between them, every click anywhere in a
        /// FOLLOWER window turned into a group drag: no buttons, no layer selection,
        /// no layer reordering, the whole panel draggable (owner, 2026-08-20). The
        /// strip is now clamped to a plausible titlebar height, and the only view
        /// that counts is our own marker class.
        private func shouldDrag(_ event: NSEvent) -> Bool {
            let point = event.locationInWindow
            let onButton = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { standardWindowButton($0) }
                .contains { $0.convert($0.bounds, to: nil).insetBy(dx: -4, dy: -4).contains(point) }
            if onButton { return false }
            let measured = frame.height - contentLayoutRect.height
            let titlebar = min(40, max(0, measured))   // never the whole window
            if titlebar > 0, point.y >= frame.height - titlebar { return true }
            return contentView?.hitTest(point) is WindowDragRegionView
        }
    }

    private func open(_ tray: PanelTray) {
        let hosting = NSHostingController(rootView: AnyView(TrayWindowView(trayID: tray.id)))
        let window = TrayWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]  // content fills under the titlebar so the glass+gradient reach the very top
        window.isOpaque = false                 // let the behind-window glass show
        window.backgroundColor = .clear
        window.title = tray.panels.map(\.title).joined(separator: " · ")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true            // we list panels ourselves
        // These are palettes, not peer document windows. Floating level keeps every
        // tray above ordinary windows on every attached display while EXP is active;
        // hiding on deactivation prevents them from hovering over another app. When
        // EXP is reactivated—whether by Command-Tab or by clicking its canvas—AppKit
        // restores the trays together at the front, matching standard pro-app panels.
        window.level = .floating
        window.hidesOnDeactivate = true
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
        groupParents.removeAll()
        lastFrames.removeAll()
    }

    // MARK: Glue groups (FEAT-022)

    /// Make AppKit's parent/child links match the hub's glue groups.
    ///
    /// **Idempotent on purpose.** `reconcile()` runs on every `trays` change, and
    /// `trays` changes on every recorded window move — so tearing the links down and
    /// rebuilding them here would re-parent N windows on every drag tick, which is
    /// precisely the Session 80 failure this design exists to avoid. Steady state
    /// must do nothing at all, so each window is only touched when its parent is
    /// actually wrong.
    func applyGrouping() {
        guard !regroupingInFlight else { return }
        regroupingInFlight = true
        defer { regroupingInFlight = false }
        let hub = PanelHub.shared
        var groups: [UUID: [UUID]] = [:]
        for tray in hub.trays.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            if let g = tray.groupID { groups[g, default: []].append(tray.id) }
        }
        groupParents = groupParents.filter { groups[$0.key]?.contains($0.value) == true }

        var desiredParent: [UUID: NSWindow] = [:]
        for (groupID, members) in groups where members.count > 1 {
            let parentID = groupParents[groupID] ?? members[0]     // leftmost by default
            groupParents[groupID] = parentID
            guard let parent = controllers[parentID]?.window else { continue }
            for id in members where id != parentID { desiredParent[id] = parent }
        }

        // TWO PASSES, and the order is the whole point.
        //
        // Detaching and attaching in one pass over an unordered dictionary can
        // attach B to A while A is STILL a child of B — a parent/child CYCLE, which
        // sends AppKit into unbounded recursion inside `addChildWindow` and kills
        // the app with a ~27,500-frame stack overflow (reported 2026-08-20; the
        // give-away was that none of the repeated frames were ours). Every stale
        // link has to be gone before the first new one is made.
        for (id, controller) in controllers {
            guard let window = controller.window else { continue }
            if window.parent !== desiredParent[id] { window.parent?.removeChildWindow(window) }
        }
        for (id, controller) in controllers {
            guard let window = controller.window else { continue }
            let want = desiredParent[id]
            if let want, want !== window, window.parent !== want {
                want.addChildWindow(window, ordered: .above)
            }
            // Item 11 — ⌘` should land on a glued group ONCE, so only its parent
            // takes part in cycling; the windows following it are not separate stops.
            if want == nil { window.collectionBehavior.remove(.ignoresCycle) }
            else { window.collectionBehavior.insert(.ignoresCycle) }
        }
    }

    /// A tray window moved. Nothing to do for a group any more — a follower's drag
    /// IS its parent's drag (see `TrayWindow.sendEvent`), so AppKit has already moved
    /// everything. We only keep the last frame, which the resize reflow needs.
    func trayDidMove(_ trayID: UUID, to frame: CGRect) {
        lastFrames[trayID] = frame
    }

    /// A tray window resized. If it is glued, slide the rest of its group so the
    /// panels stay flush instead of tearing open a gap or sliding under each other.
    func trayDidResize(_ trayID: UUID, to frame: CGRect) {
        let previous = lastFrames[trayID]
        lastFrames[trayID] = frame
        guard !reflowingGroup, !regroupingInFlight,
              let old = previous, old != .zero,
              let group = PanelHub.shared.trays.first(where: { $0.id == trayID })?.groupID
        else { return }
        let dRight = frame.maxX - old.maxX
        let dLeft = frame.minX - old.minX
        guard abs(dRight) > 0.5 || abs(dLeft) > 0.5 else { return }

        reflowingGroup = true
        defer { reflowingGroup = false }
        for member in PanelHub.shared.trays where member.groupID == group && member.id != trayID {
            guard let window = controllers[member.id]?.window else { continue }
            // Live frames, not the hub's — mid-resize the recorded ones lag.
            if abs(dRight) > 0.5, window.frame.minX >= old.maxX - 2 {
                window.setFrameOrigin(NSPoint(x: window.frame.minX + dRight, y: window.frame.minY))
            } else if abs(dLeft) > 0.5, window.frame.maxX <= old.minX + 2 {
                window.setFrameOrigin(NSPoint(x: window.frame.minX + dLeft, y: window.frame.minY))
            }
            PanelHub.shared.setTrayFrame(member.id, window.frame)
            lastFrames[member.id] = window.frame
        }
    }

    /// Move every open tray window to the frame its tray now records.
    ///
    /// `reconcile()` deliberately only opens and closes windows — nothing moved an
    /// ALREADY-OPEN one, because during normal use the frames flow the other way
    /// (the window moves, the delegate records it). Restoring a workspace preset is
    /// the one case that needs the reverse, so it gets its own explicit call rather
    /// than making reconcile fight the user's dragging (FEAT-021).
    ///
    /// Group links are dropped first: moving a parent drags its children with it,
    /// which would fight the absolute frames we are about to set.
    func applyTrayFrames() {
        for (_, controller) in controllers {
            if let window = controller.window, let parent = window.parent {
                parent.removeChildWindow(window)
            }
        }
        for tray in PanelHub.shared.trays where tray.frame != .zero {
            controllers[tray.id]?.window?.setFrame(tray.frame, display: true, animate: false)
        }
        applyGrouping()
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
        if let window = controllers[trayID]?.window, let parent = window.parent {
            parent.removeChildWindow(window)
        }
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
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let id = trayID
        let frame = window.frame
        MainActor.assumeIsolated {
            PanelHub.shared.setTrayFrame(id, frame)
            PanelWindowManager.shared.trayDidMove(id, to: frame)
            GlueGesture.shared.windowMoved(trayID: id, frame: frame)
        }
    }
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let id = trayID
        let frame = window.frame
        MainActor.assumeIsolated {
            PanelHub.shared.setTrayFrame(id, frame)
            PanelWindowManager.shared.trayDidResize(id, to: frame)
        }
    }
    func windowWillClose(_ notification: Notification) {
        let id = trayID
        MainActor.assumeIsolated { PanelWindowManager.shared.trayWindowClosed(id) }
    }
}

// MARK: - The connect gesture (FEAT-022 items 1–3, 10)

/// While a tray window is being dragged, watch for another tray's facing edge
/// coming within `GlueMetric.snapDistance` and show a vertical insertion line
/// between them (item 1). Vertical alignment is irrelevant (item 2). If the drag
/// then PAUSES, the line transitions to an "armed" state (item 3) and releasing
/// connects the two. Releasing before the pause leaves them merely adjacent
/// (item 10) — nobody is forced into a connection.
///
/// **Dwell = the system's own spring-loading delay**, read from
/// `com.apple.springing.delay` rather than guessed, so someone who has lengthened
/// it for motor reasons gets this gesture at their own pace, and someone who has
/// turned springing off gets no dwell gestures at all (the header pop-out /
/// drag-into-a-tray routes still work, so the feature stays reachable).
///
/// **Why polling, not an event monitor.** Ending the gesture needs "mouse button
/// released", and a native window drag runs its own event loop that a local
/// monitor cannot be relied on to see. A global mouse-MOVED monitor would cost the
/// app's input-to-frame budget; a 30 Hz timer that only exists while two panels
/// are actually near each other costs nothing by comparison and reads
/// `NSEvent.pressedMouseButtons` directly.
@MainActor
final class GlueGesture {
    static let shared = GlueGesture()
    private init() {}

    private var indicator: GlueIndicatorWindow?
    private var timer: Timer?
    private var movingID: UUID?
    private var candidate: Candidate?
    private var lastOrigin: CGPoint?
    private var stillSince: Date?
    private var armed = false

    private struct Candidate: Equatable { let trayID: UUID; let movingOnLeft: Bool }

    /// System spring-loading, honoured rather than reinvented.
    private var springingEnabled: Bool {
        UserDefaults.standard.object(forKey: "com.apple.springing.enabled") as? Bool ?? true
    }
    private var springingDelay: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "com.apple.springing.delay")
        return v > 0 ? v : 0.5
    }

    /// Called from every tray window's `windowDidMove`.
    func windowMoved(trayID: UUID, frame: CGRect) {
        // Only a live, user-driven drag arms anything: programmatic frame changes
        // (preset restore, unglue) also fire windowDidMove.
        guard springingEnabled,
              NSEvent.pressedMouseButtons & 1 == 1,
              PanelHub.shared.activeApp?.workspaceMode == .multiWindow else { teardown(); return }
        // Dragging a group's parent moves its children too, and each of those
        // reports a move. Only the window the user actually grabbed drives this.
        if let current = movingID, current != trayID { return }
        movingID = trayID

        if let last = lastOrigin, abs(last.x - frame.minX) < 0.5, abs(last.y - frame.minY) < 0.5 {
            // Still — let the dwell clock keep running.
        } else {
            lastOrigin = frame.origin
            stillSince = Date()
            setArmed(false)
        }

        let found = nearestNeighbour(of: trayID, frame: frame)
        if found != candidate {
            candidate = found
            stillSince = Date()
            setArmed(false)
        }
        guard let c = found,
              let target = PanelHub.shared.trays.first(where: { $0.id == c.trayID }) else {
            hideIndicator()
            return
        }
        showIndicator(moving: frame, target: target.frame, movingOnLeft: c.movingOnLeft)
        startTimer()
    }

    private func nearestNeighbour(of trayID: UUID, frame: CGRect) -> Candidate? {
        let trays = PanelHub.shared.trays
        let myGroup = trays.first(where: { $0.id == trayID })?.groupID
        var best: (candidate: Candidate, distance: CGFloat)?
        for tray in trays where tray.id != trayID && tray.frame != .zero {
            // Already connected to this one — nothing to offer.
            if let g = myGroup, tray.groupID == g { continue }
            let overlap = min(frame.maxY, tray.frame.maxY) - max(frame.minY, tray.frame.minY)
            guard overlap >= GlueMetric.minVerticalOverlap else { continue }
            let onLeft = abs(frame.maxX - tray.frame.minX)    // our right edge ↔ their left
            let onRight = abs(frame.minX - tray.frame.maxX)   // our left edge ↔ their right
            if onLeft <= GlueMetric.snapDistance, onLeft < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (Candidate(trayID: tray.id, movingOnLeft: true), onLeft)
            }
            if onRight <= GlueMetric.snapDistance, onRight < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (Candidate(trayID: tray.id, movingOnLeft: false), onRight)
            }
        }
        return best?.candidate
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated { GlueGesture.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // .common so a window-drag loop still runs it
        timer = t
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 == 1 else {
            // Drag over. Armed → connect; not armed → they stay independent (item 10).
            let connect = armed ? (movingID, candidate) : (nil, nil)
            teardown()
            if let moving = connect.0, let c = connect.1 {
                PanelHub.shared.glue(moving, to: c.trayID, movingOnLeft: c.movingOnLeft)
                PanelWindowManager.shared.applyTrayFrames()
            }
            return
        }
        guard !armed, candidate != nil, let since = stillSince else { return }
        if Date().timeIntervalSince(since) >= springingDelay { setArmed(true) }
    }

    /// The "about-to-connect" transition (item 3). Deliberately a size + opacity
    /// STATE change with no animation and no blinking loop: a flashing element is a
    /// vestibular and photosensitivity hazard, and this reads just as clearly.
    private func setArmed(_ value: Bool) {
        guard armed != value else { return }
        armed = value
        indicator?.setArmed(value)
    }

    private func showIndicator(moving: CGRect, target: CGRect, movingOnLeft: Bool) {
        let top = min(moving.maxY, target.maxY)
        let bottom = max(moving.minY, target.minY)
        let height = max(GlueMetric.minVerticalOverlap, top - bottom)
        let x = movingOnLeft ? (moving.maxX + target.minX) / 2 : (moving.minX + target.maxX) / 2
        let window = indicator ?? GlueIndicatorWindow()
        indicator = window
        window.place(x: x, top: top, height: height, armed: armed)
        window.orderFront(nil)
    }

    private func hideIndicator() {
        indicator?.orderOut(nil)
        indicator = nil
        candidate = nil
        armed = false
    }

    private func teardown() {
        timer?.invalidate(); timer = nil
        indicator?.orderOut(nil); indicator = nil
        movingID = nil; candidate = nil; lastOrigin = nil; stillSince = nil; armed = false
    }
}

/// The vertical insertion line drawn BETWEEN two tray windows — same language as
/// the Layers drop line (item 1), just rotated. Borderless, click-through, and
/// excluded from window cycling so it never becomes a thing you can tab to.
private final class GlueIndicatorWindow: NSWindow {
    private let line = NSView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        line.wantsLayer = true
        contentView = line
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func place(x: CGFloat, top: CGFloat, height: CGFloat, armed: Bool) {
        let w: CGFloat = armed ? 6 : EXPMetric.strokeDropline
        setFrame(CGRect(x: x - w / 2, y: top - height, width: w, height: height), display: true)
        paint(armed: armed, width: w)
    }

    func setArmed(_ value: Bool) {
        let f = frame
        let w: CGFloat = value ? 6 : EXPMetric.strokeDropline
        setFrame(CGRect(x: f.midX - w / 2, y: f.minY, width: w, height: f.height), display: true)
        paint(armed: value, width: w)
    }

    private func paint(armed: Bool, width: CGFloat) {
        line.layer?.backgroundColor = EXPColor.accentNS
            .withAlphaComponent(armed ? 1 : 0.55).cgColor
        line.layer?.cornerRadius = armed ? width / 2 : 0
    }
}

// MARK: - Tray window content

/// One tray window: a grab bar + a stack of its panels, all pointed at the
/// frontmost document via `PanelHub`. Switching documents re-renders the content
/// for the new active document.
///
/// When this tray is glued to one on its left (FEAT-022), it also draws the seam
/// along that edge — inside its own bounds, spanning only the height the two
/// windows share, with the unlink button at the middle of that span.
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
        .expInterfaceTypeSize()
        .background(WindowGlassBackground(active: controlActiveState == .key))
        .expTopEdge()   // a touch more opaque at the very top (the grab bar)
        .overlay(alignment: .topLeading) { seam }
    }

    @ViewBuilder
    private func content(tray: PanelTray, document: ExpDocument) -> some View {
        VStack(spacing: 0) {
            // Always present, even for a lone panel: it is the one place guaranteed
            // to drag the window (a panel header's drag already means "move this
            // panel to another tray"), and a single-panel tray used to have no drag
            // handle at all except the empty titlebar strip.
            grabBar(tray: tray)
            Divider()
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
        .padding(.leading, hub.leftNeighbour(of: trayID) == nil ? 0 : GlueMetric.seamWidth)
    }

    private var insertionLine: some View {
        Rectangle().fill(EXPColor.accent).frame(height: EXPMetric.strokeDropline)
    }

    private func grabBar(tray: PanelTray) -> some View {
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

    // MARK: The seam (FEAT-022 items 4, 5, 6, 9)

    /// Drawn inside THIS window along the edge it meets its left neighbour on, so
    /// there is no extra window and no shared rectangle. It spans only the vertical
    /// range the two windows actually overlap (item 4) and re-computes from their
    /// live frames, so resizing either one re-spans it and re-centres the button
    /// (item 9) with no extra bookkeeping.
    @ViewBuilder
    private var seam: some View {
        if let tray, let left = hub.leftNeighbour(of: trayID),
           let span = PanelHub.sharedSpan(tray.frame, left.frame) {
            let offset = max(0, tray.frame.maxY - span.top)
            // The seam carries NO drag of its own.
            //
            // Item 6 asked for it, and it was built that way, but in this window the
            // seam sits on top of the leading resize border AND over the Layers list,
            // so a move area there fought the column resize and then broke layer
            // reordering. Owner's call, 2026-08-20: *"remove the dragging from within
            // that gutter... keep the moving of the linked panels only on the header
            // bars."* Moving a group from any panel's top strip already works, so the
            // gesture is not lost — only the crowded place to perform it is.
            Rectangle()
                .fill(EXPColor.surfaceToolbar)
                .frame(width: GlueMetric.seamWidth, height: span.height)
                .allowsHitTesting(false)
                .overlay(alignment: .leading) {
                    Rectangle().fill(EXPColor.accentSubtle2)
                        .frame(width: EXPMetric.strokeDropline)
                        .allowsHitTesting(false)
                }
                // Past the resize border, and allowed to overhang into the panel: the
                // one thing in the seam that IS meant to take a click.
                .overlay(alignment: .leading) {
                    unlinkButton.offset(x: GlueMetric.seamResizeGutter)
                }
                .padding(.top, offset)
        }
    }

    private var unlinkButton: some View {
        let title = tray?.panels.map(\.title).joined(separator: ", ") ?? ""
        return Button {
            hub.unglue(trayID)
            PanelWindowManager.shared.applyTrayFrames()
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(EXPColor.textSecondary)
                .frame(width: GlueMetric.unlinkButton, height: GlueMetric.unlinkButton)
                .background(Circle().fill(EXPColor.surfacePanelSolid))
                .overlay(Circle().stroke(EXPColor.hairline, lineWidth: EXPMetric.strokeHairline))
                .padding(3)                    // a little slack around an 18pt target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Disconnect “\(title)” from the panel on its left")
        .accessibilityLabel("Disconnect \(title) from the panel on its left")
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
/// (the tray's grab bar, and the glue seam).
///
/// Every tray window drags itself, including a glued follower — carrying the rest
/// of the group is handled afterwards, in `PanelWindowManager.trayDidMove`, because
/// a `fullSizeContentView` window shares its top strip with the titlebar and a
/// titlebar drag never reaches this view at all.
///
/// NOTE: nothing SwiftUI draws may sit ON TOP of one of these — the hosting view
/// takes the hit test and the drag is lost. Put a move area BESIDE the controls it
/// shares space with, never behind them.
private struct WindowMoveArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragRegionView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The ONLY view class allowed to start a window drag. `TrayWindow.shouldDrag`
/// tests for this type by name rather than asking a view whether it happens to
/// return `mouseDownCanMoveWindow` — plenty of views say yes to that, including
/// `NSHostingView`, and one false yes turns a whole panel into a drag handle.
private final class WindowDragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
